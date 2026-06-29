import UIKit
import WebKit

class WebViewController: UIViewController, WKScriptMessageHandler {

    var initialURLString: String = "https://sandbox.virgopay.co/page#/widget/login?type=1&code=your_code"
    var theme: String = "dark"
    var primaryColor: String = "#4F46E5"
    var addressInfo: String = "string"

    private var webView: WKWebView!

    private var widgetConfig: [String: Any] {
        return [
            "host": "virgopay",
            "theme": theme,
            "primaryColor": primaryColor,
            "isMobileApp": true,
            "logoUrl": "original",
            "addressInfo": addressInfo,
            "nonce": ""
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupWebView()
        loadInitialURL()
    }

    private func setupWebView() {
        let contentController = WKUserContentController()

        let js = injectedJavaScript(theme: theme, primaryColor: primaryColor, addressInfo: addressInfo)
        let userScript = WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(userScript)

        // JS -> iOS:
        // window.ReactNativeWebView.postMessage(...)
        contentController.add(self, name: "iosBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadInitialURL() {
        guard let url = URL(string: initialURLString) else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    private func injectedJavaScript(theme: String, primaryColor: String, addressInfo: String) -> String {
        let js = """
        (function() {
            if (!window.ReactNativeWebView) {
                window.ReactNativeWebView = {
                    postMessage: function(data) {
                        if (window.webkit &&
                            window.webkit.messageHandlers &&
                            window.webkit.messageHandlers.iosBridge) {
                            window.webkit.messageHandlers.iosBridge.postMessage(data);
                        }
                    }
                };
            }
        })();
        true;
        """
        return js
    }

    // iOS -> WebView
    // 等价于 RN:
    // webRef.current?.postMessage(JSON.stringify({ type, payload }))
    private func postToWeb(_ type: String, payload: [String: Any] = [:]) {
        let message: [String: Any] = [
            "type": type,
            "payload": payload
        ]

        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message, options: []),
              let jsonString = String(data: data, encoding: .utf8),
              let jsStringLiteral = makeJavaScriptStringLiteral(jsonString) else {
            print("postToWeb: invalid message")
            return
        }

        let js = """
        (function() {
            var data = \(jsStringLiteral);

            function dispatchMessage(target) {
                try {
                    target.dispatchEvent(new MessageEvent('message', {
                        data: data
                    }));
                } catch (e) {
                    try {
                        var event = document.createEvent('MessageEvent');
                        event.initMessageEvent('message', false, false, data, '*', '', null);
                        target.dispatchEvent(event);
                    } catch (err) {}
                }
            }

            dispatchMessage(window);
            dispatchMessage(document);
        })();
        true;
        """

        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("postToWeb error:", error)
                }
            }
        }
    }

    private func makeJavaScriptStringLiteral(_ string: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
              let arrayString = String(data: data, encoding: .utf8) else {
            return nil
        }

        // ["xxx"] -> "xxx"
        guard arrayString.count >= 2 else { return nil }
        return String(arrayString.dropFirst().dropLast())
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "iosBridge" else { return }

        if let bodyString = message.body as? String {
            handleMessageFromJS(bodyString)
        } else if let bodyDict = message.body as? [String: Any] {
            handleMessageDict(bodyDict)
        } else {
            showAlert(title: "Message", message: "Unsupported body: \(message.body)")
        }
    }

    private func handleMessageFromJS(_ data: String) {
        guard !data.isEmpty, data != "[object Object]" else {
            return
        }

        guard let jsonData = data.data(using: .utf8) else {
            showAlert(title: "Error", message: "Invalid string data: \(data)")
            return
        }

        do {
            if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                handleMessageDict(dict)
            } else {
                showAlert(title: "Error", message: "JSON is not an object")
            }
        } catch {
            showAlert(title: "Error", message: "JSON parse error: \(error.localizedDescription)")
        }
    }

    private func handleMessageDict(_ dict: [String: Any]) {
        let normalizedDict = normalizeMessageDict(dict)

        let type = normalizedDict["type"] as? String ?? ""
        let payload = normalizedDict["payload"] as? [String: Any] ?? [:]

        switch type {
        // ====== Handshake / Config passing ======
        case "REQUEST_CONFIG", "PING":
            postToWeb("WIDGET_CONFIG", payload: widgetConfig)

        // ====== Business Messages ======
        case "TRANSACTION_ID":
            let id = payload["id"] as? String ?? "null"
            showAlert(title: "TRANSACTION_ID", message: "id = \(id)")

        case "OPEN_LINK":
            if let urlStr = payload["url"] as? String,
               let url = URL(string: urlStr) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                showAlert(title: "OPEN_LINK", message: "Missing or invalid url")
            }

        case "TRANSACTION_FUND":
            break

        case "MAIL_TO":
            let url = payload["url"] as? String ?? "null"
            showAlert(title: "MAIL_TO", message: url)

        case "CUSTOMER_ID":
            let customerId = payload["customerId"] as? String ?? "null"
            print("CUSTOMER_ID:", customerId)

        case "NONCE":
            let nonce = payload["nonce"] as? String ?? "null"
            showAlert(title: "NONCE", message: nonce)

        case "LOG_OUT":
            break

        default:
            showAlert(title: "Unhandled type", message: type)
        }
    }

    private func normalizeMessageDict(_ dict: [String: Any]) -> [String: Any] {
        let type = dict["type"] as? String ?? ""

        if type == "message" {
            if let dataDict = dict["data"] as? [String: Any] {
                return dataDict
            }

            if let dataString = dict["data"] as? String,
               let parsed = parseJSONStringToDict(dataString) {
                return parsed
            }

            if let payloadDict = dict["payload"] as? [String: Any] {
                return payloadDict
            }

            if let payloadString = dict["payload"] as? String,
               let parsed = parseJSONStringToDict(payloadString) {
                return parsed
            }
        }

        return dict
    }

    private func parseJSONStringToDict(_ string: String) -> [String: Any]? {
        guard !string.isEmpty,
              string != "[object Object]",
              let data = string.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(title: title,
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "iosBridge")
    }
}

extension WebViewController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 等价于 RN:
        // onLoadEnd={() => postToWeb("PING", {})}
        postToWeb("PING")
    }
}