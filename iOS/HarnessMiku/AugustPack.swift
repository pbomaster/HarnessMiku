import Foundation
import Combine
import CryptoKit
import Darwin

// Keep an installed copy in the app's data container, which survives an app update.
actor AugustPack {
    static let shared = AugustPack()
    static let tag = "miku-august-q4"
    static let bytes = 5_027_783_584
    static let directory = URL.applicationSupportDirectory.appendingPathComponent("LocalModels", isDirectory: true)
    static let file = directory.appendingPathComponent(LocalMiku.fileName + ".gguf")
    private static let temporary = directory.appendingPathComponent(LocalMiku.fileName + ".partial")
    private static let removed = directory.appendingPathComponent(".august-user-removed")
    private static let checksum = "77d9b60b446617f6503fa02fa105ee58b613091a9f2f02eb2761b6bfaa008fa4"
    private let operations = ModelInstallOperation()

    static func complete(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        return size?.intValue == bytes
    }

    private static func removeFiles() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep the user's deletion choice even when iOS retains the ODR cache.
        try Data().write(to: removed, options: .atomic)
        try ModelInstallOperation.removeFiles([file, temporary])
    }

    func remove() async throws {
        try await operations.perform(replacing: true, prepare: { try Self.removeFiles() }) {}
    }

    func reinstall(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL? {
        try await operations.perform(replacing: true, prepare: { try Self.removeFiles() }) {
            try await self.find(allowDownload: true, progress: progress)
        }
    }

    func locate(allowDownload: Bool, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL? {
        try await operations.perform {
            try await self.find(allowDownload: allowDownload, progress: progress)
        }
    }

    private func keep(_ source: URL, progress: @Sendable (Double) -> Void) async throws -> URL {
        let fm = FileManager.default
        var folder = Self.directory
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let tmp = Self.temporary
        try ModelInstallOperation.removeFiles([tmp])
        defer { try? fm.removeItem(at: tmp) }
        let cloned = source.withUnsafeFileSystemRepresentation { from in
            tmp.withUnsafeFileSystemRepresentation { to in clonefile(from, to, 0) == 0 }
        }
        let input = try FileHandle(forReadingFrom: cloned ? tmp : source)
        defer { try? input.close() }
        var output: FileHandle?
        if !cloned {
            guard fm.createFile(atPath: tmp.path, contents: nil) else { throw MikuError("8B 모델 저장 공간을 확인해 줘.") }
            output = try FileHandle(forWritingTo: tmp)
        }
        defer { try? output?.close() }
        var hash = SHA256()
        var count = 0
        while let block = try input.read(upToCount: 4 << 20), !block.isEmpty {
            try Task.checkCancellation()
            hash.update(data: block)
            try output?.write(contentsOf: block)
            count += block.count
            if count % (32 << 20) == 0 {
                progress(0.9 + 0.1 * Double(count) / Double(Self.bytes))
                await Task.yield()
            }
        }
        try output?.close()
        output = nil
        guard count == Self.bytes,
              hash.finalize().map({ String(format:"%02x",$0) }).joined() == Self.checksum,
              Self.complete(tmp) else { throw MikuError("8B 모델 파일이 원본과 달라. 다시 받아 줘.") }
        try Task.checkCancellation()
        if fm.fileExists(atPath: Self.file.path) {
            _ = try fm.replaceItemAt(Self.file, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: Self.file)
        }
        try ModelInstallOperation.removeFiles([Self.removed])
        progress(1)
        return Self.file
    }

    private func find(allowDownload: Bool, progress: @escaping @Sendable (Double) -> Void) async throws -> URL? {
        try Task.checkCancellation()
        if Self.complete(Self.file) { return Self.file }
        if !allowDownload && FileManager.default.fileExists(atPath: Self.removed.path) { return nil }
        let name = LocalMiku.fileName
        if let bundled = Bundle.main.url(forResource: name, withExtension: "gguf"), Self.complete(bundled) {
            return try await keep(bundled, progress: progress)
        }
        let pack = NSBundleResourceRequest(tags: [Self.tag])
        if !(await pack.conditionallyBeginAccessingResources()) {
            guard allowDownload else { return nil }
            let observation = pack.progress.observe(\.fractionCompleted, options: [.initial, .new]) { value, _ in
                progress(0.9 * value.fractionCompleted)
            }
            defer { observation.invalidate() }
            try await withTaskCancellationHandler {
                try await pack.beginAccessingResources()
            } onCancel: { pack.progress.cancel() }
        }
        // Apple's cache remains OS-managed after this access request has ended.
        defer { pack.endAccessingResources() }
        try Task.checkCancellation()
        guard let url = pack.bundle.url(forResource: name, withExtension: "gguf"), Self.complete(url) else {
            throw MikuError("8B 모델 팩의 파일을 확인할 수 없어.")
        }
        return try await keep(url, progress: progress)
    }
}

@MainActor final class AugustInstaller: ObservableObject {
    static let shared = AugustInstaller()
    @Published private(set) var ready = AugustPack.complete(AugustPack.file)
    @Published private(set) var checking = false
    @Published private(set) var working = false
    @Published private(set) var progress: Double?
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var operationID = UUID()

    func prepare(download: Bool) {
        guard task == nil else { return }
        ready = AugustPack.complete(AugustPack.file)
        guard !ready else { return }
        start(download: download) { progress in
            _ = try await AugustPack.shared.locate(allowDownload: download, progress: progress)
        }
    }

    func remove() {
        start(download: false) { _ in try await AugustPack.shared.remove() }
    }

    func reinstall() {
        start(download: true) { progress in _ = try await AugustPack.shared.reinstall(progress: progress) }
    }

    private func start(download: Bool, operation: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void) {
        let previous = task
        previous?.cancel()
        let id = UUID()
        operationID = id
        working = true; error = nil; checking = !download; progress = download ? 0 : nil
        task = Task {
            defer {
                if operationID == id {
                    ready = AugustPack.complete(AugustPack.file)
                    task = nil; progress = nil; checking = false; working = false
                }
            }
            if let previous { await previous.value }
            do {
                try Task.checkCancellation()
                try await operation { fraction in
                    Task { @MainActor in
                        guard self.operationID == id, let current = self.progress else { return }
                        self.progress = max(current, fraction)
                    }
                }
            } catch {
                if !Task.isCancelled, operationID == id { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() { task?.cancel() }
}
