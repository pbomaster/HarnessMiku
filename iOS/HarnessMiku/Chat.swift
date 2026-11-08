import SwiftUI
import UIKit

@MainActor final class Chat: ObservableObject {
    @Published var lines:[Line]=[]
    @Published var draft=""
    @Published var waiting=false
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
            resume(completion: completion)
            return
        }
        let text=(spokenText ?? draft).trimmingCharacters(in:.whitespacesAndNewlines)
        guard retry ? lines.last?.role=="user" : !text.isEmpty else{return}
        do {
            _ = try Service.credential()
            if retry {
                guard lines.last?.local != true else { throw MikuError("이전 기기 전용 메시지는 다시 보낼 수 없어.") }
                lines[lines.count - 1].searchMode = searchMode
            } else {
                guard text.count<=8000 else{throw MikuError("한 번에 8,000자까지 보낼 수 있어.")}
                lines.append(Line(searchMode:searchMode,role:"user",content:text))
                if spokenText == nil { draft="" }
            }
        } catch {problem=error.localizedDescription;return}
        // Earlier releases stored device-only turns beside remote turns.
        let id=UUID(),snapshot=lines.filter { $0.local != true }
        generation=id;waiting=true;problem=nil;save()
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
                if let last = snapshot.last, last.effectiveSearchMode != .always,
                   let reply = ConversationFacts.clockReply(to: last.content), generation == id {
                    finish(reply, id, [], completion)
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
            } catch {if generation==id {waiting=false;problem=error.localizedDescription}}
        }
    }
    func resume(completion:@escaping(String)->Void){
        guard !waiting,let job=pending else{return}
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
    private func finish(_ reply:String,_ id:UUID,_ sources:[WebSource],_ completion:(String)->Void){
        pending=nil;waiting=false;problem=nil
        let directed = Performance(reply).tone == nil ? "[soft]\n" + reply : reply
        lines.append(Line(sources:sources,id:id,role:"assistant",content:directed));save();completion(directed)
    }
    func clear(){generation=UUID();task?.cancel();waiting=false;pending=nil;lines=[];draft="";problem=nil;save()}
    private func save(){
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(Record(lines:lines,pending:pending)).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }catch{problem="대화 기록을 기기에 저장하지 못했어."}
    }
}
