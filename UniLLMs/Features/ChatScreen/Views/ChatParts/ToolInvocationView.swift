//
//  ToolInvocationView.swift
//  UniLLMs
//
//  Renders a single tool invocation inside the assistant's response, mimicking
//  the VS Code Copilot chat tool block. The leading status icon is owned by the
//  surrounding thinking timeline row, so this view only renders the tool title,
//  optional details, and the disclosure chevron.
//

import UIKit

final class ToolInvocationView: UIView {
    enum State: Equatable {
        case running
        case completed
        case failed(message: String)
    }

    private enum Metrics {
        static let titleLeading: CGFloat = 0.0
        static let chevronPointSize: CGFloat = 10.0
        static let headerVerticalPadding: CGFloat = 6.0
        static let bodyVerticalPadding: CGFloat = 6.0
        static let bodyLeading: CGFloat = 0.0
        static let chevronRotation: CGFloat = .pi / 2.0
        static let animationDuration: TimeInterval = 0.24
    }

    private let containerStack = UIStackView()
    private let headerButton = UIControl()
    private let titleLabel = ShimmerLabel()
    private let chevronImageView = UIImageView()
    private let bodyContainer = UIView()
    private let bodyTextView = UITextView()
    private var isExpanded = false

    let callID: String
    private(set) var state: State = .running
    private(set) var displayName: String

    init(callID: String, displayName: String, state: State = .running) {
        self.callID = callID
        self.displayName = displayName
        self.state = state
        super.init(frame: .zero)
        configure()
        applyState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(state: State) {
        guard state != self.state else {
            return
        }
        self.state = state
        applyState()
    }

    func setDetail(_ detail: String) {
        bodyTextView.text = detail
        updateBodyVisibilityIfNeeded()
    }

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.axis = .vertical
        containerStack.alignment = .fill
        containerStack.spacing = 0.0
        addSubview(containerStack)

        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.addTarget(self, action: #selector(handleHeaderTap), for: .touchUpInside)
        headerButton.isAccessibilityElement = true
        containerStack.addArrangedSubview(headerButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.baseColor = .secondaryLabel
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerButton.addSubview(titleLabel)

        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.contentMode = .center
        chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Metrics.chevronPointSize,
            weight: .semibold
        )
        chevronImageView.image = UIImage(systemName: "chevron.right")
        chevronImageView.tintColor = .tertiaryLabel
        headerButton.addSubview(chevronImageView)

        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.clipsToBounds = true
        bodyContainer.alpha = 0.0
        bodyContainer.isHidden = true
        containerStack.addArrangedSubview(bodyContainer)

        bodyTextView.translatesAutoresizingMaskIntoConstraints = false
        bodyTextView.backgroundColor = .clear
        bodyTextView.isEditable = false
        bodyTextView.isScrollEnabled = false
        bodyTextView.textContainerInset = .zero
        bodyTextView.textContainer.lineFragmentPadding = 0.0
        bodyTextView.font = .preferredFont(forTextStyle: .footnote)
        bodyTextView.adjustsFontForContentSizeCategory = true
        bodyTextView.textColor = .secondaryLabel
        bodyContainer.addSubview(bodyTextView)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: headerButton.leadingAnchor, constant: Metrics.titleLeading),
            titleLabel.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: headerButton.topAnchor, constant: Metrics.headerVerticalPadding),
            titleLabel.bottomAnchor.constraint(equalTo: headerButton.bottomAnchor, constant: -Metrics.headerVerticalPadding),

            chevronImageView.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8.0),
            chevronImageView.trailingAnchor.constraint(equalTo: headerButton.trailingAnchor),
            chevronImageView.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 14.0),
            chevronImageView.heightAnchor.constraint(equalToConstant: 14.0),

            bodyTextView.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: Metrics.bodyVerticalPadding),
            bodyTextView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: Metrics.bodyLeading),
            bodyTextView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyTextView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -Metrics.bodyVerticalPadding)
        ])
    }

    @objc private func handleHeaderTap() {
        guard hasBody else {
            return
        }
        setExpanded(!isExpanded, animated: true)
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else {
            return
        }
        isExpanded = expanded
        if expanded {
            bodyContainer.isHidden = false
            bodyContainer.alpha = 0.0
            superview?.layoutIfNeeded()
        }

        let updates = {
            self.bodyContainer.alpha = expanded ? 1.0 : 0.0
            self.chevronImageView.transform = expanded
                ? CGAffineTransform(rotationAngle: Metrics.chevronRotation)
                : .identity
            self.layoutIfNeeded()
            self.superview?.layoutIfNeeded()
        }

        let completion = {
            self.bodyContainer.isHidden = !expanded
            self.bodyContainer.alpha = expanded ? 1.0 : 0.0
            self.updateAccessibility()
            self.invalidateIntrinsicContentSize()
            self.superview?.setNeedsLayout()
        }

        guard animated, window != nil, MotionPreferences.allowsNonessentialMotion else {
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

    private func applyState() {
        switch state {
        case .running:
            titleLabel.text = String(localized: .assistantToolUsingFormat(displayName))
            titleLabel.baseColor = .secondaryLabel
            titleLabel.isShimmering = true
            chevronImageView.alpha = bodyTextView.text?.isEmpty == false ? 1.0 : 0.0
        case .completed:
            titleLabel.text = displayName
            titleLabel.baseColor = .label
            titleLabel.isShimmering = false
            chevronImageView.alpha = bodyTextView.text?.isEmpty == false ? 1.0 : 0.0
        case let .failed(message):
            titleLabel.text = String(localized: .assistantToolFailedFormat(displayName))
            titleLabel.baseColor = .systemRed
            titleLabel.isShimmering = false
            if (bodyTextView.text ?? "").isEmpty {
                bodyTextView.text = message
            }
            chevronImageView.alpha = 1.0
        }
        updateBodyVisibilityIfNeeded()
    }

    private func updateBodyVisibilityIfNeeded() {
        if !hasBody && isExpanded {
            setExpanded(false, animated: false)
        }
        chevronImageView.alpha = hasBody ? 1.0 : 0.0
        if !hasBody {
            bodyContainer.isHidden = true
            bodyContainer.alpha = 0.0
        }
        updateAccessibility()
    }

    private var hasBody: Bool {
        !(bodyTextView.text ?? "").isEmpty
    }

    private func updateAccessibility() {
        headerButton.accessibilityLabel = titleLabel.text
        headerButton.accessibilityValue = hasBody
            ? (isExpanded ? String(localized: .generalExpanded) : String(localized: .generalCollapsed))
            : nil
        headerButton.accessibilityHint = hasBody ? String(localized: .assistantToolShowsDetails) : nil
        headerButton.accessibilityTraits = hasBody ? .button : .staticText
    }
}
