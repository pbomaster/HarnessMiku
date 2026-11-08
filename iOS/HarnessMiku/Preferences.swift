import SwiftUI
import UniformTypeIdentifiers

struct Preferences: View {
    @ObservedObject var conversation: Chat
    private struct ModelChange {
        let model: LocalMiku.Model
        let redownload: Bool
        var title: String { model.title + (redownload ? "를 다시 받을까?" : "를 삭제할까?") }
    }
    @State private var pendingModelChange: ModelChange?
    private var modelInUse: Bool { conversation.waiting || conversation.hasPendingReply }

    @Environment(\.dismiss) private var dismiss
    @State private var chat = ""
    @State private var fish = ""
    @State private var id = ""
    @State private var model = ""
    @State private var auto = false
    @State private var error: String?
    @StateObject private var login=Login()
    @AppStorage("chatRoute") private var route = ""
    @AppStorage(LocalMiku.modelKey) private var localModel = LocalMiku.Model.august
    @AppStorage("bonsaiContextMode") private var bonsaiContextMode = "automatic"
    @ObservedObject private var bonsaiInstaller = BonsaiMLXInstaller.large
    @ObservedObject private var bonsai9Installer = BonsaiMLXInstaller.nine
    @State private var importingBonsai = false
    @State private var importModel = LocalMiku.Model.bonsai9MLX
    @ObservedObject private var augustInstaller = AugustInstaller.shared
    @AppStorage("replyAlerts") private var alerts=false
    @AppStorage("remoteReply") private var savedRemote=false
    @AppStorage("relayOrigin") private var savedOrigin=""
    @State private var remote=false
    @State private var origin=""
    @State private var pair=""
    @State private var loaded = false
    @AppStorage("voiceID") private var savedID = "f77a554c56df4c9caf578cb43e6bac43"
    @AppStorage("engine") private var savedModel = "s2.1-pro-free"
    @AppStorage("automaticVoice") private var savedAuto = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("연결 방식",selection:$route){
                        Text("DeepSeek 로그인").tag("account");Text("API 키").tag("api");Text("로컬 AI").tag("local")
                    }.pickerStyle(.segmented)
                    if route=="account" {
                        if login.signedIn { Label("계정 연결됨",systemImage:"person.crop.circle.badge.checkmark") }
                        Button(login.signedIn ? "다시 로그인" : "DeepSeek로 로그인"){ login.start() }.disabled(login.active)
                        if login.active { Button("로그인 취소"){login.end()} }
                        if login.signedIn { Button("로그아웃",role:.destructive){Task {await login.logout()}} }
                        if !login.message.isEmpty {Text(login.message).font(.caption)}
                    } else if route == "local" {
                        Picker("기기 내 모델", selection: $localModel) {
                            Text(LocalMiku.Model.august.title).tag(LocalMiku.Model.august)
                            Text(LocalMiku.Model.bonsai.title).tag(LocalMiku.Model.bonsai)
                            Text(LocalMiku.Model.bonsai9MLX.title).tag(LocalMiku.Model.bonsai9MLX)
                        }
                        switch localModel {
                        case .bonsai9MLX: mlxSettings(model: .bonsai9MLX, installer: bonsai9Installer)
                        case .bonsai: bonsaiSettings
                        case .august: augustSettings
                        }
                    } else {
                        SecureField("DeepSeek API 키",text:$chat).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: { Label("캐릭터 채팅",systemImage:"text.bubble") }
                  footer: { if route != "local" { Text("보내기를 누르면 미쿠의 지시문과 최근 대화 최대 24개를 DeepSeek로 보내. 선택한 계정 또는 API 키의 사용 한도가 적용돼.") } }
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
                  footer: { Text("로컬 AI로 대화할 때도 낭독할 대사는 Fish Audio로 보내. 자동 낭독을 켜면 새 답변과 미쿠의 터치 대사도 읽어 줘. Mac 개인판의 참조 음성 ID가 기본값이야. 두 API 키는 이 기기 키체인에 저장해.") }
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
                    Text("마이크로 녹음하고 완료를 누르면 초안에 담겨. 기기 내 한국어 인식을 우선하고, 지원하지 않을 때는 Apple 음성 인식을 사용해. 녹음 파일은 인식 후 삭제해. 전체 화면 음성 대화에서는 마이크가 바로 대기하고, 말이 끝나면 인식된 문장을 선택한 대화 모델로 보내. 미쿠의 답변은 Fish Audio로 읽어 줘.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("대화 설정").navigationBarTitleDisplayMode(.inline)
             .toolbar {
                 ToolbarItem(placement:.cancellationAction) { Button("취소"){ dismiss() } }
                 ToolbarItem(placement:.confirmationAction) { Button("저장"){ save() }.disabled(!loaded) }
             }
             .sheet(item:$login.page) { page in SystemBrowser(page:page,cancelled:{login.end()}).interactiveDismissDisabled() }
             .confirmationDialog(pendingModelChange?.title ?? "", isPresented: Binding(
                 get: { pendingModelChange != nil },
                 set: { if !$0 { pendingModelChange = nil } }
             ), titleVisibility: .visible) {
                 if let change = pendingModelChange {
                     Button(change.redownload ? "지우고 다시 받기" : "모델 삭제", role: .destructive) {
                         changeModel(change)
                     }
                 }
                 Button("취소", role: .cancel) { pendingModelChange = nil }
             } message: {
                 if pendingModelChange?.redownload == true {
                     Text(pendingModelChange?.model == .august
                          ? "앱의 8B 모델 파일을 지우고 다시 설치해. Apple 캐시가 있으면 검증한 뒤 복원해."
                          : "설치한 모델 파일을 지우고 다시 받아. 다운로드를 마치면 대화할 수 있어.")
                 } else {
                     Text(pendingModelChange?.model == .bonsai
                          ? "27B MLX 모델과 이전 GGUF가 있으면 함께 지워."
                          : "선택한 모델의 설치 파일을 지워.")
                 }
             }
             .fileImporter(isPresented: $importingBonsai, allowedContentTypes: [.folder]) { result in
                 switch result {
                 case .success(let url):
                     guard !modelInUse else { error = "답변이 끝난 뒤 모델을 바꿔 줘."; return }
                     if importModel == .bonsai9MLX { bonsai9Installer.install(url) }
                     else { bonsaiInstaller.install(url) }
                 case .failure(let failure):
                     if (failure as NSError).code != NSUserCancelledError { error = failure.localizedDescription }
                 }
             }
             .onDisappear { if login.active && login.page == nil { login.end() } }
             .onAppear {
                 login.refresh();remote=savedRemote;origin=savedOrigin
                 if route.isEmpty {route=(try? Keys.read(.chat))?.isEmpty == false ? "api":"account"}
                 id = savedID; model = savedModel; auto = savedAuto
                 do { chat = try Keys.read(.chat); fish = try Keys.read(.voice); pair = try Keys.read(.relay); loaded = true }
                 catch { self.error = error.localizedDescription }
             }
        }
    }
    @ViewBuilder private var augustSettings: some View {
        Text("Miku August 8B · MLX · 5.03GB 모델 팩").font(.caption)
            .task { augustInstaller.prepare(download: false) }
        if augustInstaller.working {
            if let fraction = augustInstaller.progress {
                ProgressView(value: fraction)
            } else {
                ProgressView("8B 모델 준비 중")
            }
            Button("8B 작업 취소") { augustInstaller.cancel() }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("cancel-august-model")
        } else if augustInstaller.ready {
            Label("오프라인 대화 준비됨", systemImage: "checkmark.circle")
        } else {
            Button("8B 모델 받기") { augustInstaller.prepare(download: true) }
                .buttonStyle(.borderless)
                .disabled(modelInUse)
                .accessibilityIdentifier("download-august-model")
        }
        modelManagement(for: .august, working: augustInstaller.working)
        if let error = augustInstaller.error { Text(error).font(.caption).foregroundStyle(.red) }
    }

