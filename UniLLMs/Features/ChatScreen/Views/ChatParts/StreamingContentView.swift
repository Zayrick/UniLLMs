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
    private struct TimelineOptions: Encodable {
        var isStreaming: Bool
    }

    private struct TimelineItem: Encodable {
        enum Kind: String, Encodable {
            case reasoning
            case rawText
            case tool
        }

        enum ToolState: String, Encodable {
            case running
            case completed
            case failed
        }

        var id: String
        var kind: Kind
        var text: String?
        var callID: String?
        var displayName: String?
        var state: ToolState?
        var detail: String?
    }

    fileprivate var onContentHeightChanged: (() -> Void)?

    private let webView: WKWebView
    private var timelineItems: [TimelineItem] = []
    private var timelineItemSerial = 0
    private var isTimelineStreaming = false
    private var hasPreparedTimeline = false
    private var isLoaded = false
    private var isRenderScheduled = false
    private var contentHeight: CGFloat = 0.0
    private var lastMeasuredWidth: CGFloat = 0.0
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    override init(frame: CGRect) {
        let userContentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)
        userContentController.add(WeakScriptMessageHandler(target: self), name: Self.heightMessageHandlerName)
        configure()
    }

    required init?(coder: NSCoder) {
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyCurrentStyle()
        requestHeightUpdate()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: contentHeight)
    }

    func prepareTimelineRendering() {
        timelineItems = []
        timelineItemSerial = 0
        isTimelineStreaming = true
        hasPreparedTimeline = true
        scheduleRender()
    }

    func appendTimelineReasoning(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        ensureTimelineRendering()
        if timelineItems.last?.kind == .reasoning {
            timelineItems[timelineItems.count - 1].text = (timelineItems.last?.text ?? "") + text
        } else {
            timelineItems.append(
                TimelineItem(
                    id: nextTimelineItemID(prefix: "reasoning"),
                    kind: .reasoning,
                    text: text
                )
            )
        }
        scheduleRender()
    }

    func appendTimelineRawText(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        ensureTimelineRendering()
        if timelineItems.last?.kind == .rawText {
            timelineItems[timelineItems.count - 1].text = (timelineItems.last?.text ?? "") + text
        } else {
            timelineItems.append(
                TimelineItem(
                    id: nextTimelineItemID(prefix: "raw"),
                    kind: .rawText,
                    text: text
                )
            )
        }
        scheduleRender()
    }

    func appendTimelineToolEvent(_ event: ChatToolEvent) {
        ensureTimelineRendering()

        let toolCall: ChatToolCall
        let state: TimelineItem.ToolState
        let detail: String

        switch event {
        case let .started(startedToolCall):
            toolCall = startedToolCall
            state = .running
            detail = startedToolCall.serializedArguments
        case let .completed(completedToolCall, result):
            toolCall = completedToolCall
            state = .completed
            detail = result
        case let .failed(failedToolCall, message):
            toolCall = failedToolCall
            state = .failed
            detail = message
        }

        if let existingIndex = timelineItems.firstIndex(where: { $0.callID == toolCall.id }) {
            timelineItems[existingIndex].displayName = toolCall.presentationName
            timelineItems[existingIndex].state = state
            timelineItems[existingIndex].detail = detail
        } else {
            timelineItems.append(
                TimelineItem(
                    id: "tool-\(toolCall.id)",
                    kind: .tool,
                    callID: toolCall.id,
                    displayName: toolCall.presentationName,
                    state: state,
                    detail: detail
                )
            )
        }
        scheduleRender()
    }

    func finishTimelineRendering() {
        guard hasPreparedTimeline else {
            return
        }

        isTimelineStreaming = false
        renderNow()
        requestHeightUpdate()
    }

    func refreshAfterAncestorLayoutChange() {
        setNeedsLayout()
        webView.setNeedsLayout()
        webView.scrollView.setNeedsLayout()

        layoutIfNeeded()
        webView.layoutIfNeeded()
        webView.scrollView.layoutIfNeeded()
        requestHeightUpdate()
    }

    private func ensureTimelineRendering() {
        guard !hasPreparedTimeline else {
            return
        }

        prepareTimelineRendering()
    }

    private func nextTimelineItemID(prefix: String) -> String {
        timelineItemSerial += 1
        return "\(prefix)-\(timelineItemSerial)"
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
            """
            window.streamingRenderer.setTimeline(
                \(Self.javaScriptValueLiteral(timelineItems)),
                \(Self.javaScriptValueLiteral(TimelineOptions(isStreaming: isTimelineStreaming)))
            );
            """,
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
            assertionFailure("Missing streaming renderer HTML")
            return
        }

        webView.loadFileURL(
            rendererURL,
            allowingReadAccessTo: rendererURL.deletingLastPathComponent()
        )
    }

    private var styleConfigurationJavaScriptObject: String {
        let font = UIFont.preferredFont(forTextStyle: .body)
        return """
        {
            color: \(Self.javaScriptStringLiteral(UIColor.label.cssString(resolvedWith: traitCollection))),
            linkColor: \(Self.javaScriptStringLiteral(UIColor.link.cssString(resolvedWith: traitCollection))),
            secondaryColor: \(Self.javaScriptStringLiteral(UIColor.secondaryLabel.cssString(resolvedWith: traitCollection))),
            tertiaryColor: \(Self.javaScriptStringLiteral(UIColor.tertiaryLabel.cssString(resolvedWith: traitCollection))),
            separatorColor: \(Self.javaScriptStringLiteral(UIColor.separator.cssString(resolvedWith: traitCollection))),
            successColor: \(Self.javaScriptStringLiteral(UIColor.systemGreen.cssString(resolvedWith: traitCollection))),
            errorColor: \(Self.javaScriptStringLiteral(UIColor.systemRed.cssString(resolvedWith: traitCollection))),
            colorScheme: \(Self.javaScriptStringLiteral(traitCollection.userInterfaceStyle == .dark ? "dark" : "light")),
            fontSize: \(font.pointSize * 0.96),
            language: \(Self.javaScriptStringLiteral(Self.rendererLanguageIdentifier))
        }
        """
    }

    private static var rendererURL: URL? {
        Bundle.main.url(forResource: "index", withExtension: "html")
    }

    private static var rendererLanguageIdentifier: String {
        let appPreferredLocalizations = Bundle.main.preferredLocalizations.filter { $0 != "Base" }
        let preferences = appPreferredLocalizations.isEmpty ? Locale.preferredLanguages : appPreferredLocalizations
        return Bundle.preferredLocalizations(
            from: supportedRendererLanguageIdentifiers,
            forPreferences: preferences
        ).first ?? "en"
    }

    private static let supportedRendererLanguageIdentifiers = ["en", "zh-Hans"]
    private static let heightMessageHandlerName = "heightUpdate"

    private static func javaScriptStringLiteral(_ string: String) -> String {
        let encoded = javaScriptValueLiteral(string)
        return encoded == "null" ? "\"\"" : encoded
    }

    private static func javaScriptValueLiteral<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return encoded
    }
}

