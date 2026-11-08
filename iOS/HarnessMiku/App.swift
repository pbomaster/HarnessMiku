import SwiftUI

@main struct HarnessMikuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { WindowGroup { Room() } }
}

private let jade = Color(red:0.09,green:0.44,blue:0.39)

struct Room: View {
    @StateObject private var chat = Chat()
    @StateObject private var voice = Voice()
    @ObservedObject private var installer = AugustInstaller.shared
    @ObservedObject private var bonsaiInstaller = BonsaiMLXInstaller.large
    @ObservedObject private var bonsai9Installer = BonsaiMLXInstaller.nine
    @AppStorage(LocalMiku.modelKey) private var localModel = LocalMiku.Model.august
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.dynamicTypeSize) private var type
    @Environment(\.scenePhase) private var scene
    @AppStorage("chatRoute") private var chatRoute = ""
    @State private var needsKey = false
    @State private var settings = false
    @State private var expanded = false
    @State private var erase = false
    @State private var still = false
    @State private var touchLine = ""
    @State private var touchEvent = UUID()
    @FocusState private var typing: Bool
    @AppStorage("webSearchMode") private var searchMode = SearchMode.off
    @AppStorage("automaticVoice") private var automatic = false
    @AppStorage("voiceID") private var voiceID = "f77a554c56df4c9caf578cb43e6bac43"
    @AppStorage("engine") private var engine = "s2.1-pro-free"

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = !type.isAccessibilitySize && geo.size.width >= (widthClass == .regular ? 600 : 690)
                let layout = wide ? AnyLayout(HStackLayout(spacing:12)) : AnyLayout(VStackLayout(spacing:8))
                let portraitHeight = min(240,max(72,geo.size.height * (typing ? 0.18 : 0.32)))
                layout {
                    Group {
                        if expanded { Color.clear } else { portrait }
                    }.frame(width:wide ? min(410,geo.size.width*0.39) : nil,
                                   height:wide ? nil : portraitHeight)
                    thread
                }
                .padding(.horizontal,wide ? 18 : 12).padding(.top,4)
            }
            .background(Color(uiColor:.systemGroupedBackground))
            .navigationTitle("Harness Miku").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !expanded {
                    FullScreenToolbar(expanded: false, disabled: chat.waiting || chat.hasPendingReply) {
                        typing = false
                        voice.stop()
                        expanded = true
                    }
                }
                ToolbarItem(placement:.primaryAction) {
                    Button { settings = true } label: { Label("설정",systemImage:"slider.horizontal.3") }
                }
                ToolbarItem(placement:.secondaryAction) {
                    Button("새 대화",systemImage:"square.and.pencil") { erase = true }
                }
            }
            .confirmationDialog("현재 대화를 지우고 새로 시작할까?",isPresented:$erase,titleVisibility:.visible) {
                Button("대화 지우고 시작",role:.destructive) { voice.stop(); chat.clear() }
                Button("취소",role:.cancel) {}
            }
            .fullScreenCover(isPresented: $expanded) {
                VoiceRoom(chat: chat, voice: voice, searchMode: searchMode, voiceID: voiceID, engine: engine)
            }
            .sheet(isPresented:$settings,onDismiss:{ needsKey = (try? Service.credential()) == nil }) { Preferences(conversation: chat) }
            .onAppear { chat.resume(completion:{_ in}); needsKey = (try? Service.credential()) == nil; voice.onText = { text in chat.draft += (chat.draft.isEmpty ? "" : " ") + text } }
            .onChange(of: scene == .active && (chat.localProgress != nil || installer.progress != nil || bonsaiInstaller.working || bonsai9Installer.working), initial: true) { _, active in
                UIApplication.shared.isIdleTimerDisabled = active
            }
            .onChange(of:scene) { _,value in if value == .background { voice.stop() } else if value == .active {chat.resume(completion:{_ in})} }
        }.tint(jade)
    }
    private var portrait: some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.83,green:0.96,blue:0.92),Color(red:0.99,green:0.88,blue:0.92)],
                           startPoint:.topLeading,endPoint:.bottomTrailing)
            Canvas { context,size in
                for i in 0..<4 {
                    let w=size.width*(0.62+CGFloat(i)*0.15)
                    let rect=CGRect(x:(size.width-w)/2,y:(size.height-w)/2,width:w,height:w)
                    context.stroke(Path(ellipseIn:rect),with:.color(.white.opacity(0.65)),lineWidth:1)
                }
            }.accessibilityHidden(true)
            Stage(voice:voice, onTouch:{ line in
                touchLine = line; touchEvent = UUID()
                if automatic && !chat.waiting && scene == .active && voice.mode == .idle { speak(line) }
            }, onFallback:{ still = true }).accessibilityHidden(true)
            VStack {
                Spacer()
                if !touchLine.isEmpty {
                    Text(touchLine).font(.subheadline).multilineTextAlignment(.center)
                        .padding(.horizontal,12).padding(.vertical,6)
                        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
                }
                if still { Text("일러스트 모드").font(.caption).padding(4).background(.regularMaterial,in:Capsule()) }
            }.padding(10).allowsHitTesting(false)
        }.task(id:touchEvent){
            guard !touchLine.isEmpty else {return}
            try? await Task.sleep(for:.seconds(3))
            if !Task.isCancelled { touchLine = "" }
        }.clipShape(RoundedRectangle(cornerRadius:24)).accessibilityElement(children:.ignore).accessibilityLabel(touchLine.isEmpty ? "윤회 미쿠" : "미쿠, "+touchLine)
    }
    private var thread: some View {
        VStack(spacing:0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:14) {
                        if chat.lines.isEmpty {
                            VStack(alignment:.leading,spacing:8) {
                                Label("방과 후, 창가 자리",systemImage:"sun.horizon").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text("오늘은 무슨 얘기 할까?").font(.title3.bold())
                                Text("글을 쓰거나 마이크를 눌러 미쿠에게 말을 걸어 줘.").font(.subheadline).foregroundStyle(.secondary)
                                if needsKey && chatRoute != "local" {
                                    Button { settings = true } label: { Label("DeepSeek 연결",systemImage:"key").frame(minHeight:44) }
                                }
                            }.padding(.vertical,12)
                        }
                        ForEach(chat.lines) { line in bubble(line).id(line.id) }
                        if chat.waiting { HStack {
                            ProgressView()
                            Text(chat.localProgress ?? "미쿠가 답하는 중").font(.caption)
                            if chat.localProgress != nil { Button("중지") { chat.stopLocalReply() } }
                        } }
                        if let error = chat.problem {
                            Text(error).font(.callout).foregroundStyle(.red)
                            if chat.lines.last?.role == "user" && !chat.waiting { Button("다시 요청") { send(retry:true) } }
                        }
                        Color.clear.frame(height:1).id("end")
                    }.padding(12)
                }.scrollDismissesKeyboard(.interactively)
                 .onAppear { proxy.scrollTo("end",anchor:.bottom) }
                 .onChange(of:chat.lines.count) { _,_ in proxy.scrollTo("end",anchor:.bottom) }
            }
            Divider()
            if let problem=voice.problem { Text(problem).font(.caption).foregroundStyle(.red).padding(6) }
            if voice.mode != .idle {
                HStack { Image(systemName:"waveform"); Text(voiceStatus).font(.caption); Spacer()
                    Button(voice.mode == .recording ? "완료" : "중지") { if voice.mode == .recording { voice.finishRecording() } else { voice.stop() } }
                }.padding(.horizontal).frame(minHeight:44)
            }
            Menu {
                Picker("웹 검색 방식", selection: $searchMode) {
                    ForEach(SearchMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                }
            } label: {
                Label(chatRoute == "local" ? localModel.title + " · 기기 내 대화" : "웹 검색 · " + searchMode.title, systemImage: "globe").font(.caption)
            }.disabled(chat.waiting || chatRoute == "local")
            HStack(alignment:.bottom,spacing:4) {
                Button { typing=false; if voice.mode == .recording { voice.finishRecording() } else { Task { await voice.listen() } } } label: {
                    Image(systemName:voice.mode == .recording ? "stop.circle.fill" : "mic").frame(width:44,height:44)
                }.accessibilityLabel(voice.mode == .recording ? "받아쓰기 완료" : "한국어 받아쓰기")
                  .disabled(voice.mode == .permission || voice.mode == .transcribing)
                TextField("미쿠에게 메시지",text:$chat.draft,axis:.vertical).focused($typing).lineLimit(1...4)
                    .accessibilityLabel("미쿠에게 메시지").accessibilityIdentifier("miku.draft")
                    .padding(.horizontal,10).padding(.vertical,11).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:18))
                Button { send() } label: {
                    Image(systemName:"arrow.up.circle.fill").font(.title).frame(width:44,height:44)
                }.accessibilityLabel("메시지 보내기").disabled(chat.waiting || chat.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.padding(.vertical,6)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private func bubble(_ line:Line)->some View {
        let mine=line.role=="user"
        return HStack {
            if mine { Spacer(minLength:22) }
            VStack(alignment:.leading,spacing:4) {
                Text(mine ? "나" : "미쿠").font(.caption.bold()).foregroundStyle(.secondary)
                Text(mine ? line.content : Performance(line.content).body).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                if !mine,let sources=line.sources,!sources.isEmpty {
                    DisclosureGroup("웹 자료 · "+String(sources.count)){
                        ForEach(sources.indices,id:\.self){ i in
                            Link("[\(i+1)] "+sources[i].title,destination:sources[i].url).font(.footnote)
                        }
                    }
                }
                if !mine {
                    Button { speak(line.content) } label:{ Label("듣기",systemImage:"speaker.wave.2").font(.caption).frame(minHeight:44) }
                }
            }.padding(12).background(mine ? jade.opacity(0.13) : Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:18))
            if !mine { Spacer(minLength:22) }
        }
    }
    private var voiceStatus:String {
        switch voice.mode {
        case .permission:return "마이크 준비 중"
        case .recording:return "듣고 있어 · 완료하면 초안에 담겨"
        case .transcribing:return "말을 글로 옮기는 중"
        case .loading:return "미쿠 목소리 준비 중"
        case .playing:return "미쿠가 말하는 중"
        case .idle:return ""
        }
    }
    private func speak(_ text:String){ voice.speak(text,id:voiceID,engine:engine) }
    private func send(retry:Bool=false){
        typing=false; voice.stop()
        chat.send(searchMode:searchMode, retry:retry) { reply in if automatic && scene == .active && voice.mode == .idle { speak(reply) } }
    }
}

