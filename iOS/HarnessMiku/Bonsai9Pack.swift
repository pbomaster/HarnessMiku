import Combine
import CryptoKit
import Darwin
import Foundation

// The matching model, tokenizer and rotations must reach the runtime together.
// Only fixed data files are installed; imported Python and optional draft heads are ignored.
enum Bonsai9Pack {
    static let shared = BonsaiMLXPack(revision: "f4e28a59531731c41b6dfac88cf271bd58f0a287", large: false)
    static var directory: URL { shared.directory }
    static var ready: Bool { shared.ready }
}

enum Bonsai27MLXPack {
    static let shared = BonsaiMLXPack(revision: "24b5937a4a104a44f790b6ccbd0c79b6fabd4299", large: true)
    static var directory: URL { shared.directory }
    static var ready: Bool { shared.ready }
}

actor BonsaiMLXPack {
    let directory: URL
    private let revision: String
    private let remote: URL
    private let large: Bool
    private let operations: ModelInstallOperation
    init(revision: String, large: Bool) {
        let name = large ? "Ternary-Bonsai-2-27B-mlx-2bit" : "Ternary-Bonsai-2-9B-mlx-2bit"
        directory = AugustPack.directory.appendingPathComponent(name, isDirectory: true)
        self.revision = revision
        self.large = large
        operations = large ? .bonsai27 : ModelInstallOperation()
        remote = URL(string: "https://huggingface.co/prism-ml/" + name + "/resolve/" + revision + "/")!
    }
    private static let receipt = ".verified-revision"

    private struct Asset: Sendable {
        let name: String
        let bytes: Int64
        let sha256: String
        init(_ name: String, _ bytes: Int64, _ sha256: String) {
            self.name = name; self.bytes = bytes; self.sha256 = sha256
        }
    }
    private static let nineAssets = [
        Asset("LICENSE", 10_174, "69849221bfb90053de2134ef5e6d540287b4b98062326492f1f96f5da685524b"),
        Asset("NOTICE.txt", 409, "362344de30a17813fed132eab01825641835fdee55b5101a7c0ffbf8760424ba"),
        Asset("config.json", 30_202, "b028784e087316b7ce0fb7ae3d2d6eaeb0b15144dd3f234da4c5d57ef1ffbacb"),
        Asset("generation_config.json", 201, "a3345cadb9d63a91a11c2c12135da7eadc3d0c820e3287b04682b51cad1b12d2"),
        Asset("hadamard.json", 168_574, "6d0b37a136e1b5b25b3e8b0467599c78dd0a90c341b640a1f49271cb0be7c73b"),
        Asset("chat_template.jinja", 7_756, "a4aee8afcf2e0711942cf848899be66016f8d14a889ff9ede07bca099c28f715"),
        Asset("tokenizer_config.json", 16_710, "316230d6a809701f4db5ea8f8fc862bc3a6f3229c937c174e674ff3ca0a64ac8"),
        Asset("tokenizer.json", 12_807_982, "5f9e4d4901a92b997e463c1f46055088b6cca5ca61a6522d1b9f64c4bb81cb42"),
        Asset("preprocessor_config.json", 390, "27225450ac9c6529872ee1924fcb0962ff5634834f817040f444118116f4e516"),
        Asset("video_preprocessor_config.json", 385, "7768af27c1fafa9cc9011c1dc20067e03f8915e03b63504550e11d5066986d13"),
        Asset("model.safetensors", 3_462_149_260, "b8ebd13459dcd53504432a4a0a797287c3a4c00d80835466dbb499f05b7512bb"),
    ]
    private static let largeAssets = [
        Asset("LICENSE", 10_174, "69849221bfb90053de2134ef5e6d540287b4b98062326492f1f96f5da685524b"),
        Asset("NOTICE.txt", 411, "de0e0c48fb6f691a31e74f338e3ccf93f9ecdfe2866ab769c4bf8b79a7636a30"),
        Asset("config.json", 58_145, "238de7c512cc56a733421e3fd011d88f8260739e3d00e32c5d65b7943cc9f837"),
        Asset("generation_config.json", 202, "e70c136c1b78ddc1fb0905bac8e733a4dc448d4f852a5dd75143fffc70be550e"),
        Asset("hadamard.json", 297_903, "7132a3ec364f0bdac1f08f905f24f0ad2f14245060f592637a0396826d3b5fe6"),
        Asset("chat_template.jinja", 8_952, "c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041"),
        Asset("tokenizer_config.json", 17_928, "b11349aafa7cdc6a320767cf7ceb29ed82f7eda5d65e8e0819e76f0ce947bf27"),
        Asset("tokenizer.json", 12_809_320, "0997f410c57a1f4e53b09e4be8f4a172d90edd9564368fb0847030937229b9f3"),
        Asset("preprocessor_config.json", 390, "27225450ac9c6529872ee1924fcb0962ff5634834f817040f444118116f4e516"),
        Asset("video_preprocessor_config.json", 385, "7768af27c1fafa9cc9011c1dc20067e03f8915e03b63504550e11d5066986d13"),
        Asset("model.safetensors", 7_673_980_416, "21d6f8b23f911ccb3eaf21665700f8c006b6f5ef6d18639b3c9c89a313b22b71"),
    ]
    private nonisolated var assets: [Asset] { large ? Self.largeAssets : Self.nineAssets }
    nonisolated var ready: Bool {
        let marker = directory.appendingPathComponent(Self.receipt)
        guard (try? String(contentsOf: marker, encoding: .utf8)) == revision else { return false }
        return assets.allSatisfy { asset in
            let url = directory.appendingPathComponent(asset.name)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            return size?.int64Value == asset.bytes
        }
    }

    // A nil fraction means the download is in progress; a number measures hash verification.
    func install(folder: URL?, progress: @escaping @Sendable (Int, Int, Double?) async -> Void) async throws {
        try await operations.perform {
            try await self.installFiles(folder: folder, progress: progress)
        }
    }

    func remove(includeLegacy: Bool = true) async throws {
        try await operations.perform(replacing: true, prepare: { try self.removeFiles(includeLegacy: includeLegacy) }) {}
    }

    func reinstall(progress: @escaping @Sendable (Int, Int, Double?) async -> Void) async throws {
        try await operations.perform(replacing: true, prepare: { try self.removeFiles(includeLegacy: true) }) {
            try await self.installFiles(folder: nil, progress: progress)
        }
    }

    private nonisolated func removeFiles(includeLegacy: Bool) throws {
        // The 27B MLX and former GGUF installers share the same operation gate.
        try ModelInstallOperation.removeFiles([
            directory, directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + ".partial")
        ])
        if large && includeLegacy { try BonsaiPack.removeFiles() }
    }

    private func installFiles(folder: URL?, progress: @escaping @Sendable (Int, Int, Double?) async -> Void) async throws {
        try Task.checkCancellation()
        guard !ready else { return }
        let fm = FileManager.default
        var parent = directory.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try parent.setResourceValues(values)
        let staging = parent.appendingPathComponent(directory.lastPathComponent + ".partial", isDirectory: true)
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let scoped = folder?.startAccessingSecurityScopedResource() == true
        defer { if scoped { folder?.stopAccessingSecurityScopedResource() } }

        for (index, asset) in assets.enumerated() {
            try Task.checkCancellation()
            let number = index + 1
            let destination = staging.appendingPathComponent(asset.name)
            let source = folder?.appendingPathComponent(asset.name)
            if large && asset.name == "model.safetensors" {
                let selectedSize = source.flatMap { (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }
                if source == nil || selectedSize == TextProjection.originalBytes {
                    await progress(number, assets.count, source == nil ? nil : 0)
                    try await TextProjection.write(from: source, remote: remote.appendingPathComponent(asset.name),
                                                   destination: destination, bytes: asset.bytes, checksum: asset.sha256) { value in
                        await progress(number, self.assets.count, value)
                    }
                    continue
                }
            }
            let input: URL
            if let source {
                guard let info = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      info.isRegularFile == true, info.isSymbolicLink != true else {
                    throw MikuError("선택한 폴더에 공식 MLX 파일 \(asset.name)이 필요해.")
                }
                // Files on the same APFS volume can be staged without duplicating storage.
                let cloned = source.withUnsafeFileSystemRepresentation { from in
                    destination.withUnsafeFileSystemRepresentation { to in clonefile(from, to, 0) == 0 }
                }
                input = cloned ? destination : source
            } else {
                await progress(number, assets.count, nil)
                let (download, response) = try await URLSession.shared.download(from: remote.appendingPathComponent(asset.name))
                defer { try? fm.removeItem(at: download) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw MikuError("Bonsai MLX 파일 \(asset.name)을 받지 못했어. 네트워크를 확인해 줘.")
                }
                try fm.moveItem(at: download, to: destination)
                input = destination
            }
            try await Self.verify(asset, input: input, destination: destination) { fraction in
                await progress(number, assets.count, fraction)
            }
        }
        try revision.write(to: staging.appendingPathComponent(Self.receipt), atomically: true, encoding: .utf8)
        try Task.checkCancellation()
        if fm.fileExists(atPath: directory.path) {
            _ = try fm.replaceItemAt(directory, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: directory)
        }
    }

    private static func verify(_ asset: Asset, input: URL, destination: URL,
                               progress: @Sendable (Double) async -> Void) async throws {
        let metadata = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else {
            throw MikuError("Bonsai MLX 모델에 올바른 데이터 파일이 필요해.")
        }
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        guard try handle.seekToEnd() == UInt64(asset.bytes) else {
            throw MikuError("MLX 파일 \(asset.name)의 크기가 공식 체크포인트와 달라.")
        }
        try handle.seek(toOffset: 0)
        var copy: FileHandle?
        if input != destination {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw MikuError("기기 저장 공간을 확인해 줘.")
            }
            copy = try FileHandle(forWritingTo: destination)
        }
        defer { try? copy?.close() }
        var hash = SHA256()
        var count: Int64 = 0
        var nextUpdate: Int64 = 0
        while true {
            try Task.checkCancellation()
            guard let block = try handle.read(upToCount: 4 << 20), !block.isEmpty else { break }
            hash.update(data: block)
            try copy?.write(contentsOf: block)
            count += Int64(block.count)
            if count >= nextUpdate {
                await progress(Double(count) / Double(asset.bytes))
                nextUpdate = count + (32 << 20)
            }
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == asset.bytes, digest == asset.sha256 else {
            throw MikuError("MLX 파일 \(asset.name)이 공식 체크포인트와 달라. 다시 받아 줘.")
        }
        try copy?.close()
        copy = nil
    }
}

