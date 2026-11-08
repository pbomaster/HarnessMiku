import Darwin
import Foundation
import MLX
import MLXNN

/// Read the checkpoint directory once; only the selected rows enter the Metal allocator.
final class StreamedVocabulary {
    fileprivate struct Entry: Decodable {
        let shape: [Int]
        let dtype: String
        let data_offsets: [Int]
    }
    private let file: FileHandle
    private let start: Int
    private let length: Int
    private let entries: [String: Entry]

    init(directory: URL) throws {
        file = try FileHandle(forReadingFrom: directory.appendingPathComponent("model.safetensors"))
        let fileSize = try file.seekToEnd()
        try file.seek(toOffset: 0)
        guard fileSize <= Int.max, let prefix = try file.read(upToCount: 8), prefix.count == 8 else {
            throw InvalidPack("MLX 가중치 헤더가 손상됐어.")
        }
        let size = prefix.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        guard size > 0, size <= 64 << 20, size + 8 < fileSize,
              let data = try file.read(upToCount: Int(size)), data.count == Int(size),
              var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InvalidPack("MLX 가중치 목록을 읽을 수 없어.")
        }
        json.removeValue(forKey: "__metadata__")
        entries = try JSONDecoder().decode([String: Entry].self, from: JSONSerialization.data(withJSONObject: json))
        start = 8 + Int(size)
        length = Int(fileSize) - start
    }

    func make(path: String, block: Int, embedding: Bool) throws -> Module {
        let prefix = entries["language_model." + path + ".weight"] == nil ? path : "language_model." + path
        func map(_ key: String, _ dtype: DType) throws -> VocabularyRows {
            guard let entry = entries[prefix + "." + key] else { throw InvalidPack(prefix + "." + key) }
            return try VocabularyRows(entry: entry, dtype: dtype, file: file, start: start, length: length)
        }
        let w = try map("weight", .uint32), s = try map("scales", .float16), b = try map("biases", .float16)
        guard w.shape.count == 2, s.shape.count == 2, b.shape == s.shape, w.shape[0] == s.shape[0],
              w.shape[1].isMultiple(of: 8), w.shape[1] / 8 == s.shape[1], w.shape[1] <= Int(Int32.max) / 16
        else { throw InvalidPack("2비트 가중치 모양이 맞지 않아: " + path) }
        let width = w.shape[1] * 16
        var signs: MLXArray?
        if block > 0 {
            let signRows = try map("signs", .float32)
            guard [512, 1024, 2048, 4096].contains(block), width.isMultiple(of: block), signRows.shape == [width]
            else { throw InvalidPack("회전 계수 모양이 맞지 않아: " + path) }
            signs = signRows.copy(rows: 0..<width)
        } else if block != 0 || entries[prefix + ".signs"] != nil {
            throw InvalidPack("회전 계수 형식이 맞지 않아: " + path)
        }
        let values = VocabularyValues(weight: w, scales: s, biases: b, signs: signs, block: block)
        if embedding { return StreamedEmbedding(values) }
        return StreamedHead(values, lastTokenOnly: path == "lm_head")
    }

    static func make(directory: URL, path: String, block: Int, embedding: Bool) throws -> Module {
        try StreamedVocabulary(directory: directory).make(path: path, block: block, embedding: embedding)
    }
}

/// Keep these mappings on the CPU side. MLXArray(Data, ...) copies exactly the selected
/// bytes into a new array, so neither a tiny view nor a lazy graph pins the entire file in Metal.
private final class VocabularyRows {
    let shape: [Int]
    private let dtype: DType
    private let base: UnsafeMutableRawPointer
    private let mappedBytes: Int
    private let bytes: UnsafeMutableRawPointer
    private let stride: Int

