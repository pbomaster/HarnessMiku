import SwiftUI
import SafariServices
import CryptoKit
import Network
import Security

enum AccountWire {
    static let session = URLSession(configuration:.ephemeral,delegate:NoRedirect(),delegateQueue:nil)
    static let platform = "https://platform.deepseek.com"
    static func valid(_ text:String?, path:String) -> URL? {
        guard let text, let u=URLComponents(string:text), u.scheme=="https", u.host=="platform.deepseek.com",
              u.port == nil || u.port == 443, u.user == nil, u.password == nil, u.fragment == nil, u.path==path else { return nil }
        return u.url
    }
    static func random() throws -> String {
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else { throw MikuError("로그인 보안 코드를 만들 수 없어.") }
        return base64(Data(bytes))
    }
    static func base64(_ data:Data)->String {
        data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
    static func request(_ path:String, _ body:[String:String], token:String?=nil) async throws -> [String:Any] {
        var q=URLRequest(url:URL(string:platform+"/auth-api/v0/"+path)!)
        q.httpMethod="POST"; q.timeoutInterval=25
        q.setValue("application/json",forHTTPHeaderField:"Content-Type")
        q.setValue("web",forHTTPHeaderField:"x-client-platform"); q.setValue("en_US",forHTTPHeaderField:"x-client-locale")
        q.setValue("0.2.1-rc.5",forHTTPHeaderField:"x-client-version")
        q.setValue(String(TimeZone.current.secondsFromGMT()),forHTTPHeaderField:"x-client-timezone-offset")
        if let token { q.setValue(token,forHTTPHeaderField:"x-dsh-auth-token") }
        q.httpBody=try JSONSerialization.data(withJSONObject:body)
        let (data,r)=try await session.data(for:q)
        guard (r as? HTTPURLResponse)?.statusCode == 200, let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              obj["code"] as? Int == 0, let env=obj["data"] as? [String:Any], env["biz_code"] as? Int == 0 else {
            throw MikuError("DeepSeek가 계정 인증 요청을 승인하지 않았어. 다시 로그인해 줘.")
        }
        return env["biz_data"] as? [String:Any] ?? [:]
    }
}

struct LoginPage: Identifiable { let id=UUID(); let url:URL }
struct SystemBrowser: UIViewControllerRepresentable {
    let page:LoginPage
    let cancelled:()->Void
    final class Coordinator:NSObject,SFSafariViewControllerDelegate {
        let cancel:()->Void
        init(_ cancel:@escaping ()->Void){self.cancel=cancel}
        func safariViewControllerDidFinish(_ controller:SFSafariViewController){cancel()}
    }
    func makeCoordinator()->Coordinator { Coordinator(cancelled) }
    func makeUIViewController(context:Context)->SFSafariViewController {
        let vc=SFSafariViewController(url:page.url);vc.delegate=context.coordinator;return vc
    }
    func updateUIViewController(_ vc:SFSafariViewController,context:Context){}
}

@MainActor final class Login: ObservableObject {
    @Published var page:LoginPage?
    @Published var active=false
    @Published var message=""
    @Published var signedIn=false
    private var id=UUID(), verifier="", state="", redirect="", authorization=""
    private var server:NWListener?
    private var peers:[ObjectIdentifier:NWConnection]=[:]
    private var deadline:Task<Void,Never>?
    private var exchanging=false
    func refresh(){signedIn=(try? Keys.read(.account))?.isEmpty == false}
    func start(){
        guard !active else {return}
        do {
            verifier=try AccountWire.random();state=try AccountWire.random()
            let p=NWParameters.tcp
            p.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
            let listener=try NWListener(using:p);server=listener
            active=true;message="공식 로그인 페이지를 준비하고 있어."
            let attempt=id
            listener.stateUpdateHandler={ [weak self,weak listener] event in
                Task { @MainActor in
                    guard let self,self.id==attempt else{return}
                    switch event {
                    case .ready:
                        if let port=listener?.port { await self.initialize(port:port.rawValue,attempt:attempt) }
                    case .failed: self.end("아이폰의 로그인 콜백을 열 수 없어.")
                    default:break
                    }
                }
            }
            listener.newConnectionHandler={ [weak self] connection in
                Task { @MainActor in
                    guard let self,self.id==attempt,self.peers.count<8 else{connection.cancel();return}
                    self.peers[ObjectIdentifier(connection)]=connection
                    connection.start(queue:.main);self.receive(connection,Data(),attempt)
                }
            }
            listener.start(queue:.main);timeout(180,attempt)
        } catch { end(error.localizedDescription) }
    }
    private func timeout(_ seconds:Double,_ attempt:UUID){
        deadline?.cancel();deadline=Task { try? await Task.sleep(for:.seconds(seconds))
            if !Task.isCancelled && id==attempt { end("로그인 시간이 만료됐어. 다시 시도해 줘.") }
        }
    }
    private func initialize(port:UInt16,attempt:UUID) async {
        redirect="http://127.0.0.1:\(port)/oauth/callback"
        let proof=verifier
        do {
            let result=try await AccountWire.request("dsh/auth_init",["code_challenge":AccountWire.base64(Data(SHA256.hash(data:Data(proof.utf8)))),"code_challenge_method":"S256","state":state,"redirect_uri":redirect,"locale":"en_US","login_source":"web"])
            guard let aid=result["authorize_id"] as? String,!aid.isEmpty else {throw MikuError("인증 번호를 받지 못했어.")}
            guard attempt==id else {_ = try? await AccountWire.request("dsh/auth_cancel",["authorize_id":aid,"code_verifier":proof]);return}
            authorization=aid
            guard let url=AccountWire.valid(result["authorize_url"] as? String,path:"/dsh/authorize"),
                  let secs=result["expires_in"] as? Double,secs>0 else {throw MikuError("DeepSeek 로그인 주소를 확인할 수 없어.")}
            timeout(min(180,secs),attempt);page=LoginPage(url:url);message="DeepSeek에서 로그인을 승인해 줘."
        } catch { if attempt==id {end(error.localizedDescription)} }
    }
    private func receive(_ c:NWConnection,_ prefix:Data,_ attempt:UUID) {
        c.receive(minimumIncompleteLength:1,maximumLength:4096){ [weak self] data,_,done,error in
            Task { @MainActor in
                guard let self,self.id==attempt else {c.cancel();return}
                let buf=prefix+(data ?? Data())
                guard buf.count<=8192,error==nil else {self.close(c);return}
                guard buf.range(of:Data("\r\n\r\n".utf8)) != nil else {
                    if done {self.close(c)} else {self.receive(c,buf,attempt)};return
                }
                let request=String(decoding:buf,as:UTF8.self).components(separatedBy:"\r\n")[0].split(separator:" ")
                let u=request.count==3 && request[0]=="GET" ? URLComponents(string:String(request[1])) : nil
                let items=u?.queryItems ?? []
                let states=items.filter{$0.name=="state"}, codes=items.filter{$0.name=="code"}
                let code=codes.first?.value ?? ""
                let ok=u?.scheme==nil && u?.host==nil && u?.path=="/oauth/callback" && states.count==1 && states.first?.value==self.state && codes.count==1 && !code.isEmpty && !self.exchanging && self.page != nil
                let payload="HTTP/1.1 "+(ok ? "200 OK" : "400 Bad Request")+"\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"+(ok ? "Harness Miku로 돌아가세요." : "Invalid callback")
                c.send(content:Data(payload.utf8),completion:.contentProcessed{_ in Task { @MainActor in self.close(c) }})
                if ok {self.exchanging=true;self.page=nil;await self.exchange(code,attempt)}
            }
        }
    }
    private func close(_ c:NWConnection){peers.removeValue(forKey:ObjectIdentifier(c));c.cancel()}
    private func exchange(_ code:String,_ attempt:UUID) async {
        do {
            let existing=try Keys.read(.device)
            let device=existing.isEmpty ? UUID().uuidString : existing
            if existing.isEmpty {try Keys.write(device,to:.device)}
            let result=try await AccountWire.request("dsh/auth_exchange",["code":code,"code_verifier":verifier,"redirect_uri":redirect,"device_id":device,"device_model":"iPhone","os_version":UIDevice.current.systemVersion])
            guard attempt==id else{return}
            guard AccountWire.valid(result["authorized_url"] as? String,path:"/dsh/authorized") != nil,
                  let token=result["token"] as? String,!token.isEmpty,token.utf8.allSatisfy({(33...126).contains($0)}) else {throw MikuError("계정 인증 결과를 확인하지 못했어.")}
            try Keys.write(token,to:.account);UserDefaults.standard.set("account",forKey:"chatRoute")
            authorization="";end("DeepSeek 계정으로 연결했어.")
        } catch {if attempt==id {end(error.localizedDescription)}}
    }
    func end(_ note:String="로그인을 취소했어."){
        let aid=authorization,proof=verifier
        id=UUID();deadline?.cancel();deadline=nil;server?.cancel();server=nil
        for c in peers.values {c.cancel()};peers.removeAll()
        page=nil;active=false;exchanging=false;authorization="";verifier="";state="";message=note;refresh()
        if !aid.isEmpty {Task {_ = try? await AccountWire.request("dsh/auth_cancel",["authorize_id":aid,"code_verifier":proof])}}
    }
    func logout() async {
        do {let token=try Keys.read(.account);try Keys.write("",to:.account);refresh()
            message="이 기기에서 로그아웃했어."
            if !token.isEmpty {_ = try await AccountWire.request("users/logout",[:],token:token)}
        } catch {message="로그아웃 상태를 확인해 줘. "+error.localizedDescription}
    }
}
