import SwiftUI
import AVFoundation

struct VoiceRoom: View {
    @ObservedObject var chat: Chat
    @ObservedObject var voice: Voice
    let searchMode: SearchMode
    let voiceID: String
    let engine: String
    @StateObject private var input = HandsFreeInput()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @State private var turn: UUID? = UUID()
    @State private var caption = ""
    @State private var touchLine = ""
    @State private var touchEvent = UUID()
    @State private var roomError: String?
    @State private var sentHere = false
    @State private var firstTurn = true

    private var errorText: String? { roomError ?? input.problem ?? voice.problem ?? (sentHere ? chat.problem : nil) }
    private var subtitle: String {
        if let errorText { return errorText }
        if !input.partial.isEmpty { return input.partial }
        if chat.waiting || voice.mode == .playing || voice.mode == .loading || input.phase == .finalizing { return caption }
        return touchLine.isEmpty ? caption : touchLine
    }

    var body: some View {
        GeometryReader { display in
            room(in: display.frame(in: .global))
        }
        .ignoresSafeArea()
        .task(id: touchEvent) {
            guard !touchLine.isEmpty else { return }
            do { try await Task.sleep(for: .seconds(2.4)) } catch { return }
            touchLine = ""
        }
        .task(id: turn) {
            guard let id = turn else { return }
            do { _ = try Service.credential() }
            catch { roomError = error.localizedDescription; pause(); return }
            if !firstTurn { try? await Task.sleep(for: .milliseconds(300)) }
            firstTurn = false
            guard !Task.isCancelled && turn == id else { return }
            await input.listen { words in
                guard turn == id, scene != .background, !chat.waiting else { return }
                caption = words; sentHere = true
                chat.send(searchMode: searchMode, spokenText: words) { reply in
                    guard turn == id, scene != .background else { return }
                    caption = Performance(reply).body
                    voice.speak(reply, id: voiceID, engine: engine) {
                        guard turn == id, scene != .background else { return }
                        turn = UUID()
                    }
                }
            }
            // A repeat denial can clear and restore the same error in one frame.
            if turn == id, input.problem != nil { pause() }
        }
        .onChange(of: input.problem) { _, problem in
            if problem != nil { pause() }
        }
        .onChange(of: voice.problem) { _, problem in
            if problem != nil { pause() }
        }
        .onChange(of: chat.problem) { _, problem in
            if sentHere && problem != nil { pause() }
        }
        .onChange(of: scene) { _, phase in
            // Foreground transitions can temporarily deactivate the scene while Duo changes displays.
            if phase == .background { pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue { pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            if note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { pause() }
        }
        .onDisappear { pause() }
    }

    private func room(in display: CGRect) -> some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.83, green: 0.96, blue: 0.92), Color(red: 0.99, green: 0.88, blue: 0.92)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                Stage(voice: voice, framing: .thighs, onTouch: { line in
                    touchLine = line
                    touchEvent = UUID()
                }, onFallback: {})
                    .ignoresSafeArea().accessibilityHidden(true)
                GeometryReader { content in
                    let safe = content.frame(in: .global)
                    let shift = display.width > display.height ? display.midX - safe.midX : 0
                    statusCard
                        .padding(.horizontal, 16 + abs(shift))
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .offset(x: shift)
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .toolbar {
                FullScreenToolbar(expanded: true, microphoneEnabled: turn != nil,
                                  microphoneDisabled: turn == nil && (chat.waiting || chat.hasPendingReply),
                                  microphoneAction: toggleMicrophone) {
                    pause()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder private var statusCard: some View {
        if !subtitle.isEmpty {
            Text(subtitle)
                .font(.callout)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("miku.voiceStatus")
        }
    }

    private func toggleMicrophone() {
        if turn != nil {
            pause()
        } else if !chat.waiting && !chat.hasPendingReply {
            roomError = nil
            sentHere = false
            voice.problem = nil
            turn = UUID()
        }
    }

    private func pause() {
        turn = nil
        input.stop()
        voice.stop()
    }
}