@MainActor final class BonsaiMLXInstaller: ObservableObject {
    static let nine = BonsaiMLXInstaller(pack: Bonsai9Pack.shared)
    static let large = BonsaiMLXInstaller(pack: Bonsai27MLXPack.shared)
    private let pack: BonsaiMLXPack
    @Published private(set) var ready: Bool
    private init(pack: BonsaiMLXPack) {
        self.pack = pack
        ready = pack.ready
    }
    @Published private(set) var working = false
    @Published private(set) var progress: Double?
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    private enum Action {
        case install(URL?), remove(Bool), reinstall
    }

    func install(_ folder: URL? = nil) {
        guard task == nil else { return }
        ready = pack.ready
        guard !ready else { return }
        start(.install(folder))
    }
    func remove(includeLegacy: Bool = true) { start(.remove(includeLegacy)) }
    func reinstall() { start(.reinstall) }

    private func start(_ action: Action) {
        let previous = task
        previous?.cancel()
        let id = UUID()
        operationID = id
        working = true; error = nil; progress = nil
        if case .remove = action { status = "모델 파일 삭제 중" } else { status = "모델 준비 중" }
        task = Task {
            defer {
                if operationID == id {
                    ready = pack.ready
                    working = false; task = nil; progress = nil; status = ""
                }
            }
            if let previous { await previous.value }
            do {
                try Task.checkCancellation()
                let report: @Sendable (Int, Int, Double?) async -> Void = { n, total, value in
                    await MainActor.run {
                        guard self.operationID == id else { return }
                        self.status = (value == nil ? "모델 파일 받는 중" : "모델 데이터 확인 중") + " · \(n)/\(total)"
                        self.progress = value
                    }
                }
                switch action {
                case .install(let folder): try await pack.install(folder: folder, progress: report)
                case .remove(let includeLegacy): try await pack.remove(includeLegacy: includeLegacy)
                case .reinstall: try await pack.reinstall(progress: report)
                }
            } catch {
                if !Task.isCancelled, operationID == id { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() { task?.cancel() }
}

private struct TextProjection: Decodable {
    static let originalBytes = 8_595_477_990
    struct Span: Decodable {
        let start: UInt64
        let length: UInt64
    }
    let header: Data
    let ranges: [Span]
    let fileBytes: Int64
    let sha256: String

    // The map is bundled with the app and was derived from the SHA-verified complete
    // official checkpoint. Exactly the original language tensor bytes are selected.
    static func write(from source: URL?, remote: URL, destination: URL, bytes: Int64, checksum: String,
                      progress: @Sendable (Double) async -> Void) async throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Stage/bonsai-27b-text.json")
        let map = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard map.fileBytes == bytes, map.sha256 == checksum else { throw MikuError("27B 언어 모델 설치 정보를 확인할 수 없어.") }
        let fm = FileManager.default
        let original = try source.map { input -> FileHandle in
            let info = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else { throw MikuError("원본 모델 파일을 선택해 줘.") }
            return try FileHandle(forReadingFrom: input)
        }
        defer { try? original?.close() }
        guard fm.createFile(atPath: destination.path, contents: nil) else { throw MikuError("27B 모델 저장 공간을 확인해 줘.") }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var hash = SHA256()
        try output.write(contentsOf: map.header)
        hash.update(data: map.header)
        var done = Int64(map.header.count)
        var nextReport: Int64 = 0
        for range in map.ranges {
            try Task.checkCancellation()
            let input: FileHandle
            var download: URL?
            // Each downloaded range is a temporary file; peak RAM stays independent of length.
            defer { if let download { try? fm.removeItem(at: download) } }
            if let original {
                try original.seek(toOffset: range.start)
                input = original
            } else {
                let last = range.start + range.length - 1
                var components = URLComponents(url: remote, resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "text-range", value: "\(range.start)-\(last)")]
                var request = URLRequest(url: components.url!)
                request.setValue("bytes=\(range.start)-\(last)", forHTTPHeaderField: "Range")
                let (part, response) = try await URLSession.shared.download(for: request)
                download = part
                guard let http = response as? HTTPURLResponse, http.statusCode == 206,
                      http.value(forHTTPHeaderField: "Content-Range") == "bytes \(range.start)-\(last)/\(originalBytes)" else {
                    throw MikuError("27B 언어 가중치 범위를 받지 못했어. 다시 받거나 원본 모델 폴더를 가져와 줘.")
                }
                input = try FileHandle(forReadingFrom: part)
            }
            defer { if original == nil { try? input.close() } }
            var remaining = range.length
            while remaining > 0 {
                try Task.checkCancellation()
                guard let block = try input.read(upToCount: Int(min(remaining, 4 << 20))), !block.isEmpty else {
                    throw MikuError("27B 언어 가중치가 중간에 끊겼어.")
                }
                try output.write(contentsOf: block)
                hash.update(data: block)
                remaining -= UInt64(block.count)
                done += Int64(block.count)
                if done >= nextReport {
                    await progress(Double(done) / Double(bytes))
                    nextReport = done + (32 << 20)
                }
            }
        }
        try output.synchronize()
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard done == bytes, digest == checksum else {
            throw MikuError("27B 언어 가중치가 공식 체크포인트에서 가져온 값과 달라.")
        }
    }
}
