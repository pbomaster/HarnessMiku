import Darwin
import Foundation
import MLX

/// File-backed, page-aligned Metal allocations keep the compressed weights reclaimable.
enum MappedBonsaiWeights {
    private struct Tensor: Decodable {
        let dtype: String
        let shape: [Int]
        let data_offsets: [Int]
    }

    static func read(_ url: URL, skipping modules: Set<String>) throws -> [String: MLXArray] {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let fileSize = try file.seekToEnd()
        try file.seek(toOffset: 0)
        guard let lengthBytes = try file.read(upToCount: 8), lengthBytes.count == 8 else {
            throw InvalidPack("모델 파일 헤더를 읽을 수 없어.")
        }
        let length = lengthBytes.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        guard length < 64 << 20, length + 8 < fileSize,
              let header = try file.read(upToCount: Int(length)), header.count == Int(length),
              let root = try JSONSerialization.jsonObject(with: header) as? [String: Any] else {
            throw InvalidPack("모델 파일 헤더가 손상됐어.")
        }
        let page = Int(getpagesize())
        let start = Int(length) + 8
        let dtypes: [String: DType] = ["F16": .float16, "F32": .float32, "BF16": .bfloat16, "U32": .uint32]
        var result = [String: MLXArray]()
        for (name, info) in root where name != "__metadata__" && !name.hasPrefix("vision_tower.") {
            let localName = name.hasPrefix("language_model.") ? String(name.dropFirst("language_model.".count)) : name
            if let dot = localName.lastIndex(of: "."), modules.contains(String(localName[..<dot])) { continue }
            try Task.checkCancellation()
            let tensor = try JSONDecoder().decode(Tensor.self, from: JSONSerialization.data(withJSONObject: info))
            guard let dtype = dtypes[tensor.dtype], !tensor.shape.isEmpty, tensor.data_offsets.count == 2 else {
                throw InvalidPack("가중치 형식을 확인할 수 없어: " + name)
            }
            let lower = tensor.data_offsets[0], upper = tensor.data_offsets[1]
            guard lower >= 0, upper > lower, upper <= Int(fileSize) - start else { throw InvalidPack(name) }
            let size = upper - lower
            var expected = dtype.size
            for dim in tensor.shape {
                guard dim > 0, dim <= size / expected else { throw InvalidPack(name) }
                expected *= dim
            }
            guard expected == size else { throw InvalidPack(name) }
            let offset = start + lower
            let delta = offset % page
            let aligned = offset - delta
            let bytes = (delta + size + page - 1) / page * page
            guard let ptr = mmap(nil, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE, file.fileDescriptor, off_t(aligned)),
                  ptr != MAP_FAILED else { throw InvalidPack("모델 메모리 매핑 실패: " + name) }
            let buffer = MLXArray(rawPointer: ptr, [bytes], dtype: .uint8) { munmap(ptr, bytes) }
            result[name] = buffer[delta ..< delta + size].view(dtype: dtype).reshaped(tensor.shape)
        }
        return result
    }
}
