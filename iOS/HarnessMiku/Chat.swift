import SwiftUI
import UIKit

@MainActor final class Chat: ObservableObject {
    @Published var lines:[Line]=[]
    @Published var draft=""
    @Published var waiting=false
    @Published private(set) var localProgress: String?
    @Published var problem:String?
    private var task:Task<Void,Never>?
    private var generation=UUID()
    private var pending:Pending?
    private struct Pending:Codable {let id:UUID;let origin:String;var sources:[WebSource]?=nil}
    private struct Record:Codable {let lines:[Line];let pending:Pending?}
    private let url=URL.applicationSupportDirectory.appendingPathComponent("dialogue.json")
    init(){
        if let data=try? Data(contentsOf:url){
            if let saved=try? JSONDecoder().decode(Record.self,from:data){lines=saved.lines;pending=saved.pending}
            else {lines=(try? JSONDecoder().decode([Line].self,from:data)) ?? []}
        }
    }
    var hasPendingReply: Bool { pending != nil }
    func send(searchMode:SearchMode, retry:Bool=false, spokenText: String? = nil,completion:@escaping (String)->Void) {
        guard !waiting else{return}
        if pending != nil {
            if LocalMiku.selected { problem = "이전 중계 답변이 남아 있어. DeepSeek 모드에서 받은 뒤 다시 시도해 줘." }
            else { resume(completion: completion) }
            return
        }
        let text=(spokenText ?? draft).trimmingCharacters(in:.whitespacesAndNewlines)
        guard retry ? lines.last?.role=="user" : !text.isEmpty else{return}
        let local = LocalMiku.selected
        let localModel = LocalMiku.model
        do {
            if !local { _ = try Service.credential() }
            if retry {
                guard (lines.last?.local == true) == local else { throw MikuError("이 메시지를 보냈던 대화 모델로 바꾼 뒤 다시 시도해 줘.") }
                lines[lines.count - 1].searchMode = searchMode
            } else {
                guard (local && localModel == .bonsai) || text.count<=8000 else{throw MikuError("한 번에 8,000자까지 보낼 수 있어.")}
                lines.append(Line(local:local,searchMode:searchMode,role:"user",content:text))
                if spokenText == nil { draft="" }
            }
        } catch {problem=error.localizedDescription;return}
        let id=UUID(),snapshot=lines.filter { ($0.local == true) == local }
        generation=id;waiting=true;problem=nil;save()
        localProgress = local ? "\(localModel.title) 여는 중" : nil
        let useRelay=UserDefaults.standard.bool(forKey:"remoteReply") && UserDefaults.standard.bool(forKey:"replyAlerts")
        task=Task {
            // Cover the short transition into background; iOS controls the deadline.
            var bg:UIBackgroundTaskIdentifier = .invalid
            bg=UIApplication.shared.beginBackgroundTask(withName:"Harness Miku reply"){
                Task { @MainActor in if self.generation==id {self.task?.cancel()} }
            }
            defer {if bg != .invalid {UIApplication.shared.endBackgroundTask(bg)}}
            do {
                try Task.checkCancellation()
                if let last = snapshot.last, (local || last.effectiveSearchMode != .always),
                   let reply = ConversationFacts.clockReply(to: last.content), generation == id {
                    finish(reply, id, [], completion, local: local)
                    return
                }
                if local {
                    let reply = try await LocalMiku.reply(snapshot, model: localModel) { status in
                        Task { @MainActor in
                            if self.generation == id && self.waiting { self.localProgress = status }
                        }
                    }
                    try Task.checkCancellation()
                    guard generation == id else { return }
                    finish(reply, id, [], completion, local: true)
                    return
                }
                let route = try await Service.modelRoute()
                let query = try await Service.searchQuery(snapshot, route: route)
                try Task.checkCancellation()
                var hits: [WebHit] = []
                if let query { hits = try await Service.lookup(query, route: route) }
                try Task.checkCancellation()
                let sources=hits.map(\.source)
                let req = try Service.inference(snapshot, hits: hits, route: route)
                let account = route.account
                guard generation==id else{return}
                if useRelay {
                    let origin=UserDefaults.standard.string(forKey:"relayOrigin") ?? ""
                    _ = try Relay.base(origin)
                    guard !(try Keys.read(.relay)).isEmpty, !(UserDefaults.standard.string(forKey:"pushToken") ?? "").isEmpty else {throw MikuError("APNs 등록과 개인 중계 키 설정을 먼저 확인해 줘.")}
                    let job=Pending(id:id,origin:origin,sources:sources)
                    pending=job;save()
                    try await Relay.submit(req,account:account,id:id,origin:origin)
                    try await poll(job,completion)
                } else {
                    let reply=try await Service.reply(req,account:account)
                    guard generation==id else{return}
                    finish(reply,id,sources,completion);await Alerts.local(id)
                }
            } catch {if generation==id {waiting=false;localProgress=nil;problem=error.localizedDescription}}
        }
    }
    func resume(completion:@escaping(String)->Void){
        guard !LocalMiku.selected, !waiting,let job=pending else{return}
        generation=job.id;waiting=true;problem=nil
        task=Task {
            do {try await poll(job,completion)}
            catch {if generation==job.id {waiting=false;problem=error.localizedDescription}}
        }
    }
    private func poll(_ job:Pending,_ completion:@escaping(String)->Void) async throws {
        while generation==job.id {
            try Task.checkCancellation()
            let result=try await Relay.call(job.id,job.origin)
            guard generation==job.id else{return}
            switch result["state"] as? String {
            case "done":
                guard let reply=result["reply"] as? String,!reply.isEmpty else {throw MikuError("빈 중계 응답이야.")}
                finish(reply,job.id,job.sources ?? [],completion);return
            case "failed","missing":
                pending=nil;save();throw MikuError((result["error"] as? String) ?? "중계에 보관된 답변이 없어. 다시 요청해 줘.")
            case "running":try await Task.sleep(for:.seconds(2))
            default:throw MikuError("중계 응답 형식을 확인해 줘.")
            }
        }
    }
    private func finish(_ reply:String,_ id:UUID,_ sources:[WebSource],_ completion:(String)->Void, local: Bool = false){
        pending=nil;waiting=false;localProgress=nil;problem=nil
        let directed = Performance(reply).tone == nil ? "[soft]\n" + reply : reply
        lines.append(Line(local:local,sources:sources,id:id,role:"assistant",content:directed));save();completion(directed)
    }
    func stopLocalReply() {
        guard localProgress != nil else { return }
        generation = UUID()
        task?.cancel()
        localProgress = nil
        waiting = false
        problem = "답변 생성을 중지했어."
    }
    func clear(){localProgress=nil;generation=UUID();task?.cancel();waiting=false;pending=nil;lines=[];draft="";problem=nil;save()}
    private func save(){
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(Record(lines:lines,pending:pending)).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }catch{problem="대화 기록을 기기에 저장하지 못했어."}
    }
}
