import UIKit
import UserNotifications

final class AppDelegate:NSObject,UIApplicationDelegate,UNUserNotificationCenterDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
        UNUserNotificationCenter.current().delegate=self
        if UserDefaults.standard.bool(forKey:"replyAlerts"){application.registerForRemoteNotifications()}
        return true
    }
    func application(_ application:UIApplication,didRegisterForRemoteNotificationsWithDeviceToken token:Data){
        UserDefaults.standard.set(token.map{String(format:"%02x",$0)}.joined(),forKey:"pushToken")
    }
    func application(_ application:UIApplication,didFailToRegisterForRemoteNotificationsWithError error:Error){
        UserDefaults.standard.removeObject(forKey:"pushToken")
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification) async -> UNNotificationPresentationOptions {
        [] // The open conversation already displays the completed answer.
    }
}
enum Alerts {
    @MainActor static func authorize() async throws {
        guard try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) else {throw MikuError("설정 앱에서 Harness Miku 알림을 허용해 줘.")}
        UIApplication.shared.registerForRemoteNotifications()
    }
    @MainActor static func local(_ id:UUID) async {
        guard UIApplication.shared.applicationState != .active,UserDefaults.standard.bool(forKey:"replyAlerts") else{return}
        let content=UNMutableNotificationContent();content.title="Harness Miku";content.body="미쿠의 답변이 도착했어.";content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:id.uuidString,content:content,trigger:nil))
    }
}

enum Relay {
    static let session=URLSession(configuration:.ephemeral,delegate:NoRedirect(),delegateQueue:nil)
    static func base(_ value:String) throws -> URL {
        guard let c=URLComponents(string:value),c.scheme=="https",c.host != nil,c.user==nil,c.password==nil,c.fragment==nil,c.query==nil,c.path.isEmpty || c.path=="/",let url=c.url else {throw MikuError("개인 중계 서버의 HTTPS 주소를 확인해 줘.")}
        return url
    }
    static func call(_ id:UUID,_ origin:String,body:[String:Any]?=nil) async throws -> [String:Any] {
        guard try base(origin)==base(UserDefaults.standard.string(forKey:"relayOrigin") ?? "") else {throw MikuError("이 요청을 보낸 중계 주소로 설정을 복구해 줘.")}
        let pair=try Keys.read(.relay)
        guard !pair.isEmpty else { throw MikuError("중계 연결 키를 설정해 줘.") }
        var q=URLRequest(url:try base(origin).appendingPathComponent("jobs/"+id.uuidString))
        q.timeoutInterval=20;q.setValue("Bearer "+pair,forHTTPHeaderField:"Authorization")
        if let body {q.httpMethod="POST";q.setValue("application/json",forHTTPHeaderField:"Content-Type");q.httpBody=try JSONSerialization.data(withJSONObject:body)}
        let (data,r)=try await session.data(for:q)
        guard let http=r as? HTTPURLResponse else{throw MikuError("중계 응답을 확인할 수 없어.")}
        if http.statusCode==404{return ["state":"missing"]}
        guard (200..<300).contains(http.statusCode),let result=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw MikuError("개인 중계 연결을 확인해 줘 (HTTP \(http.statusCode)).")}
        return result
    }
    static func submit(_ request:URLRequest,account:Bool,id:UUID,origin:String) async throws {
        let token=UserDefaults.standard.string(forKey:"pushToken") ?? ""
        guard !token.isEmpty else {throw MikuError("APNs 등록이 아직 완료되지 않았어. 서명과 Push Notifications 권한을 확인해 줘.")}
        guard let data=request.httpBody,let auth=request.value(forHTTPHeaderField:account ? "x-dsh-auth-token" : "Authorization") else {throw MikuError("대화 요청을 만들지 못했어.")}
        _ = try await call(id,origin,body:["kind":account ? "account":"api","credential":auth,"request":try JSONSerialization.jsonObject(with:data),"device":token])
    }
}
