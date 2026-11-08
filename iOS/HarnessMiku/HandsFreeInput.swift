import AVFoundation
import Speech
import SwiftUI
import Accelerate

// Only recognized words arm the endpoint. Audio activity keeps a turn open
// between partial transcripts; background noise alone cannot send a message.
struct SpeechEndpoint {
    private(set) var text = ""
    private(set) var lastActivity = 0.0
    private var lastWords = 0.0
    private var noiseFloor: Float = -60

    mutating func transcript(_ value: String, now: Double) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && value != text { text = value; lastActivity = now; lastWords = now }
    }
    mutating func audio(level: Float, now: Double) {
        let threshold = min(-27, max(-52, noiseFloor + 10))
        if level > threshold {
            lastActivity = now
        }
        if text.isEmpty || level < threshold {
            noiseFloor += (max(-80, min(level, -30)) - noiseFloor) * 0.035
        }
    }
    func finished(at now: Double) -> Bool {
        // Steady room noise must not hold a completed transcription indefinitely.
        !text.isEmpty && (now - lastActivity >= 1.3 || now - lastWords >= 4)
    }
}

@MainActor final class HandsFreeInput: ObservableObject {
    enum Phase { case idle, permission, listening, finalizing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var partial = ""
    @Published private(set) var problem: String?
    private var generation = UUID()
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timer: Task<Void, Never>?
    private var tapInstalled = false
    private var sessionActive = false
    private var endpoint = SpeechEndpoint()
    private var previousSegment = ""
    private var rolling = false
    private var onUtterance: ((String) -> Void)?
    private var retry: Task<Void, Never>?

    func stop() {
        generation = UUID()
        retry?.cancel(); retry = nil
        timer?.cancel(); timer = nil
        stopCapture()
        recognition?.cancel(); recognition = nil
        request = nil; onUtterance = nil
        endpoint = SpeechEndpoint(); partial = ""; previousSegment = ""; rolling = false; phase = .idle
    }

    private func stopCapture() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }

    func listen(onUtterance: @escaping (String) -> Void) async {
        stop(); problem = nil; phase = .permission
        let id = generation
        let mic = await AVAudioApplication.requestRecordPermission()
        guard generation == id && !Task.isCancelled else { return }
        guard mic else { fail("아이폰 설정에서 마이크 접근을 허용해 줘."); return }
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard generation == id && !Task.isCancelled else { return }
        guard status == .authorized else { fail("아이폰 설정에서 음성 인식을 허용해 줘."); return }
        self.onUtterance = onUtterance
        startCapture()
    }

    private func startCapture() {
        guard let recognizer, recognizer.isAvailable else { fail("지금 한국어 음성 인식을 사용할 수 없어."); return }
        let id = UUID()
        generation = id; rolling = false; partial = endpoint.text
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audio.setActive(true); sessionActive = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MikuError("사용할 수 있는 마이크가 없어.") }
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.taskHint = .dictation
            if LocalMiku.selected && !recognizer.supportsOnDeviceRecognition { throw MikuError("이 기기에 한국어 받아쓰기가 필요해.") }
            req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request = req
            input.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.tap(req) { [weak self] level, now in
                Task { @MainActor in
                    guard let self, self.generation == id, self.phase == .listening else { return }
                    self.endpoint.audio(level: level, now: now)
                }
            })
            tapInstalled = true
            recognition = recognizer.recognitionTask(with: req) { [weak self] result, error in
                let words = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let nsError = error as NSError?
                Task { @MainActor in
                    guard let self, self.generation == id, self.phase != .idle else { return }
                    if let words {
                        let segment = words.trimmingCharacters(in: .whitespacesAndNewlines)
                        let combined = [self.previousSegment, segment].filter { !$0.isEmpty }.joined(separator: " ")
                        self.endpoint.transcript(combined, now: ProcessInfo.processInfo.systemUptime)
                        self.partial = self.endpoint.text
                    }
                    if final { self.finishTurn(allowContinuation: self.phase == .listening || self.rolling) }
                    else if let nsError {
                        if self.phase == .finalizing || (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110) {
                            self.finishTurn(allowContinuation: self.rolling)
                        } else { self.fail("받아쓰기가 중단됐어. " + nsError.localizedDescription) }
                    }
                }
            }
            engine.prepare(); try engine.start(); phase = .listening
            let started = ProcessInfo.processInfo.systemUptime
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled, let self, self.generation == id else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    if self.endpoint.finished(at: now) || now - started >= 54 {
                        self.rolling = !self.endpoint.finished(at: now)
                        self.finalizeInput(); return
                    }
                }
            }
        } catch { fail(error.localizedDescription) }
    }

    // The audio tap runs on the audio thread, never on the UI actor.
    nonisolated private static func tap(_ request: SFSpeechAudioBufferRecognitionRequest,
                                         meter: @escaping @Sendable (Float, Double) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(samples, vDSP_Stride(buffer.stride), &rms, vDSP_Length(buffer.frameLength))
            meter(20 * log10(max(rms, 0.0001)), ProcessInfo.processInfo.systemUptime)
        }
    }
    private func finalizeInput() {
        phase = .finalizing; stopCapture(); request?.endAudio()
        let id = generation
        timer = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled && generation == id { finishTurn(allowContinuation: rolling) }
        }
    }
    private func finishTurn(allowContinuation: Bool = false) {
        let saved = endpoint, text = endpoint.text, deliver = onUtterance
        let continuing = allowContinuation && !text.isEmpty && !endpoint.finished(at: ProcessInfo.processInfo.systemUptime)
        stop()
        if !text.isEmpty && !continuing { deliver?(text); return }
        // The recognizer may finalize a segment before the speaker has finished.
        if continuing { previousSegment = text; endpoint = saved; partial = text }
        // A speech service session can end in silence. Re-arm without sending.
        onUtterance = deliver
        let id = generation
        retry = Task {
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled && generation == id { startCapture() }
        }
    }
    private func fail(_ message: String) { stop(); problem = message }
}