/// The system moves bottom toolbar items to its lower side rail in supported Duo poses.
struct FullScreenToolbar: ToolbarContent {
    let expanded: Bool
    var disabled = false
    var microphoneEnabled: Bool?
    var microphoneDisabled = false
    var microphoneAction: (() -> Void)?
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        if let enabled = microphoneEnabled, let microphoneAction {
            SideToolbarButton(symbol: enabled ? "mic.fill" : "mic.slash",
                              label: enabled ? "마이크 끄기" : "마이크 켜기",
                              value: enabled ? "켬" : "끔", identifier: "miku.microphone",
                              disabled: microphoneDisabled, action: microphoneAction)
        }
        SideToolbarButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                          label: expanded ? "전체 화면 음성 대화 닫기" : "전체 화면 음성 대화 열기",
                          value: expanded ? "켬" : "끔", identifier: "miku.fullScreen",
                          disabled: disabled, action: action)
    }
}

private struct SideToolbarButton: ToolbarContent {
    let symbol: String
    let label: String
    let value: String
    let identifier: String
    let disabled: Bool
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 27.1, *) {
            control.axisBehavior(.verticalPreferred)
        } else {
            control
        }
    }

    private var control: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            HStack {
                Button(action: action) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityLabel(label)
                .accessibilityValue(value)
                .accessibilityIdentifier(identifier)
            }
            .fixedSize()
        }
        .sharedBackgroundVisibility(.hidden)
        .visibilityPriority(.high)
    }
}
