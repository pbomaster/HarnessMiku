import SwiftUI

struct Preferences: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chat = ""
    @State private var fish = ""
    @State private var id = ""
    @State private var model = ""
    @State private var auto = false
    @State private var error: String?
    @StateObject private var login=Login()
    @AppStorage("chatRoute") private var route = ""
    @AppStorage("replyAlerts") private var alerts=false
    @AppStorage("remoteReply") private var savedRemote=false
    @AppStorage("relayOrigin") private var savedOrigin=""
    @State private var remote=false
    @State private var origin=""
    @State private var pair=""
    @State private var loaded = false
    @AppStorage("voiceID") private var savedID = ""
    @AppStorage("engine") private var savedModel = "s2.1-pro-free"
    @AppStorage("automaticVoice") private var savedAuto = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("연결 방식",selection:$route){
                        Text("DeepSeek 로그인").tag("account");Text("API 키").tag("api")
                    }.pickerStyle(.segmented)
                    if route=="account" {
                        if login.signedIn { Label("계정 연결됨",systemImage:"person.crop.circle.badge.checkmark") }
                        Button(login.signedIn ? "다시 로그인" : "DeepSeek로 로그인"){ login.start() }.disabled(login.active)
                        if login.active { Button("로그인 취소"){login.end()} }
                        if login.signedIn { Button("로그아웃",role:.destructive){Task {await login.logout()}} }
                        if !login.message.isEmpty {Text(login.message).font(.caption)}
                    } else {
                        SecureField("DeepSeek API 키",text:$chat).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: { Label("캐릭터 채팅",systemImage:"text.bubble") }
                  footer: { Text("보내기를 누르면 미쿠의 지시문과 최근 대화 최대 24개를 DeepSeek로 보내. 선택한 계정 또는 API 키의 사용 한도가 적용돼.") }
                Section {
                    SecureField("Fish Audio API 키",text:$fish).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("32자리 참조 음성 ID",text:$id).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("합성 모델",selection:$model) {
                        Text("S2.1 Pro Free").tag("s2.1-pro-free")
                        Text("S2.1 Pro").tag("s2.1-pro")
                        Text("Drama 3").tag("drama-3")
                    }
                    Toggle("답변 자동 낭독",isOn:$auto)
                } header: { Label("미쿠의 목소리",systemImage:"waveform") }
                  footer: { Text("낭독할 대사는 Fish Audio로 보내. 자동 낭독을 켜면 새 답변과 미쿠의 터치 대사도 읽어 줘. Mac 개인판의 참조 음성 ID가 기본값이야. 두 API 키는 이 기기 키체인에 저장해.") }
                Section("답변 완료 알림") {
                    Toggle("답변이 오면 알림",isOn:Binding(get:{alerts},set:{on in
                        if on { Task {do {try await Alerts.authorize();alerts=true} catch {self.error=error.localizedDescription}} }
                        else {alerts=false;remote=false;savedRemote=false}
                    }))
                    if alerts {
                        Toggle("개인 중계로 원격 푸시 받기",isOn:$remote)
                        if remote {
                            Text("내가 관리하는 HTTPS 서버에 대화와 선택한 DeepSeek 자격 증명을 보내. 서버가 답변을 받아 APNs로 알려 줘.").font(.caption)
                            TextField("개인 서버 HTTPS 주소",text:$origin).textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField("중계 연결 키",text:$pair).textInputAutocapitalization(.never).autocorrectionDisabled()
                        } else {Text("아이폰에서 답변 수신이 끝나면 알림을 보내. 앱이 정지된 동안에도 받으려면 개인 중계가 필요해.").font(.caption)}
                    }
                }
                Section("웹 검색"){
                    Text("기본은 꺼짐이야. 자동을 고르면 미쿠가 최근 대화를 보고 검색이 필요한지 먼저 판단해. 항상 검색을 고르면 보낼 때마다 검색해. 검색어나 링크는 DeepSeek로 보내. 대화에 연결한 계정을 사용하며, 검색 이용 한도와 요금은 해당 계정에 따라 달라져.").font(.caption)
                }
                Section("받아쓰기") {
                    Text("마이크로 녹음하고 완료를 누르면 초안에 담겨. 기기 내 한국어 인식을 우선하고, 지원하지 않을 때는 Apple 음성 인식을 사용해. 녹음 파일은 인식 후 삭제해. 전체 화면 음성 대화에서는 마이크가 바로 대기하고, 말이 끝나면 인식된 문장을 DeepSeek로 보내. 미쿠의 답변은 Fish Audio로 읽어 줘.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("대화 설정").navigationBarTitleDisplayMode(.inline)
             .toolbar {
                 ToolbarItem(placement:.cancellationAction) { Button("취소"){ dismiss() } }
                 ToolbarItem(placement:.confirmationAction) { Button("저장"){ save() }.disabled(!loaded) }
             }
             .sheet(item:$login.page) { page in SystemBrowser(page:page,cancelled:{login.end()}).interactiveDismissDisabled() }
             .onDisappear { if login.active && login.page == nil { login.end() } }
             .onAppear {
                 login.refresh();remote=savedRemote;origin=savedOrigin
                 if !["account", "api"].contains(route) { route = Service.accountRoute ? "account" : "api" }
                 id = savedID; model = savedModel; auto = savedAuto
                 do { chat = try Keys.read(.chat); fish = try Keys.read(.voice); pair = try Keys.read(.relay); loaded = true }
                 catch { self.error = error.localizedDescription }
             }
        }
    }
    private func save() {
        let value = id.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard (value.isEmpty && !auto) || value.range(of:"^[a-f0-9]{32}$",options:.regularExpression) != nil else {
            error = "참조 음성 ID는 32자리 16진수야."; return
        }
        guard !auto || !fish.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            error = "자동 낭독에는 Fish Audio API 키가 필요해."; return
        }
        do {
            if remote { _=try Relay.base(origin);guard pair.count>=32 else{throw MikuError("32자 이상의 중계 연결 키를 입력해 줘.")} }
            try Keys.write(pair,to:.relay);savedOrigin=origin;savedRemote=remote
            try Keys.write(chat,to:.chat); try Keys.write(fish.trimmingCharacters(in: .whitespacesAndNewlines),to:.voice)
            savedID=value; savedModel=model; savedAuto=auto; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
