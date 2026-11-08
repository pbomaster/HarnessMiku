import SwiftUI
import WebKit
import UniformTypeIdentifiers

private final class StageFiles: NSObject, WKURLSchemeHandler {
    let root = Bundle.main.bundleURL.appendingPathComponent("Stage").standardizedFileURL
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "stage" else { task.didFailWithError(URLError(.badURL)); return }
        let file = root.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf:file,options:.mappedIfSafe) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let type = ["js":"application/javascript","html":"text/html","json":"application/json","png":"image/png"][file.pathExtension] ?? "application/octet-stream"
        guard let response = HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",
              headerFields:["Content-Type":type,"Access-Control-Allow-Origin":"*"]) else { task.didFailWithError(URLError(.badServerResponse)); return }
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct Stage: UIViewRepresentable {
    @ObservedObject var voice: Voice
    @Environment(\.accessibilityReduceMotion) var reduced
    enum Framing: String { case portrait, thighs }
    var framing: Framing = .portrait
    var onTouch: (String) -> Void
    var onFallback: () -> Void
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var fallback: () -> Void
        var previous = ""
        var latest = ""
        var loadedFraming: Framing?
        var onTouch: (String) -> Void
        init(_ fallback: @escaping () -> Void, _ onTouch: @escaping (String) -> Void) {
            self.fallback = fallback; self.onTouch = onTouch
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.host == "stage" else { return }
            if let body=message.body as? [String:String], let line=body["line"], !line.isEmpty, line.count<=180 { onTouch(line); return }
            if message.body as? String == "fallback" { fallback() }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler(url?.scheme == "miku" && url?.host == "stage" ? .allow : .cancel)
        }
        func applyPose(to webView: WKWebView) {
            let command = latest
            guard !command.isEmpty, command != previous else { return }
            webView.evaluateJavaScript(command) { [weak self] result, _ in
                guard let self, result as? Bool == true, self.latest == command else { return }
                self.previous = command
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            previous = ""
            applyPose(to: webView)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { previous = ""; webView.reload() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onFallback,onTouch) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(StageFiles(),forURLScheme:"miku")
        config.userContentController.add(context.coordinator,name:"stage")
        let view = WKWebView(frame:.zero,configuration:config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = .clear; view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false; view.isUserInteractionEnabled = true
        load(view, coordinator: context.coordinator)
        return view
    }
    private func load(_ view: WKWebView, coordinator: Coordinator) {
        guard coordinator.loadedFraming != framing else { return }
        coordinator.loadedFraming = framing
        coordinator.previous = ""
        // SwiftUI supplies the full-screen window bounds, including the bottom and side rails.
        // WKWebView must not subtract the same safe areas a second time.
        view.scrollView.contentInsetAdjustmentBehavior = framing == .thighs ? .never : .automatic
        if framing == .thighs { view.scrollView.contentInset = .zero }
        view.load(URLRequest(url: URL(string: "miku://stage/index.html?framing=" + framing.rawValue)!))
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        load(uiView, coordinator: context.coordinator)
        context.coordinator.onTouch = onTouch
        let pose = voice.mouth
        let command = "window.mikuPose ? (window.mikuPose(\(pose.open),\(pose.form),\(pose.pucker),\(reduced ? "true" : "false")), true) : false"
        context.coordinator.latest = command
        context.coordinator.applyPose(to: uiView)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName:"stage")
        view.stopLoading()
    }
}
