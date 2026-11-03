import Cocoa

final class Installer: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var job: Process?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let chooser = NSOpenPanel()
        chooser.title = "제작자에게 받은 RetrynowMiku 모델 ZIP을 선택하세요"
        chooser.allowedFileTypes = ["zip"]
        guard chooser.runModal() == .OK, let model = chooser.url else { NSApp.terminate(nil); return }
        let resources = Bundle.main.resourceURL!.appendingPathComponent("HarnessMiku")
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("HarnessMiku-\(UUID()).log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let output = try? FileHandle(forWritingTo: log) else {
            finish("설치 로그를 만들 수 없습니다."); return
        }
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 480,height: 110), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Harness Miku 설치"
        let label = NSTextField(wrappingLabelWithString: "설치 중입니다. 다운로드에 시간이 걸릴 수 있습니다. macOS 개발자 도구 설치 창이 뜨면 설치를 눌러 주세요.")
        label.frame = NSRect(x:20,y:20,width:440,height:65)
        window.contentView?.addSubview(label); window.center(); window.makeKeyAndOrderFront(nil)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [resources.appendingPathComponent("Install.command").path, model.path]
        task.standardOutput = output; task.standardError = output
        task.terminationHandler = { done in
            output.closeFile()
            DispatchQueue.main.async {
                if done.terminationStatus == 0 {
                    try? FileManager.default.removeItem(at: log)
                    self.finish("설치 완료. 사용자 응용 프로그램 폴더에서 Harness Miku를 실행하세요.")
                } else {
                    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                    self.finish("설치를 완료하지 못했습니다.\n\(String(text.suffix(700)))\n\n로그: \(log.path)")
                }
            }
        }
        job = task
        do { try task.run() } catch { output.closeFile(); finish(error.localizedDescription) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return job?.isRunning == true ? .terminateCancel : .terminateNow
    }
    func finish(_ text: String) {
        let alert = NSAlert(); alert.messageText = "Harness Miku"; alert.informativeText = text
        alert.runModal(); NSApp.terminate(nil)
    }
}
let app = NSApplication.shared
let delegate = Installer()
app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
