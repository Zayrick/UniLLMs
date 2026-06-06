//
//  StreamingPlainTextView.swift
//  UniLLMs
//
//  Displays streamed assistant text in a WebView without parsing markup.
//  Created by Codex on 2026/6/6.
//

import UIKit
import WebKit

final class StreamingPlainTextView: UIView {
    enum Style {
        case rawText
        case thinking

        var textStyle: UIFont.TextStyle {
            switch self {
            case .rawText:
                return .body
            case .thinking:
                return .callout
            }
        }

        var textColor: UIColor {
            switch self {
            case .rawText:
                return .label
            case .thinking:
                return .secondaryLabel
            }
        }
    }

    var onNeedsHeightUpdate: (() -> Void)?
    var plainText: String {
        bufferedText
    }

    private let style: Style
    private let webView: WKWebView
    private var bufferedText = ""
    private var isLoaded = false
    private var isRenderScheduled = false
    private var contentHeight: CGFloat = 0.0
    private var lastMeasuredWidth: CGFloat = 0.0

    init(style: Style = .rawText) {
        self.style = style
        let userContentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        userContentController.add(WeakScriptMessageHandler(target: self), name: Self.heightMessageHandlerName)
        configure()
    }

    required init?(coder: NSCoder) {
        style = .rawText
        let userContentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(coder: coder)
        userContentController.add(WeakScriptMessageHandler(target: self), name: Self.heightMessageHandlerName)
        configure()
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.heightMessageHandlerName
        )
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0.0,
              abs(bounds.width - lastMeasuredWidth) > 0.5 else {
            return
        }

        lastMeasuredWidth = bounds.width
        requestHeightUpdate()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: contentHeight)
    }

    func appendText(_ textDelta: String) {
        guard !textDelta.isEmpty else {
            return
        }

        bufferedText += textDelta
        scheduleRender()
    }

    func setFinishedText(_ text: String) {
        bufferedText = text
        renderNow()
    }

    func finishStreamingContent() {
        renderNow()
        requestHeightUpdate()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)

        webView.navigationDelegate = self
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        webView.loadHTMLString(makeHTML(), baseURL: nil)
    }

    private func scheduleRender() {
        guard isLoaded, !isRenderScheduled else {
            return
        }

        isRenderScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.renderNow()
        }
    }

    private func renderNow() {
        guard isLoaded else {
            return
        }

        isRenderScheduled = false
        webView.evaluateJavaScript(
            "window.setPlainTextContent(\(Self.javaScriptStringLiteral(bufferedText)));",
            completionHandler: nil
        )
    }

    private func requestHeightUpdate() {
        guard isLoaded else {
            return
        }

        webView.evaluateJavaScript("window.requestPlainTextHeightUpdate();", completionHandler: nil)
    }

    private func applyHeight(_ height: CGFloat) {
        let newHeight = ceil(max(0.0, height))
        guard abs(newHeight - contentHeight) > 0.5 else {
            return
        }

        contentHeight = newHeight
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onNeedsHeightUpdate?()
    }

    private func makeHTML() -> String {
        let font = UIFont.preferredFont(forTextStyle: style.textStyle)
        let lineHeight = max(font.lineHeight, font.pointSize * 1.18)
        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <style>
        html, body {
            margin: 0;
            padding: 0;
            width: 100%;
            overflow: hidden;
            background: transparent;
            -webkit-text-size-adjust: 100%;
        }
        body {
            color: \(style.textColor.cssString(resolvedWith: traitCollection));
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: \(font.pointSize)px;
            line-height: \(lineHeight)px;
        }
        #content {
            width: 100%;
            white-space: pre-wrap;
            overflow-wrap: anywhere;
            word-break: break-word;
            -webkit-user-select: text;
            user-select: text;
        }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
        (() => {
            const content = document.getElementById("content");
            const renderInterval = 1000 / 20;
            let text = "";
            let renderScheduled = false;
            let heightScheduled = false;
            let lastRenderTime = 0;

            function postHeight() {
                heightScheduled = false;
                const height = Math.ceil(content.getBoundingClientRect().height);
                window.webkit.messageHandlers.\(Self.heightMessageHandlerName).postMessage(height);
            }

            window.requestPlainTextHeightUpdate = function() {
                if (heightScheduled) {
                    return;
                }
                heightScheduled = true;
                requestAnimationFrame(postHeight);
            };

            function renderText(timestamp) {
                if (lastRenderTime > 0 && timestamp - lastRenderTime < renderInterval) {
                    requestAnimationFrame(renderText);
                    return;
                }

                renderScheduled = false;
                lastRenderTime = timestamp;
                if (content.textContent !== text) {
                    content.textContent = text;
                }
                window.requestPlainTextHeightUpdate();
            }

            window.setPlainTextContent = function(nextText) {
                text = nextText || "";
                if (renderScheduled) {
                    return;
                }
                renderScheduled = true;
                requestAnimationFrame(renderText);
            };

            window.addEventListener("resize", window.requestPlainTextHeightUpdate);
            window.requestPlainTextHeightUpdate();
        })();
        </script>
        </body>
        </html>
        """
    }

    private static let heightMessageHandlerName = "heightUpdate"

    private static func javaScriptStringLiteral(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }
}

extension StreamingPlainTextView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        renderNow()
        requestHeightUpdate()
    }
}

extension StreamingPlainTextView: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.heightMessageHandlerName else {
            return
        }

        if let height = message.body as? NSNumber {
            applyHeight(CGFloat(truncating: height))
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

private extension UIColor {
    func cssString(resolvedWith traitCollection: UITraitCollection) -> String {
        let resolvedColor = resolvedColor(with: traitCollection)
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "rgba(\(Self.cssColorComponent(red)), \(Self.cssColorComponent(green)), \(Self.cssColorComponent(blue)), \(alpha))"
    }

    private static func cssColorComponent(_ component: CGFloat) -> Int {
        Int(round(max(0.0, min(1.0, component)) * 255.0))
    }
}
