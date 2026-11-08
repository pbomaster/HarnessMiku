import Foundation

/// Owns the actual download/verification task so a destructive action can wait for
/// its cancellation and cleanup. The two 27B formats share one operation slot.
actor ModelInstallOperation {
    static let bonsai27 = ModelInstallOperation()
    private struct Running {
        let id: UUID
        let cancel: @Sendable () -> Void
        let finished: Task<Void, Never>
    }
    private var running: Running?
    private var replacing = false

    func perform<Value: Sendable>(
        replacing existing: Bool = false,
        prepare: @Sendable () throws -> Void = {},
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard !replacing else { throw MikuError("모델 파일을 정리 중이야. 잠시 기다려 줘.") }
        if existing {
            replacing = true
            defer { replacing = false }
            if let previous = running {
                previous.cancel()
                await previous.finished.value
            }
            try Task.checkCancellation()
            try prepare()
            return try await execute(operation)
        }
        guard running == nil else { throw MikuError("이 모델을 이미 준비 중이야.") }
        return try await execute(operation)
    }

    private func execute<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let id = UUID()
        let work = Task { try await operation() }
        running = Running(id: id, cancel: { work.cancel() }, finished: Task { _ = await work.result })
        defer { if running?.id == id { running = nil } }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    nonisolated static func removeFiles(_ urls: [URL]) throws {
        for url in urls {
            do { try FileManager.default.removeItem(at: url) }
            catch CocoaError.fileNoSuchFile {}
            catch { throw error }
        }
    }
}
