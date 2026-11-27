import SwiftUI
import WebKit

/// 路单排序界面：加载 App 内置的本地 HTML（离线可用）。
/// 通过 WKScriptMessageHandler 与 HTML 联动：
///  - noteBridge：HTML 里复制水印文案时，文案自动带入相机备注
///  - appBridge：HTML 里点「返回相机」时切回相机界面
///  - clipboardBridge：复制文案时同步写入系统剪贴板
///  - torchBridge：HTML 里点手电筒开关时，联动原生相机手电筒
struct RouteView: UIViewRepresentable {
    let onNoteCopied: (String) -> Void
    let onBackToCamera: () -> Void
    let onToggleTorch: () -> Void
    let torchOn: Bool
    let torchSupported: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onNoteCopied: onNoteCopied,
                    onBackToCamera: onBackToCamera,
                    onToggleTorch: onToggleTorch,
                    torchOn: torchOn,
                    torchSupported: torchSupported)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "noteBridge")
        contentController.add(context.coordinator, name: "appBridge")
        contentController.add(context.coordinator, name: "clipboardBridge")
        contentController.add(context.coordinator, name: "torchBridge")
        config.userContentController = contentController
        // 允许本地 html 读取同目录的 xlsx.js
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = UIColor.systemBackground

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "RouteWeb") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator
        c.onNoteCopied = onNoteCopied
        c.onBackToCamera = onBackToCamera
        c.onToggleTorch = onToggleTorch
        // 仅在 torch 状态真正变化时同步，避免时间定时器每秒触发无谓的 JS 调用
        let torchChanged = (c.torchOn != torchOn) || (c.torchSupported != torchSupported)
        c.torchOn = torchOn
        c.torchSupported = torchSupported
        if torchChanged {
            c.syncTorchState(to: webView)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UIDocumentPickerDelegate {
        var onNoteCopied: (String) -> Void
        var onBackToCamera: () -> Void
        var onToggleTorch: () -> Void
        var torchOn: Bool
        var torchSupported: Bool
        var pickerCompletion: (([URL]) -> Void)?

        init(onNoteCopied: @escaping (String) -> Void,
             onBackToCamera: @escaping () -> Void,
             onToggleTorch: @escaping () -> Void,
             torchOn: Bool,
             torchSupported: Bool) {
            self.onNoteCopied = onNoteCopied
            self.onBackToCamera = onBackToCamera
            self.onToggleTorch = onToggleTorch
            self.torchOn = torchOn
            self.torchSupported = torchSupported
        }

        /// 把手电筒当前状态同步给 HTML 按钮显示。
        func syncTorchState(to webView: WKWebView) {
            let js = "if (typeof window.setTorchState === 'function') { window.setTorchState(\(torchOn), \(torchSupported)); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // MARK: 页面加载完成后注入真实的顶部安全区高度
        // 让 HTML 把「返回相机」按钮下移到状态栏 / 灵动岛下方，避免无法点击。
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            var top = webView.safeAreaInsets.top
            if top <= 0 {
                // ignoresSafeArea 下 webView 自身 inset 可能为 0，回退到 keyWindow 的真实状态栏高度
                if #available(iOS 15.0, *) {
                    top = UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .flatMap { $0.windows }
                        .first { $0.isKeyWindow }?.safeAreaInsets.top ?? 0
                }
            }
            if top > 0 {
                let js = "document.documentElement.style.setProperty('--ios-safe-top', '\(top)px');"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            // 页面就绪后同步一次手电筒按钮状态
            syncTorchState(to: webView)
        }

        // MARK: JS 桥接
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            switch message.name {
            case "noteBridge":
                if let text = body["text"] as? String, !text.isEmpty {
                    DispatchQueue.main.async { self.onNoteCopied(text) }
                }
            case "appBridge":
                if let action = body["action"] as? String, action == "backToCamera" {
                    DispatchQueue.main.async { self.onBackToCamera() }
                }
            case "clipboardBridge":
                if let text = body["text"] as? String, !text.isEmpty {
                    DispatchQueue.main.async { UIPasteboard.general.string = text }
                }
            case "torchBridge":
                if let action = body["action"] as? String, action == "toggle" {
                    DispatchQueue.main.async { self.onToggleTorch() }
                }
            default:
                break
            }
        }

        // MARK: iOS 14+ 文件选择：HTML 的 <input type=file> 导入路单
        @available(iOS 14.0, *)
        func webView(_ webView: WKWebView,
                     runUIDocumentPicker picker: UIDocumentPickerViewController,
                     with completion: @escaping ([URL]) -> Void) {
            picker.delegate = self
            pickerCompletion = completion
            if let vc = webView.findViewController() {
                vc.present(picker, animated: true)
            }
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            pickerCompletion?(urls)
            pickerCompletion = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            pickerCompletion?([])
            pickerCompletion = nil
        }
    }
}

// MARK: - UIView 辅助：找到所在的 ViewController

extension UIView {
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let found = r as? UIViewController { return found }
            responder = r.next
        }
        return nil
    }
}
