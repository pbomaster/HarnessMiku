import SwiftUI
import AVFoundation
import Speech

@MainActor final class Voice: NSObject, ObservableObject {
    enum Mode { case idle, permission, recording, transcribing, loading, playing }
    @Published private(set) var mode = Mode.idle
    @Published private(set) var mouth = LipPose.closed
    @Published var problem: String?
    var onText: ((String) -> Void)?
    private let audio = AVAudioSession.sharedInstance()
    private var token = UUID()
    private var playbackFinished: (() -> Void)?
    private var player: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var speechTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var synthesis: Task<Void,Never>?
    private var deviceSpeech: LocalMikuSpeech?
    private var clock: Task<Void,Never>?
    private var observer: NSObjectProtocol?
    override init() {
        super.init()
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let kind = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  kind == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.stop() }
        }
    }
    func stop() {
        token = UUID()
        playbackFinished = nil
        clock?.cancel(); clock = nil
        synthesis?.cancel(); synthesis = nil
        deviceSpeech?.stop(); deviceSpeech = nil
        speechTask?.cancel(); speechTask = nil; recognizer = nil
        recorder?.stop(); recorder = nil
        player?.stop(); player = nil
        if let file { try? FileManager.default.removeItem(at:file) }; file = nil
        if mode != .idle { try? audio.setActive(false,options:.notifyOthersOnDeactivation) }
        mode = .idle; mouth = .closed
    }
    func listen() async {
        stop(); problem = nil; mode = .permission
        let ticket = token
        let mic = await AVAudioApplication.requestRecordPermission()
        guard ticket == token else { return }
        guard mic else { stop(); problem = "설정 앱에서 마이크 접근을 허용해 줘."; return }
        let grant = await withCheckedContinuation { cont in SFSpeechRecognizer.requestAuthorization { cont.resume(returning:$0) } }
        guard ticket == token else { return }
        guard grant == .authorized else { stop(); problem = "설정 앱에서 음성 인식을 허용해 줘."; return }
        do {
            try audio.setCategory(.record,mode:.measurement)
            try audio.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a")
            file = url
            let rec = try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1])
            guard rec.record() else { throw MikuError("마이크 녹음을 시작하지 못했어.") }
            recorder = rec; mode = .recording
            clock = Task { try? await Task.sleep(for:.seconds(55)); if !Task.isCancelled { finishRecording() } }
        } catch { stop(); problem = error.localizedDescription }
    }
    func finishRecording() {
        guard mode == .recording, let file else { return }
        clock?.cancel(); recorder?.stop(); recorder = nil
        try? audio.setActive(false,options:.notifyOthersOnDeactivation)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier:"ko-KR")), recognizer.isAvailable else {
            stop(); problem = "지금 한국어 받아쓰기를 사용할 수 없어. 키보드로 입력해 줘."; return
        }
        self.recognizer = recognizer
        let request = SFSpeechURLRecognitionRequest(url:file)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        let ticket = token
        mode = .transcribing
        clock = Task { try? await Task.sleep(for:.seconds(40)); if !Task.isCancelled && ticket == token { stop(); problem = "받아쓰기 시간이 초과됐어." } }
        speechTask = recognizer.recognitionTask(with:request) { [weak self] result,error in
            let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.token == ticket else { return }
                if let text { self.stop(); self.onText?(text) }
                else if failed { self.stop(); self.problem = "음성을 인식하지 못했어. 다시 말해 줘." }
            }
        }
    }
    func speak(_ text: String, id: String, engine: String, handsFreeCompletion: (() -> Void)? = nil) {
        stop(); problem = nil; mode = .loading
        playbackFinished = handsFreeCompletion
        let ticket = token
        let provider = SpeechProvider.selected
        synthesis = Task {
            guard ticket == token, !Task.isCancelled else { return }
            do {
                switch provider {
                case .fish:
                    let speech = try await Service.voice(text,id:id,engine:engine)
                    try await play(speech, text: text, ticket: ticket)
                case .localRVC:
                    guard LocalMikuRVC.isInstalled else { throw MikuError("설정에서 미쿠 RVC 음성 팩을 먼저 가져와 줘.") }
                    let performance = Performance(text)
                    let phrases = LocalMikuSpeech.phrases(performance.body)
                    guard !phrases.isEmpty else { throw MikuError("읽을 대사가 없어.") }
                    let source = LocalMikuSpeech()
                    deviceSpeech = source
                    var speech = try await source.render(phrases[0], tone: performance.tone)
                    for index in phrases.indices {
                        try Task.checkCancellation()
                        guard ticket == token else { return }
                        if index + 1 < phrases.count {
                            // Prepare at most one phrase ahead while the current one plays.
                            async let upcoming = source.render(phrases[index + 1], tone: performance.tone)
                            try await play(speech, text: phrases[index], ticket: ticket)
                            if ticket == token { mode = .loading }
                            speech = try await upcoming
                        } else {
                            try await play(speech, text: phrases[index], ticket: ticket)
                        }
                    }
                }
                if token == ticket { finishPlayback() }
            } catch {
                guard ticket == token else { return }
                stop()
                problem = error.localizedDescription
            }
        }
    }
    private func play(_ speech: SpeechAudio, text: String, ticket: UUID) async throws {
        guard ticket == token, !Task.isCancelled else { return }
        try audio.setCategory(.playback, mode: .spokenAudio)
        try audio.setActive(true)
        let next = try AVAudioPlayer(data: speech.audio)
        let segments = speech.segments.isEmpty
            ? [SpeechSegment(text: Performance(text).body, start: 0, end: next.duration)]
            : speech.segments
        let timeline = LipTimeline(segments: segments)
        guard next.play() else { throw MikuError("음성을 재생하지 못했어.") }
        player = next
        mode = .playing
        while ticket == token && next.isPlaying {
            mouth = timeline.pose(at: next.currentTime)
            try await Task.sleep(for: .milliseconds(33))
        }
        if ticket == token { mouth = .closed }
    }
    private func finishPlayback() {
        let finished = playbackFinished
        stop()
        finished?()
    }
}
