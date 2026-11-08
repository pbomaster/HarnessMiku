import Combine
import CryptoKit
import Darwin
import Foundation

actor BonsaiPack {
    static let shared = BonsaiPack()
    private let operations = ModelInstallOperation.bonsai27
    static let bytes: Int64 = 7_206_168_928
    private static let checksum = "3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1"
    static let file = AugustPack.directory.appendingPathComponent("Ternary-Bonsai-2-27B-PQ2_0.gguf")
    private static let remote = URL(string: "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/839bd57023c1558945afea70a74fa83c054f35f9/Ternary-Bonsai-2-27B-PQ2_0.gguf?download=true")!

    // These byte locations belong only to the SHA-pinned original GGUF. Putting
    // the CPU embedding first makes the following GPU weights contiguous in mmap.
    private static let reorderedChecksum = "ed7002ea8f1d06c5e356bad7ecb5cd8f5c44a248653cdcae233941277b926217"

    private static func normalizeLayout(in url: URL, checking: @Sendable (Double) async -> Void) async throws {
        let first: UInt64 = 11_120_992
        let second: UInt64 = 348_856_672
        let length: UInt64 = 337_715_200
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let stream = try FileHandle(forUpdating: url)
        defer { try? stream.close() }
        func readExactly(offset: UInt64, count: Int) throws -> Data {
            try stream.seek(toOffset: offset)
            guard let block = try stream.read(upToCount: count), block.count == count else {
                throw MikuError("Bonsai 모델 파일을 끝까지 읽을 수 없어.")
            }
            return block
        }
        var offset: UInt64 = 0
        while offset < length {
            try Task.checkCancellation()
            let count = Int(min(UInt64(2 << 20), length - offset))
            let a = try readExactly(offset: first + offset, count: count)
            let b = try readExactly(offset: second + offset, count: count)
            try stream.seek(toOffset: first + offset)
            try stream.write(contentsOf: b)
            try stream.seek(toOffset: second + offset)
            try stream.write(contentsOf: a)
            offset += UInt64(count)
            if offset % (32 << 20) == 0 || offset == length {
                await checking(0.45 + 0.1 * Double(offset) / Double(length))
            }
        }
        // Prism reads descriptors in storage order. Rewrite the first three
        // entries together: embedding, unchanged output norm, then LM head.
        let directory: UInt64 = 11_070_652
        let head = try readExactly(offset: directory, count: 53)
        let norm = try readExactly(offset: directory + 53, count: 50)
        let embedding = try readExactly(offset: directory + 103, count: 57)
        try stream.seek(toOffset: directory)
        func writeDescriptor(_ data: Data, tensorOffset: UInt64) throws {
            try stream.write(contentsOf: data.dropLast(8))
            try withUnsafeBytes(of: tensorOffset.littleEndian) { try stream.write(contentsOf: $0) }
        }
        try writeDescriptor(embedding, tensorOffset: 0)
        try stream.write(contentsOf: norm)
        try writeDescriptor(head, tensorOffset: second - first)
        try stream.synchronize()
        try stream.seek(toOffset: 0)
        let result = try await digest(stream, copyingTo: nil) { value in
            await checking(0.55 + 0.45 * value)
        }
        guard result == reorderedChecksum else {
            throw MikuError("Bonsai 파일 배치를 확인할 수 없어. 다시 가져와 줘.")
        }
    }

    // Hash the complete byte stream and optionally copy it into our unpublished
    // file when a Files provider cannot make an APFS clone.
    private static func digest(_ source: FileHandle, copyingTo destination: FileHandle?,
                               checking: @Sendable (Double) async -> Void) async throws -> String {
        var hash = SHA256()
        var count: Int64 = 0
        var nextReport: Int64 = 0
        while true {
            try Task.checkCancellation()
            guard let block = try source.read(upToCount: 4 << 20), !block.isEmpty else { break }
            hash.update(data: block)
            try destination?.write(contentsOf: block)
            count += Int64(block.count)
            if count >= nextReport {
                await checking(Double(count) / Double(bytes))
                nextReport = count + (32 << 20)
            }
        }
        guard count == bytes else { throw MikuError("모델 파일의 크기가 예상과 달라.") }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static var ready: Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber
        return size?.int64Value == bytes
    }

    // Only publish a complete, verified file on the model directory's volume.
    func install(source: URL?, checking: @escaping @Sendable (Double) async -> Void) async throws {
        try await operations.perform {
            try await self.installFile(source: source, checking: checking)
        }
    }

    static func removeFiles() throws {
        try ModelInstallOperation.removeFiles([file, file.deletingLastPathComponent().appendingPathComponent("Bonsai-PQ2_0.partial")])
    }

    func remove() async throws {
        try await operations.perform(replacing: true, prepare: { try Self.removeFiles() }) {}
    }

    func reinstall(checking: @escaping @Sendable (Double) async -> Void) async throws {
        try await operations.perform(replacing: true, prepare: { try Self.removeFiles() }) {
            try await self.installFile(source: nil, checking: checking)
        }
    }

    private func installFile(source: URL?, checking: @escaping @Sendable (Double) async -> Void) async throws {
        try Task.checkCancellation()
        guard !Self.ready else { return }
        let fm = FileManager.default
        var directory = Self.file.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let temporary = directory.appendingPathComponent("Bonsai-PQ2_0.partial")
        if fm.fileExists(atPath: temporary.path) { try fm.removeItem(at: temporary) }
        defer { try? fm.removeItem(at: temporary) }
        let scoped = source?.startAccessingSecurityScopedResource() == true
        defer { if scoped { source?.stopAccessingSecurityScopedResource() } }
        let input: URL
        if let source {
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw MikuError("파일 앱에서 원본 GGUF 파일을 선택해 줘.")
            }
            // An APFS clone avoids a second 7.21GB allocation when Files shares the volume.
            let cloned = source.withUnsafeFileSystemRepresentation { from in
                temporary.withUnsafeFileSystemRepresentation { to in clonefile(from, to, 0) == 0 }
            }
            if cloned, try temporary.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw MikuError("바로가기 대신 원본 GGUF 파일을 선택해 줘.")
            }
            input = cloned ? temporary : source
        } else {
            let (download, response) = try await URLSession.shared.download(from: Self.remote)
            defer { try? fm.removeItem(at: download) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw MikuError("Bonsai 원본 파일을 받을 수 없어. 네트워크를 확인해 줘.")
            }
            try fm.moveItem(at: download, to: temporary)
            input = temporary
        }
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        guard try handle.seekToEnd() == UInt64(Self.bytes) else {
            throw MikuError("Bonsai 2 27B 원본 PQ2_0 GGUF 파일(7.21GB)을 선택해 줘.")
        }
        try handle.seek(toOffset: 0)
        var dest: FileHandle?
        if input != temporary {
            guard fm.createFile(atPath: temporary.path, contents: nil) else {
                throw MikuError("모델을 저장할 공간을 확인해 줘.")
            }
            dest = try FileHandle(forWritingTo: temporary)
        }
        defer { try? dest?.close() }
        let inputHash = try await Self.digest(handle, copyingTo: dest) { value in
            await checking(0.45 * value)
        }
        try dest?.close()
        dest = nil
        switch inputHash {
        case Self.checksum:
            try await Self.normalizeLayout(in: temporary, checking: checking)
        case Self.reorderedChecksum:
            break
        default:
            throw MikuError("원본 PQ2_0 파일과 내용이 달라. Bonsai 모델 받기를 다시 시도해 줘.")
        }
        await checking(1)
        try Task.checkCancellation()
        if fm.fileExists(atPath: Self.file.path) {
            _ = try fm.replaceItemAt(Self.file, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: Self.file)
        }
    }
}

