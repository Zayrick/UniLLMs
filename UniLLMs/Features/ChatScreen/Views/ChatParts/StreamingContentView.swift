//
//  StreamingContentView.swift
//  UniLLMs
//
//  Displays streamed assistant content in a WebView.
//  Created by Codex on 2026/6/6.
//

import UIKit
import WebKit

final class StreamingContentView: UIView {
    enum Style {
        case response
        case thinking

        var textStyle: UIFont.TextStyle {
            switch self {
            case .response:
                return .body
            case .thinking:
                return .footnote
            }
        }

        var textColor: UIColor {
            switch self {
            case .response:
                return .label
            case .thinking:
                return .secondaryLabel
            }
        }
    }

    fileprivate var onContentHeightChanged: (() -> Void)?
    var content: String {
        bufferedContent
    }

    private let style: Style
    private let webView: WKWebView
    private var bufferedContent = ""
    private var isLoaded = false
    private var isRenderScheduled = false
    private var contentHeight: CGFloat = 0.0
    private var lastMeasuredWidth: CGFloat = 0.0
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    init(style: Style = .response) {
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
        style = .response
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

    func appendContent(_ contentDelta: String) {
        guard !contentDelta.isEmpty else {
            return
        }

        bufferedContent += contentDelta
        scheduleRender()
    }

    func setFinishedContent(_ content: String) {
        bufferedContent = content
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

        configureTraitObservation()
        loadRenderer()
    }

    private func configureTraitObservation() {
        traitChangeRegistration = registerForTraitChanges(
            [
                UITraitUserInterfaceStyle.self,
                UITraitPreferredContentSizeCategory.self
            ]
        ) { (view: StreamingContentView, _) in
            view.applyCurrentStyle()
        }
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
            "window.streamingRenderer.setContent(\(Self.javaScriptStringLiteral(bufferedContent)));",
            completionHandler: nil
        )
    }

    private func applyCurrentStyle() {
        guard isLoaded else {
            return
        }

        webView.evaluateJavaScript(
            "window.streamingRenderer.configure(\(styleConfigurationJavaScriptObject));",
            completionHandler: nil
        )
    }

    private func requestHeightUpdate() {
        guard isLoaded else {
            return
        }

        webView.evaluateJavaScript("window.streamingRenderer.requestHeightUpdate();", completionHandler: nil)
    }

    private func applyHeight(_ height: CGFloat) {
        let newHeight = ceil(max(0.0, height))
        guard abs(newHeight - contentHeight) > 0.5 else {
            return
        }

        contentHeight = newHeight
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onContentHeightChanged?()
    }

    private func loadRenderer() {
        guard let rendererURL = Self.rendererURL else {
            assertionFailure("Missing StreamingContentRenderer.html")
            return
        }

        webView.loadFileURL(
            rendererURL,
            allowingReadAccessTo: rendererURL.deletingLastPathComponent()
        )
    }

    private var styleConfigurationJavaScriptObject: String {
        let font = UIFont.preferredFont(forTextStyle: style.textStyle)
        return """
        {
            color: \(Self.javaScriptStringLiteral(style.textColor.cssString(resolvedWith: traitCollection))),
            linkColor: \(Self.javaScriptStringLiteral(UIColor.link.cssString(resolvedWith: traitCollection))),
            colorScheme: \(Self.javaScriptStringLiteral(traitCollection.userInterfaceStyle == .dark ? "dark" : "light")),
            fontSize: \(font.pointSize * 0.96)
        }
        """
    }

    private static var rendererURL: URL? {
        let subdirectories = [
            "StreamingContentRenderer",
            "Resources/StreamingContentRenderer"
        ]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(
                forResource: "StreamingContentRenderer",
                withExtension: "html",
                subdirectory: subdirectory
            ) {
                return url
            }
        }
        return Bundle.main.url(forResource: "StreamingContentRenderer", withExtension: "html")
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

final class StreamingContentHostView: UIView {
    private let contentView: StreamingContentView
    private let contentInsets: UIEdgeInsets
    private var contentHeightConstraint: NSLayoutConstraint!
    private var lastMeasuredWidth: CGFloat = 0.0

    var onLayoutInvalidated: (() -> Void)?

    var content: String {
        contentView.content
    }

    init(
        style: StreamingContentView.Style = .response,
        contentInsets: UIEdgeInsets = .zero
    ) {
        self.contentInsets = contentInsets
        contentView = StreamingContentView(style: style)
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        contentInsets = .zero
        contentView = StreamingContentView()
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: ceil(contentHeightConstraint.constant + contentInsets.top + contentInsets.bottom)
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateContentHeightIfNeeded()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingSize = contentView.sizeThatFits(
            CGSize(
                width: max(1.0, size.width - contentInsets.left - contentInsets.right),
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        return CGSize(
            width: size.width,
            height: ceil(fittingSize.height + contentInsets.top + contentInsets.bottom)
        )
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        sizeThatFits(targetSize)
    }

    func appendContent(_ contentDelta: String) {
        contentView.appendContent(contentDelta)
        updateContentHeight()
    }

    func setFinishedContent(_ content: String) {
        contentView.setFinishedContent(content)
        updateContentHeight()
    }

    func finishStreamingContent() {
        contentView.finishStreamingContent()
        updateContentHeight()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.onContentHeightChanged = { [weak self] in
            self?.updateContentHeight()
        }
        addSubview(contentView)

        contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: 0.0)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom),
            contentHeightConstraint
        ])
    }

    private func updateContentHeightIfNeeded() {
        let width = contentMeasurementWidth
        guard abs(width - lastMeasuredWidth) > 0.5 else {
            return
        }

        updateContentHeight()
    }

    private func updateContentHeight() {
        let width = contentMeasurementWidth
        guard width > 0.0 else {
            return
        }

        let height = contentView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        ).height
        let newHeight = ceil(height)
        let didChangeHeight = abs(newHeight - contentHeightConstraint.constant) > 0.5
        contentHeightConstraint.constant = newHeight
        lastMeasuredWidth = width
        invalidateIntrinsicContentSize()
        setNeedsLayout()

        if didChangeHeight {
            onLayoutInvalidated?()
        }
    }

    private var contentMeasurementWidth: CGFloat {
        max(
            bounds.width - contentInsets.left - contentInsets.right,
            (superview?.bounds.width ?? 0.0) - contentInsets.left - contentInsets.right,
            1.0
        )
    }
}

extension StreamingContentView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        applyCurrentStyle()
        renderNow()
        requestHeightUpdate()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        decisionHandler(.cancel)
    }
}

extension StreamingContentView: WKScriptMessageHandler {
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
