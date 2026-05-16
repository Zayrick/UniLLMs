//
//  ThinkingSectionView.swift
//  UniLLMs
//
//  A collapsible "Thinking" panel mirroring the VS Code Copilot chat layout.
//  The header shows a chevron and a `ShimmerLabel` whose text shimmers while
//  the model is still reasoning. The body contains an ordered list of items
//  (reasoning text and tool invocations), each with a leading circular symbol
//  badge and a vertical connector line that draws the thinking timeline.
//

import UIKit

final class ThinkingSectionView: UIView {
    private enum Metrics {
        static let chevronPointSize: CGFloat = 11.0
        static let chevronSize: CGFloat = 14.0
        static let chevronTrailingSpacing: CGFloat = 6.0
        static let headerVerticalPadding: CGFloat = 6.0
        static let bodyTopPadding: CGFloat = 2.0
        static let bodyBottomPadding: CGFloat = 4.0
        static let itemLeadingInset: CGFloat = 24.0
        static let itemSpacing: CGFloat = 0.0
        static let connectorLeading: CGFloat = 10.5
        static let itemBadgeSize: CGFloat = 16.0
        static let itemBadgeLeading: CGFloat = connectorLeading - itemBadgeSize / 2.0
        static let itemSymbolPointSize: CGFloat = 9.0
        static let itemIconCenterY: CGFloat = 15.0
        static let chevronRotation: CGFloat = .pi / 2.0
        static let animationDuration: TimeInterval = 0.26
    }

    private struct TimelineIconStyle {
        var symbolName: String
        var fallbackSymbolNames: [String] = []
        var fillColor: UIColor
        var glyphColor: UIColor
    }

    private final class TimelineIconBadgeView: UIView {
        private let imageView = UIImageView()
        private let symbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Metrics.itemSymbolPointSize,
            weight: .semibold
        )

        override init(frame: CGRect) {
            super.init(frame: frame)
            configure()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = bounds.height / 2.0
        }

        func apply(_ style: TimelineIconStyle) {
            imageView.image = symbolImage(
                named: style.symbolName,
                fallbacks: style.fallbackSymbolNames
            )
            backgroundColor = style.fillColor
            imageView.tintColor = style.glyphColor
        }

