import AVFoundation
import Foundation

enum SpeechProvider: String {
    case fish, localRVC

    static let key = "speechProvider"
    static var selected: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .fish
    }
}

@MainActor final class LocalMikuSpeech {
    private let synth = AVSpeechSynthesizer()
    private var capture: SpeechCapture?

    func stop() {
        capture?.finish(CancellationError())
        capture = nil
        synth.stopSpeaking(at: .immediate)
    }

    // Bound long unpunctuated text as well as normal sentences so the first
    // phrase can play before the rest of a reply is rendered.
    static func phrases(_ body: String) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(text) }
            current = ""
        }
        for ch in body {
            current.append(ch)
            if ch.isNewline || ".!?。！？".contains(ch) || current.count >= 80 ||
                (current.count >= 48 && ch.isWhitespace) { flush() }
        }
        flush()
        return result
    }

    func render(_ phrase: String, tone: String?) async throws -> SpeechAudio {
        try Task.checkCancellation()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.voiceTraits.contains(.isPersonalVoice) && $0.identifier.hasPrefix("com.apple.") && $0.language.lowercased().hasPrefix("ko")
        }
        guard let voice = voices.max(by: { $0.quality.rawValue < $1.quality.rawValue }) else {
            throw MikuError("설정에서 한국어 낭독 음성을 기기에 설치해 줘.")
        }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voice
        if tone == "slow" || tone == "whisper" { utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92 }
        if tone == "emphasis" { utterance.pitchMultiplier = 1.05 }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = SpeechCapture(url)
        capture = sink
        defer { if capture === sink { capture = nil } }
        let timeout = Task {
            try await Task.sleep(for: .seconds(45))
            if self.capture === sink {
                sink.finish(MikuError("기기 음성 생성 시간이 초과됐어. 한국어 낭독 음성을 확인해 줘."))
                self.synth.stopSpeaking(at: .immediate)
            }
        }
        defer { timeout.cancel() }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                sink.begin(continuation)
                if Task.isCancelled { sink.finish(CancellationError()); return }
                synth.write(utterance, toBufferCallback: sink.receive)
            }
        }, onCancel: { sink.finish(CancellationError()) })
        timeout.cancel()
        try Task.checkCancellation()
        let samples = try await Self.readMono16k(url)
        try Task.checkCancellation()
        let converted = try await LocalMikuRVC.shared.convert(samples)
        try Task.checkCancellation()
        return try await Self.waveAudio(converted)
    }

    nonisolated private static func readMono16k(_ file: URL) async throws -> [Float] {
        let source = try AVAudioFile(forReading: file)
        guard source.length > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source.processingFormat, to: target),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else {
            throw MikuError("한국어 음성을 미쿠 입력 형식으로 바꾸지 못했어.")
        }
        var samples: [Float] = []
        var inputError: Error?
        while true {
            try Task.checkCancellation()
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { packets, state in
                let remaining = source.length - source.framePosition
                guard remaining > 0 else { state.pointee = .endOfStream; return nil }
                let count = AVAudioFrameCount(min(AVAudioFramePosition(packets), remaining))
                guard let input = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: count) else {
                    inputError = MikuError("음성 읽기 버퍼를 준비하지 못했어.")
                    state.pointee = .endOfStream; return nil
                }
                do { try source.read(into: input, frameCount: count) }
                catch { inputError = error; state.pointee = .endOfStream; return nil }
                state.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                return input.frameLength == 0 ? nil : input
            }
            if let inputError { throw inputError }
            if let error { throw error }
            if let data = output.floatChannelData, output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
            }
            if status == .endOfStream { break }
            guard status != .error && output.frameLength > 0 else { throw MikuError("기기 음성을 변환하지 못했어.") }
        }
        guard !samples.isEmpty else { throw MikuError("한국어 낭독 결과가 비어 있어.") }
        return samples
    }

    nonisolated private static func waveAudio(_ samples: [Float]) async throws -> SpeechAudio {
        guard !samples.isEmpty, samples.count < (Int(UInt32.max) - 36) / 2 else {
            throw MikuError("미쿠 음성 변환 결과를 재생할 수 없어.")
        }
        let rate = UInt32(LocalMikuRVC.outputSampleRate)
        let byteCount = UInt32(samples.count * 2)
        var data = Data(capacity: 44 + Int(byteCount))
        func literal(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        literal("RIFF"); number(36 + byteCount); literal("WAVEfmt "); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(rate); number(2 * rate)
        number(UInt16(2)); number(UInt16(16)); literal("data"); number(byteCount)
        let pcm = samples.map { value -> Int16 in
            let sample = value.isFinite ? max(-1, min(1, value)) : 0
            return Int16((sample * Float(Int16.max)).rounded()).littleEndian
        }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return SpeechAudio(audio: data, segments: [])
    }
}

// AVSpeechSynthesizer owns the callback queue and may reuse the PCM buffer
// after the callback. Write it synchronously and serialize completion with stop.
private final class SpeechCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var file: AVAudioFile?
    private var continuation: CheckedContinuation<Void, Error>?
    private var outcome: Result<Void, Error>?

    init(_ url: URL) { self.url = url }
    func begin(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock(); defer { lock.unlock() }
        if let outcome { continuation.resume(with: outcome) }
        else { self.continuation = continuation }
    }
    func finish(_ error: Error? = nil) {
        lock.lock(); defer { lock.unlock() }
        complete(error)
    }
    private func complete(_ error: Error?) {
        guard outcome == nil else { return }
        let result: Result<Void, Error> = error.map { .failure($0) } ?? .success(Void())
        file = nil
        outcome = result
        continuation?.resume(with: result)
        continuation = nil
    }
    func receive(_ buffer: AVAudioBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard outcome == nil else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else { complete(MikuError("기기 음성 버퍼 형식이 달라.")); return }
        guard pcm.frameLength > 0 else {
            complete(file == nil ? MikuError("한국어 낭독 음성을 생성하지 못했어.") : nil)
            return
        }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                       commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
        } catch { complete(error) }
    }
}