    @ViewBuilder private var bonsaiSettings: some View {
        Menu {
            Picker("문맥 길이", selection: $bonsaiContextMode) {
                Text("자동 최대").tag("automatic")
                Text("64K 고정 (65,536)").tag("fixed64k")
            }
        } label: {
            HStack {
                Text("문맥 길이").foregroundStyle(.primary)
                Spacer()
                Text(bonsaiContextMode == "fixed64k" ? "64K 고정 (65,536)" : "자동 최대")
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("bonsai27-context-mode")
        if bonsaiContextMode == "fixed64k" {
            Text("문맥 65,536토큰을 요청해. 현재 메모리로 처리할 수 없으면 알려 줄게.").font(.caption)
        }
        mlxSettings(model: .bonsai, installer: bonsaiInstaller)
    }

    // Each action is a separate Form row. The file chooser and the download
    // must not share SwiftUI's automatic row-wide button action.
    @ViewBuilder private func mlxSettings(model: LocalMiku.Model, installer: BonsaiMLXInstaller) -> some View {
        let large = model == .bonsai
        Text(large ? "MLX 2비트 · 언어 가중치만 설치" : "공식 MLX 2비트 · 3.48GB").font(.caption)
        if installer.working {
            if let progress = installer.progress {
                ProgressView(installer.status, value: progress)
            } else {
                ProgressView(installer.status)
            }
            Button("작업 취소") { installer.cancel() }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("cancel-model-" + model.rawValue)
        } else if installer.ready {
            Label("오프라인 대화 준비됨", systemImage: "checkmark.circle")
        } else {
            if large && BonsaiPack.ready {
                Text("기존 GGUF는 보관돼 있어. MLX 대화에는 MLX 모델을 한 번 받아 줘.").font(.caption)
            }
            Button {
                installer.install()
            } label: {
                Label(large ? "Bonsai 27B MLX 받기" : "Bonsai 9B MLX 받기", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(modelInUse)
            .accessibilityIdentifier(large ? "download-bonsai27-mlx" : "download-bonsai9-mlx")
            Button {
                importModel = model
                importingBonsai = true
            } label: {
                Label("MLX 모델 폴더 가져오기", systemImage: "folder")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(modelInUse)
            .accessibilityIdentifier(large ? "import-bonsai27-mlx" : "import-bonsai9-mlx")
        }
        modelManagement(for: model, working: installer.working)
        if let error = installer.error { Text(error).font(.caption).foregroundStyle(.red) }
    }

    @ViewBuilder private func modelManagement(for model: LocalMiku.Model, working: Bool) -> some View {
        if hasInstalledFiles(model) && !working {
            Button {
                pendingModelChange = ModelChange(model: model, redownload: true)
            } label: {
                Label("모델 다시 받기", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(modelInUse)
            .accessibilityIdentifier("redownload-model-" + model.rawValue)
            Button(role: .destructive) {
                pendingModelChange = ModelChange(model: model, redownload: false)
            } label: {
                Label("모델 삭제", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(modelInUse)
            .accessibilityIdentifier("delete-model-" + model.rawValue)
            if model == .august {
                Text("삭제하면 앱의 8B 모델 파일을 지워. Apple 다운로드 캐시는 iOS가 정리해.")
                    .font(.caption)
            }
        }
    }

    private func hasInstalledFiles(_ model: LocalMiku.Model) -> Bool {
        let fm = FileManager.default
        switch model {
        case .august: return fm.fileExists(atPath: AugustPack.file.path)
        case .bonsai9MLX: return fm.fileExists(atPath: Bonsai9Pack.directory.path)
        case .bonsai:
            return fm.fileExists(atPath: Bonsai27MLXPack.directory.path) || fm.fileExists(atPath: BonsaiPack.file.path)
        }
    }

    private func changeModel(_ change: ModelChange) {
        pendingModelChange = nil
        guard !modelInUse else { error = "답변이 끝난 뒤 모델을 바꿔 줘."; return }
        switch change.model {
        case .august:
            if change.redownload { augustInstaller.reinstall() } else { augustInstaller.remove() }
        case .bonsai:
            if change.redownload { bonsaiInstaller.reinstall() } else { bonsaiInstaller.remove() }
        case .bonsai9MLX:
            if change.redownload { bonsai9Installer.reinstall() } else { bonsai9Installer.remove() }
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