        private func configure() {
            translatesAutoresizingMaskIntoConstraints = false
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            clipsToBounds = true

            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .center
            imageView.preferredSymbolConfiguration = symbolConfiguration
            imageView.isAccessibilityElement = false
            addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: Metrics.itemBadgeSize - 4.0),
                imageView.heightAnchor.constraint(equalToConstant: Metrics.itemBadgeSize - 4.0)
            ])
        }

        private func symbolImage(named name: String, fallbacks: [String]) -> UIImage? {
            for symbolName in [name] + fallbacks {
                if let image = UIImage(
                    systemName: symbolName,
                    withConfiguration: symbolConfiguration
                ) {
                    return image.withRenderingMode(.alwaysTemplate)
                }
            }
            return nil
        }
    }

    private final class ItemRow: UIView {
        let icon = TimelineIconBadgeView()
        let contentContainer = UIView()
        var hostedView: UIView?

        override init(frame: CGRect) {
            super.init(frame: frame)
            configure()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        private func configure() {
            translatesAutoresizingMaskIntoConstraints = false
            backgroundColor = .clear

            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)

            contentContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(contentContainer)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.itemBadgeLeading),
                icon.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.itemIconCenterY - Metrics.itemBadgeSize / 2.0),
                icon.widthAnchor.constraint(equalToConstant: Metrics.itemBadgeSize),
                icon.heightAnchor.constraint(equalToConstant: Metrics.itemBadgeSize),

                contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.itemLeadingInset),
                contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentContainer.topAnchor.constraint(equalTo: topAnchor),
                contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        func setHostedView(_ view: UIView) {
            hostedView?.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
            hostedView = view
        }

        func applyIconStyle(_ style: TimelineIconStyle) {
            icon.apply(style)
        }
    }

    // MARK: - Header

    private let containerStack = UIStackView()
    private let headerButton = UIControl()
    private let chevronImageView = UIImageView()
    private let titleLabel = ShimmerLabel()
    private let detailLabel = UILabel()

    // MARK: - Body

    private let bodyContainer = UIView()
    private let connectorLineView = ChatConnectorLineView()
    private let itemsStack = UIStackView()
    private var itemRows: [ItemRow] = []
    private var toolRowsByCallID: [String: ItemRow] = [:]
    private var isConnectorLineUpdateScheduled = false

    private var isCollapsed = false
    private var isThinking = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateConnectorLine()
    }

    // MARK: - Public API

    func appendReasoning(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        if let lastRow = itemRows.last,
           let reasoningTextView = lastRow.hostedView as? ReasoningTextView {
            reasoningTextView.append(text)
            setNeedsConnectorLineUpdate()
            return
        }

        let textView = ReasoningTextView()
        let row = makeRow(iconStyle: Self.reasoningIconStyle, hosted: textView)
        addRow(row)
        textView.append(text)
    }

    /// Append a tool-call row. If a row for the same `callID` already exists, the
    /// existing one is reused (e.g. on transitions from `.started` to `.completed`).
    @discardableResult
    func appendToolInvocation(
        callID: String,
        displayName: String,
        state: ToolInvocationView.State
    ) -> ToolInvocationView {
        if let existingRow = toolRowsByCallID[callID],
           let invocation = existingRow.hostedView as? ToolInvocationView {
            invocation.update(state: state)
            existingRow.applyIconStyle(Self.toolIconStyle(for: state))
            setNeedsConnectorLineUpdate()
            return invocation
        }

        let invocation = ToolInvocationView(callID: callID, displayName: displayName, state: state)
        let row = makeRow(iconStyle: Self.toolIconStyle(for: state), hosted: invocation)
        addRow(row)
        toolRowsByCallID[callID] = row
        return invocation
    }

    /// Updates an existing tool invocation, if any.
    func updateToolInvocation(callID: String, state: ToolInvocationView.State) {
        guard let row = toolRowsByCallID[callID],
              let invocation = row.hostedView as? ToolInvocationView else {
            return
        }
        invocation.update(state: state)
        row.applyIconStyle(Self.toolIconStyle(for: state))
        setNeedsConnectorLineUpdate()
    }

    func setThinking(_ thinking: Bool, animated: Bool) {
        guard isThinking != thinking else {
            return
        }
        isThinking = thinking
        titleLabel.isShimmering = thinking
        titleLabel.text = thinking ? "Thinking" : "Thought process"
        if !thinking {
            setCollapsed(true, animated: animated)
        }
    }

    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard collapsed != isCollapsed else {
            return
        }
        isCollapsed = collapsed
        headerButton.accessibilityValue = collapsed ? "Collapsed" : "Expanded"
        if !collapsed {
            bodyContainer.isHidden = false
            bodyContainer.alpha = 0.0
            containerStack.setCustomSpacing(Metrics.bodyTopPadding, after: headerButton)
            layoutIfNeeded()
            superview?.layoutIfNeeded()
        }

        let updates = {
            self.applyCollapsedLayout(collapsed)
        }

        let completion: () -> Void = {
            self.bodyContainer.isHidden = collapsed
            self.bodyContainer.alpha = collapsed ? 0.0 : 1.0
            self.containerStack.setCustomSpacing(
                collapsed ? 0.0 : Metrics.bodyTopPadding,
                after: self.headerButton
            )
            self.invalidateIntrinsicContentSize()
            self.superview?.setNeedsLayout()
        }

        guard animated, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            updates()
            completion()
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: Metrics.animationDuration,
            curve: .easeInOut,
            animations: updates
        )
        animator.addCompletion { _ in
            completion()
        }
        animator.startAnimation()
    }

    private func applyCollapsedLayout(_ collapsed: Bool) {
        bodyContainer.alpha = collapsed ? 0.0 : 1.0
        bodyContainer.isHidden = collapsed
        containerStack.setCustomSpacing(collapsed ? 0.0 : Metrics.bodyTopPadding, after: headerButton)
        chevronImageView.transform = collapsed
            ? .identity
            : CGAffineTransform(rotationAngle: Metrics.chevronRotation)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
        layoutIfNeeded()
        superview?.layoutIfNeeded()
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.axis = .vertical
        containerStack.alignment = .fill
        containerStack.spacing = 0.0
        addSubview(containerStack)

        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.addTarget(self, action: #selector(toggleCollapsed), for: .touchUpInside)
        headerButton.isAccessibilityElement = true
        headerButton.accessibilityTraits = .button
        headerButton.accessibilityLabel = "Thinking"
        headerButton.accessibilityValue = "Expanded"
        containerStack.addArrangedSubview(headerButton)

        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.image = UIImage(systemName: "chevron.right")
        chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Metrics.chevronPointSize,
            weight: .semibold
        )
        chevronImageView.tintColor = .tertiaryLabel
        chevronImageView.contentMode = .center
        chevronImageView.transform = CGAffineTransform(rotationAngle: Metrics.chevronRotation)
        headerButton.addSubview(chevronImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Thinking"
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.baseColor = .secondaryLabel
        titleLabel.isShimmering = true
        headerButton.addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .tertiaryLabel
        detailLabel.numberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail
        headerButton.addSubview(detailLabel)

        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.clipsToBounds = true
        containerStack.addArrangedSubview(bodyContainer)
        containerStack.setCustomSpacing(Metrics.bodyTopPadding, after: headerButton)

        connectorLineView.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(connectorLineView)

        itemsStack.translatesAutoresizingMaskIntoConstraints = false
        itemsStack.axis = .vertical
        itemsStack.alignment = .fill
        itemsStack.spacing = Metrics.itemSpacing
        bodyContainer.addSubview(itemsStack)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            chevronImageView.leadingAnchor.constraint(equalTo: headerButton.leadingAnchor, constant: 4.0),
            chevronImageView.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: Metrics.chevronSize),
            chevronImageView.heightAnchor.constraint(equalToConstant: Metrics.chevronSize),

            titleLabel.leadingAnchor.constraint(equalTo: chevronImageView.trailingAnchor, constant: Metrics.chevronTrailingSpacing),
            titleLabel.topAnchor.constraint(equalTo: headerButton.topAnchor, constant: Metrics.headerVerticalPadding),
            titleLabel.bottomAnchor.constraint(equalTo: headerButton.bottomAnchor, constant: -Metrics.headerVerticalPadding),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8.0),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerButton.trailingAnchor),
            detailLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            connectorLineView.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            connectorLineView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            connectorLineView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            connectorLineView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

            itemsStack.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            itemsStack.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            itemsStack.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            itemsStack.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -Metrics.bodyBottomPadding)
        ])
    }

    @objc private func toggleCollapsed() {
        setCollapsed(!isCollapsed, animated: true)
    }

    // MARK: - Item helpers

    private func makeRow(iconStyle: TimelineIconStyle, hosted: UIView) -> ItemRow {
        let row = ItemRow()
        row.applyIconStyle(iconStyle)
        row.setHostedView(hosted)
        return row
    }

    private static var reasoningIconStyle: TimelineIconStyle {
        TimelineIconStyle(
            symbolName: "brain.fill",
            fallbackSymbolNames: ["brain"],
            fillColor: .secondaryLabel,
            glyphColor: .systemBackground
        )
    }

    private static func toolIconStyle(for state: ToolInvocationView.State) -> TimelineIconStyle {
        let fillColor: UIColor
        switch state {
        case .running:
            fillColor = .secondaryLabel
        case .completed:
            fillColor = .systemGreen
        case .failed:
            fillColor = .systemRed
        }

        return TimelineIconStyle(
            symbolName: "wrench.adjustable.fill",
            fallbackSymbolNames: ["wrench.and.screwdriver.fill", "hammer.fill", "wrench.adjustable"],
            fillColor: fillColor,
            glyphColor: .systemBackground
        )
    }

    private func addRow(_ row: ItemRow) {
        itemsStack.addArrangedSubview(row)
        itemRows.append(row)
        connectorLineView.setConnectedCircleViews(itemRows.map(\.icon))
        setNeedsConnectorLineUpdate()
    }

    private func setNeedsConnectorLineUpdate() {
        bodyContainer.setNeedsLayout()
        itemsStack.setNeedsLayout()
        connectorLineView.setNeedsLayout()
        setNeedsLayout()
        scheduleConnectorLineUpdate()
    }

    private func updateConnectorLine() {
        bodyContainer.layoutIfNeeded()
        itemsStack.layoutIfNeeded()
        itemRows.forEach { $0.layoutIfNeeded() }
        connectorLineView.updateForCurrentCircleLayout()
    }

    private func scheduleConnectorLineUpdate() {
        guard !isConnectorLineUpdateScheduled else {
            return
        }

        isConnectorLineUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.isConnectorLineUpdateScheduled = false
            self.layoutIfNeeded()
            self.updateConnectorLine()
        }
    }

    // MARK: - Nested reasoning text view

    private final class ReasoningTextView: UITextView {
        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            configure()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure()
        }

        private func configure() {
            backgroundColor = .clear
            isEditable = false
            isScrollEnabled = false
            isSelectable = true
            textContainerInset = UIEdgeInsets(top: 6.0, left: 0.0, bottom: 6.0, right: 0.0)
            self.textContainer.lineFragmentPadding = 0.0
            dataDetectorTypes = [.link]
            setContentCompressionResistancePriority(.required, for: .vertical)
            setContentHuggingPriority(.required, for: .vertical)
            font = .preferredFont(forTextStyle: .footnote)
            adjustsFontForContentSizeCategory = true
            textColor = .secondaryLabel
        }

        func append(_ string: String) {
            guard !string.isEmpty else {
                return
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.secondaryLabel
            ]
            textStorage.beginEditing()
            textStorage.append(NSAttributedString(string: string, attributes: attributes))
            textStorage.endEditing()
            invalidateIntrinsicContentSize()
        }
    }
}
