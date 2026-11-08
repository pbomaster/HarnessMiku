import Foundation
import Darwin
import MLX

enum AugustModelError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return "미쿠 8B 모델을 열 수 없어. " + reason }
    }
}

/// Reads the original Qwen3 asset. Packed GGML blocks are never requantized.
struct AugustGGUF {
    struct Tensor {
        let width: Int
        let rows: Int
        let type: UInt32
        let array: MLXArray
    }
    struct Entry {
        let name: String
        let width: Int
        let rows: Int
        let type: UInt32
        let offset: Int
    }
    private struct Cursor {
        let data: UnsafeRawBufferPointer
        var offset = 0
        mutating func take(_ length: Int) throws -> UnsafeRawBufferPointer {
            guard length >= 0, offset <= data.count - length else { throw AugustModelError.invalid("파일이 손상됐어.") }
            defer { offset += length }
            return UnsafeRawBufferPointer(rebasing: data[offset..<(offset + length)])
        }
        mutating func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            try take(MemoryLayout<T>.size).loadUnaligned(as: T.self).littleEndian
        }
        mutating func count() throws -> Int {
            let n = try read(UInt64.self)
            guard n <= UInt64(Int.max) else { throw AugustModelError.invalid("잘못된 데이터 길이야.") }
            return Int(n)
        }
        mutating func string() throws -> String {
            let length = try count()
            return String(decoding: try take(length), as: UTF8.self)
        }
        mutating func skip(type: UInt32, count n: Int = 1) throws {
            let bytes: Int
            switch type {
            case 0,1,7: bytes = 1
            case 2,3: bytes = 2
            case 4,5,6: bytes = 4
            case 10,11,12: bytes = 8
            case 8:
                for _ in 0..<n { let length = try count(); _ = try take(length) }
                return
            case 9 where n == 1:
                let t = try read(UInt32.self), number = try count()
                guard t != 9, number <= data.count else { throw AugustModelError.invalid("잘못된 배열이야.") }
                try skip(type: t, count: number)
                return
            default: throw AugustModelError.invalid("지원되지 않는 메타데이터야.")
            }
            guard n <= data.count / bytes else { throw AugustModelError.invalid("배열 길이가 맞지 않아.") }
            _ = try take(n * bytes)
        }
    }

    static func load(_ url: URL) throws -> [String: Tensor] {
        let descriptor = try FileHandle(forReadingFrom: url)
        defer { try? descriptor.close() }
        let page = Int(getpagesize())
        let mapping = try Data(contentsOf: url, options: .alwaysMapped)
        return try mapping.withUnsafeBytes { (region: UnsafeRawBufferPointer) in
            var cursor = Cursor(data: region)
            guard try cursor.read(UInt32.self) == 0x46554747, try cursor.read(UInt32.self) == 3 else {
                throw AugustModelError.invalid("GGUF 3 파일이 필요해.")
            }
            let tensorCount = try cursor.count(), fieldCount = try cursor.count()
            guard tensorCount <= 1024, fieldCount <= 512 else { throw AugustModelError.invalid("모델 정보가 맞지 않아.") }
            var alignment = 32, architecture = ""
            for _ in 0..<fieldCount {
                let key = try cursor.string(), type = try cursor.read(UInt32.self)
                if key == "general.architecture", type == 8 { architecture = try cursor.string() }
                else if key == "general.alignment", type == 4 { alignment = Int(try cursor.read(UInt32.self)) }
                else { try cursor.skip(type: type) }
            }
            guard architecture == "qwen3", alignment > 0, alignment <= 65536 else {
                throw AugustModelError.invalid("August Qwen3 가중치를 확인해 줘.")
            }
            var entries: [Entry] = []
            for _ in 0..<tensorCount {
                let name = try cursor.string(), dimensions = try cursor.read(UInt32.self)
                guard dimensions == 1 || dimensions == 2 else { throw AugustModelError.invalid(name) }
                let width = try cursor.count(), rows = dimensions == 2 ? try cursor.count() : 1
                let type = try cursor.read(UInt32.self), offset = try cursor.count()
                entries.append(.init(name: name, width: width, rows: rows, type: type, offset: offset))
            }
            let base = (cursor.offset + alignment - 1) / alignment * alignment
            var tensors: [String: Tensor] = [:]
            for entry in entries {
                try Task.checkCancellation()
                let w = entry.width, r = entry.rows
                guard (1...151936).contains(w), (1...151936).contains(r), entry.offset <= region.count - base,
                      tensors[entry.name] == nil else { throw AugustModelError.invalid(entry.name) }
                let bytesPerRow: Int
                switch entry.type {
                case 0 where r == 1: bytesPerRow = w * 4
                case 12 where w % 256 == 0: bytesPerRow = w / 256 * 144
                case 14 where w % 256 == 0: bytesPerRow = w / 256 * 210
                default: throw AugustModelError.invalid("지원되지 않는 텐서 " + entry.name)
                }
                let start = base + entry.offset
                guard bytesPerRow <= (region.count - start) / r else { throw AugustModelError.invalid(entry.name) }
                let ptr = UnsafeRawBufferPointer(rebasing: region[start..<(start + bytesPerRow * r)])
                let array: MLXArray
                if entry.type == 0 {
                    array = MLXArray(ptr, [w], type: Float.self).asType(.float16)
                } else {
                    // Wrap a page-aligned private mapping in a managed MLX buffer.
                    // The view excludes padding before and after this tensor.
                    let displacement = start % page
                    let byteCount = bytesPerRow * r
                    let length = (displacement + byteCount + page - 1) / page * page
                    if let address = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_PRIVATE,
                                          descriptor.fileDescriptor, off_t(start - displacement)),
                       address != MAP_FAILED {
                        let buffer = MLXArray(rawPointer: address, [length], dtype: .uint8) {
                            munmap(address, length)
                        }
                        array = buffer[displacement..<(displacement + byteCount)].reshaped(r, bytesPerRow)
                    } else {
                        array = MLXArray(ptr, [r, bytesPerRow], type: UInt8.self)
                    }
                }
                tensors[entry.name] = Tensor(width: w, rows: r, type: entry.type, array: array)
            }
            return tensors
        }
    }
}