@MainActor final class BonsaiInstaller: ObservableObject {
    static let shared = BonsaiInstaller()
    @Published private(set) var ready = BonsaiPack.ready
    @Published private(set) var working = false
    @Published private(set) var progress: Double?
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    private enum Action {
        case install(URL?), remove, reinstall
    }

    func install(_ source: URL? = nil) {
        guard task == nil else { return }
        ready = BonsaiPack.ready
        guard !ready else { return }
        start(.install(source))
    }
    func remove() { start(.remove) }
    func reinstall() { start(.reinstall) }

    private func start(_ action: Action) {
        let previous = task
        previous?.cancel()
        let id = UUID()
        operationID = id
        working = true; error = nil; progress = nil
        task = Task {
            defer {
                if operationID == id {
                    ready = BonsaiPack.ready
                    working = false; task = nil; progress = nil
                }
            }
            if let previous { await previous.value }
            do {
                try Task.checkCancellation()
                let report: @Sendable (Double) async -> Void = { value in
                    await MainActor.run {
                        guard self.operationID == id else { return }
                        self.progress = value
                    }
                }
                switch action {
                case .install(let source): try await BonsaiPack.shared.install(source: source, checking: report)
                case .remove: try await BonsaiPack.shared.remove()
                case .reinstall: try await BonsaiPack.shared.reinstall(checking: report)
                }
            } catch {
                if !Task.isCancelled, operationID == id { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() { task?.cancel() }
}