    init(entry: StreamedVocabulary.Entry, dtype: DType, file: FileHandle, start: Int, length: Int) throws {
        let types: [String: DType] = ["U32": .uint32, "F16": .float16, "F32": .float32]
        guard types[entry.dtype] == dtype, (1...2).contains(entry.shape.count), entry.data_offsets.count == 2 else {
            throw InvalidPack("스트리밍할 텐서 형식이 맞지 않아.")
        }
        let lower = entry.data_offsets[0], upper = entry.data_offsets[1]
        guard lower >= 0, upper > lower, upper <= length else { throw InvalidPack("가중치 파일 범위 오류") }
        let size = upper - lower
        var expected = dtype.size
        for dim in entry.shape {
            guard dim > 0, dim <= Int32.max, dim <= size / expected else { throw InvalidPack("가중치 차원 오류") }
            expected *= dim
        }
        guard expected == size else { throw InvalidPack("가중치 길이 오류") }
        let offset = start + lower
        let delta = offset % Int(getpagesize())
        let mapSize = delta + size
        guard let base = mmap(nil, mapSize, PROT_READ, MAP_PRIVATE, file.fileDescriptor, off_t(offset - delta)),
              base != MAP_FAILED else { throw InvalidPack("가중치 파일을 메모리에 연결할 수 없어.") }
        self.base = base
        self.bytes = base.advanced(by: delta)
        self.mappedBytes = mapSize
        self.shape = entry.shape
        self.dtype = dtype
        self.stride = size / entry.shape[0]
    }
    deinit { munmap(base, mappedBytes) }

    func copy(rows: Range<Int>) -> MLXArray {
        precondition(rows.lowerBound >= 0 && rows.upperBound <= shape[0] && !rows.isEmpty)
        let data = Data(bytesNoCopy: bytes.advanced(by: rows.lowerBound * stride), count: rows.count * stride, deallocator: .none)
        return withExtendedLifetime(self) { MLXArray(data, [rows.count] + shape.dropFirst(), dtype: dtype) }
    }

    func gather(_ ids: [Int32]) -> MLXArray {
        var data = Data(count: ids.count * stride)
        data.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            guard let destination = out.baseAddress else { return }
            for (i, token) in ids.enumerated() {
                let row = Int(token)
                precondition(row >= 0 && row < shape[0])
                destination.advanced(by: i * stride).copyMemory(from: bytes.advanced(by: row * stride), byteCount: stride)
            }
        }
        return MLXArray(data, [ids.count] + shape.dropFirst(), dtype: dtype)
    }
}

private struct VocabularyValues {
    let weight: VocabularyRows
    let scales: VocabularyRows
    let biases: VocabularyRows
    let signs: MLXArray?
    let block: Int

    func project(_ input: MLXArray) -> MLXArray {
        let x = rotate(input, block: block, signs: signs)
        // Evaluate each projection before reading the next block. Only the small output
        // remains live when MLX recycles the packed weights for the next iteration.
        let rows = weight.shape[0]
        let step = rows <= 8192 ? rows : 8192
        var parts = [MLXArray]()
        for first in Swift.stride(from: 0, to: rows, by: step) {
            let range = first..<min(first + step, rows)
            let part = quantizedMatmul(x, weight.copy(rows: range), scales: scales.copy(rows: range),
                                       biases: biases.copy(rows: range), groupSize: 128, bits: 2)
            eval(part)
            parts.append(part)
        }
        return parts.count == 1 ? parts[0] : concatenated(parts, axis: -1)
    }
}

private final class StreamedEmbedding: Embedding {
    private let values: VocabularyValues
    init(_ values: VocabularyValues) {
        self.values = values
        super.init(weight: MLXArray.zeros([1, 1]))
    }
    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        let ids = x.reshaped(-1).asArray(Int32.self)
        let rows = dequantized(values.weight.gather(ids), scales: values.scales.gather(ids),
                               biases: values.biases.gather(ids), groupSize: 128, bits: 2)
        return rotate(rows.reshaped(x.shape + [-1]).asType(.float16), block: values.block, signs: values.signs, inverse: true)
    }
    override func asLinear(_ x: MLXArray) -> MLXArray { values.project(x) }
}

private final class StreamedHead: Linear {
    private let values: VocabularyValues
    private let lastTokenOnly: Bool
    init(_ values: VocabularyValues, lastTokenOnly: Bool) {
        self.values = values
        self.lastTokenOnly = lastTokenOnly
        super.init(weight: MLXArray.zeros([1, 1]))
    }
    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        let hidden = lastTokenOnly && x.ndim == 3 && x.dim(1) > 1 ? x[0..., (-1)..., 0...] : x
        return values.project(hidden)
    }
}