final class StreamingContentHostView: UIView {
    private let contentView = StreamingContentView()
    private var contentHeightConstraint: NSLayoutConstraint!
    private var lastMeasuredWidth: CGFloat = 0.0

    var onLayoutInvalidated: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: ceil(contentHeightConstraint.constant))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateContentHeightIfNeeded()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingSize = contentView.sizeThatFits(
            CGSize(
                width: max(1.0, size.width),
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        return CGSize(width: size.width, height: ceil(fittingSize.height))
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        sizeThatFits(targetSize)
    }

    func prepareTimelineRendering() {
        contentView.prepareTimelineRendering()
        updateContentHeight()
    }

    func appendTimelineReasoning(_ text: String) {
        contentView.appendTimelineReasoning(text)
        updateContentHeight()
    }

    func appendTimelineRawText(_ text: String) {
        contentView.appendTimelineRawText(text)
        updateContentHeight()
    }

    func appendTimelineToolEvent(_ event: ChatToolEvent) {
        contentView.appendTimelineToolEvent(event)
        updateContentHeight()
    }

    func finishTimelineRendering() {
        contentView.finishTimelineRendering()
        updateContentHeight()
    }

    func refreshAfterAncestorLayoutChange() {
        setNeedsLayout()
        layoutIfNeeded()
        contentView.refreshAfterAncestorLayoutChange()
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
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
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
            bounds.width,
            superview?.bounds.width ?? 0.0,
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
