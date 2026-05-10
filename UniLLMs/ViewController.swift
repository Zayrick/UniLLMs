//
//  ViewController.swift
//  UniLLMs
//
//  Created by Zayrick on 2026/5/9.
//

import UIKit

private struct LLMModelSelection: Equatable {
    var providerID: UUID
    var providerName: String
    var modelID: String
    var modelName: String

    var displayName: String {
        modelName.isEmpty ? modelID : modelName
    }
}

class ViewController: UIViewController {
    private enum HeaderLayout {
        static let defaultModuleSelectionTitle = "Select Model"
        static let buttonSize: CGFloat = 44.0
        static let horizontalInset: CGFloat = 16.0
        static let itemSpacing: CGFloat = 8.0
        static let topSpacing: CGFloat = 10.0
        static let iconPointSize: CGFloat = 18.0
        static let modulePillHorizontalInset: CGFloat = 16.0
        static let moduleSelectionAnimationDuration: TimeInterval = 0.32
        static let moduleSelectionTextAnimationDuration: TimeInterval = 0.18
        static let moduleSelectionAnimationDampingRatio: CGFloat = 0.84
    }

    private enum ComposerLayout {
        static let keyboardHorizontalInset: CGFloat = 14.0
        static let keyboardBottomSpacing: CGFloat = 8.0
    }

    private enum MessagesLayout {
        static let horizontalInset: CGFloat = 16.0
        static let topSpacing: CGFloat = 16.0
        static let bottomSpacing: CGFloat = 12.0
        static let verticalInset: CGFloat = 8.0
        static let itemSpacing: CGFloat = 8.0
        static let maximumBubbleWidthRatio: CGFloat = 0.82
        static let sendAnimationDuration: TimeInterval = 0.46
        static let sendAnimationDampingRatio: CGFloat = 0.88
        static let existingMessageShiftVisibilityMargin: CGFloat = 80.0
    }

    private enum SideMenuLayout {
        static let revealRatio: CGFloat = 0.8
        static let pageOpacity: CGFloat = 0.72
        static let animationDuration: TimeInterval = 0.44
        static let animationDampingRatio: CGFloat = 0.86
        static let shadowOpacity: Float = 0.18
        static let shadowRadius: CGFloat = 28.0
        static let shadowOffset = CGSize(width: -10.0, height: 0.0)
    }

    private let rootBackgroundView = AppGradientBackgroundView()
    private let sideMenuView = SideMenuView()
    private let sideMenuDismissControl = UIControl()
    private let mainPageContainerView = UIView()
    private let mainPageView = UIView()
    private let backgroundView = AppGradientBackgroundView()
    private let headerGlassContainerView = UIVisualEffectView(effect: ViewController.makeHeaderContainerEffect())
    private let headerStackView = UIStackView()
    private let leftHeaderGlassView = UIVisualEffectView(effect: ViewController.makeHeaderGlassEffect())
    private let moduleSelectionPillGlassView = UIVisualEffectView(effect: ViewController.makeHeaderGlassEffect())
    private let leftHeaderButton = ViewController.makeHeaderContentButton(
        systemName: "list.bullet",
        accessibilityLabel: "Menu"
    )
    private let moduleSelectionPillButton = ViewController.makeHeaderPill(
        title: HeaderLayout.defaultModuleSelectionTitle
    )
    private let rightHeaderButton = ViewController.makeHeaderButton(
        systemName: "app.dashed",
        accessibilityLabel: "Layout"
    )
    private let messagesScrollView = UIScrollView()
    private let messagesContentView = UIView()
    private let messagesStackView = UIStackView()
    private let composerView = GlassComposerBarView()
    private var composerLeadingConstraint: NSLayoutConstraint!
    private var composerTrailingConstraint: NSLayoutConstraint!
    private var composerKeyboardBottomConstraint: NSLayoutConstraint!
    private var composerRestingBottomConstraint: NSLayoutConstraint!
    private var keyboardObservation: NotificationCenter.ObservationToken?
    private var isKeyboardVisible = false
    private var isSideMenuOpen = false
    private var selectedModelSelection: LLMModelSelection?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .appBackgroundMiddle

        configureRootBackground()
        configureSideMenu()
        configureMainPage()
        configureHeaderButtons()
        configureComposerView()
        configureMessagesView()
        configureSideMenuDismissControl()
        installKeyboardObserver()
    }

    deinit {
        if let keyboardObservation {
            NotificationCenter.default.removeObserver(keyboardObservation)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        updateComposerLayout(animated: false)
        updateMessagesContentInsets()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateSideMenuLayout()
        updateMessagesContentInsets()
        updateMainPageShadowPath()
    }

    private func configureRootBackground() {
        rootBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootBackgroundView)

        NSLayoutConstraint.activate([
            rootBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            rootBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureSideMenu() {
        sideMenuView.translatesAutoresizingMaskIntoConstraints = false
        sideMenuView.alpha = 0.0
        sideMenuView.isUserInteractionEnabled = false
        sideMenuView.addSettingsTarget(self, action: #selector(presentSettings))
        view.addSubview(sideMenuView)

        NSLayoutConstraint.activate([
            sideMenuView.topAnchor.constraint(equalTo: view.topAnchor),
            sideMenuView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sideMenuView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sideMenuView.widthAnchor.constraint(
                equalTo: view.widthAnchor,
                multiplier: SideMenuLayout.revealRatio
            )
        ])
    }

    private func configureMainPage() {
        mainPageContainerView.translatesAutoresizingMaskIntoConstraints = false
        mainPageContainerView.clipsToBounds = false
        mainPageContainerView.layer.shadowColor = UIColor.black.cgColor
        mainPageContainerView.layer.shadowOpacity = 0.0
        mainPageContainerView.layer.shadowRadius = SideMenuLayout.shadowRadius
        mainPageContainerView.layer.shadowOffset = SideMenuLayout.shadowOffset
        view.addSubview(mainPageContainerView)

        mainPageView.translatesAutoresizingMaskIntoConstraints = false
        mainPageView.backgroundColor = .appBackgroundMiddle
        mainPageView.layer.cornerCurve = .continuous
        mainPageContainerView.addSubview(mainPageView)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        mainPageView.addSubview(backgroundView)

        NSLayoutConstraint.activate([
            mainPageContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            mainPageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainPageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainPageContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            mainPageView.topAnchor.constraint(equalTo: mainPageContainerView.topAnchor),
            mainPageView.leadingAnchor.constraint(equalTo: mainPageContainerView.leadingAnchor),
            mainPageView.trailingAnchor.constraint(equalTo: mainPageContainerView.trailingAnchor),
            mainPageView.bottomAnchor.constraint(equalTo: mainPageContainerView.bottomAnchor),

            backgroundView.topAnchor.constraint(equalTo: mainPageView.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: mainPageView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: mainPageView.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: mainPageView.bottomAnchor)
        ])
    }

    private func configureHeaderButtons() {
        headerGlassContainerView.translatesAutoresizingMaskIntoConstraints = false
        headerGlassContainerView.backgroundColor = .clear
        mainPageView.addSubview(headerGlassContainerView)

        headerStackView.axis = .horizontal
        headerStackView.alignment = .center
        headerStackView.spacing = HeaderLayout.itemSpacing
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerGlassContainerView.contentView.addSubview(headerStackView)

        headerStackView.addArrangedSubview(leftHeaderGlassView)
        headerStackView.addArrangedSubview(moduleSelectionPillGlassView)

        leftHeaderGlassView.translatesAutoresizingMaskIntoConstraints = false
        leftHeaderGlassView.cornerConfiguration = .capsule()
        leftHeaderGlassView.setContentHuggingPriority(.required, for: .horizontal)
        leftHeaderGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)

        moduleSelectionPillGlassView.translatesAutoresizingMaskIntoConstraints = false
        moduleSelectionPillGlassView.cornerConfiguration = .capsule()
        moduleSelectionPillGlassView.setContentHuggingPriority(.required, for: .horizontal)
        moduleSelectionPillGlassView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        [leftHeaderButton, moduleSelectionPillButton, rightHeaderButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        leftHeaderGlassView.contentView.addSubview(leftHeaderButton)
        moduleSelectionPillGlassView.contentView.addSubview(moduleSelectionPillButton)
        mainPageView.addSubview(rightHeaderButton)

        leftHeaderButton.addTarget(self, action: #selector(toggleSideMenu), for: .touchUpInside)
        moduleSelectionPillButton.addTarget(self, action: #selector(presentModelSelection), for: .touchUpInside)

        NSLayoutConstraint.activate([
            headerGlassContainerView.topAnchor.constraint(
                equalTo: mainPageView.safeAreaLayoutGuide.topAnchor,
                constant: HeaderLayout.topSpacing
            ),
            headerGlassContainerView.heightAnchor.constraint(equalToConstant: HeaderLayout.buttonSize),
            headerGlassContainerView.leadingAnchor.constraint(
                equalTo: mainPageView.safeAreaLayoutGuide.leadingAnchor,
                constant: HeaderLayout.horizontalInset
            ),
            headerGlassContainerView.trailingAnchor.constraint(
                lessThanOrEqualTo: rightHeaderButton.leadingAnchor,
                constant: -HeaderLayout.itemSpacing
            ),

            headerStackView.topAnchor.constraint(equalTo: headerGlassContainerView.contentView.topAnchor),
            headerStackView.leadingAnchor.constraint(equalTo: headerGlassContainerView.contentView.leadingAnchor),
            headerStackView.trailingAnchor.constraint(equalTo: headerGlassContainerView.contentView.trailingAnchor),
            headerStackView.bottomAnchor.constraint(equalTo: headerGlassContainerView.contentView.bottomAnchor),

            leftHeaderGlassView.widthAnchor.constraint(equalToConstant: HeaderLayout.buttonSize),
            leftHeaderGlassView.heightAnchor.constraint(equalToConstant: HeaderLayout.buttonSize),
            leftHeaderButton.topAnchor.constraint(equalTo: leftHeaderGlassView.contentView.topAnchor),
            leftHeaderButton.leadingAnchor.constraint(equalTo: leftHeaderGlassView.contentView.leadingAnchor),
            leftHeaderButton.trailingAnchor.constraint(equalTo: leftHeaderGlassView.contentView.trailingAnchor),
            leftHeaderButton.bottomAnchor.constraint(equalTo: leftHeaderGlassView.contentView.bottomAnchor),

            moduleSelectionPillButton.topAnchor.constraint(
                equalTo: moduleSelectionPillGlassView.contentView.topAnchor
            ),
            moduleSelectionPillButton.leadingAnchor.constraint(
                equalTo: moduleSelectionPillGlassView.contentView.leadingAnchor
            ),
            moduleSelectionPillButton.trailingAnchor.constraint(
                equalTo: moduleSelectionPillGlassView.contentView.trailingAnchor
            ),
            moduleSelectionPillButton.bottomAnchor.constraint(
                equalTo: moduleSelectionPillGlassView.contentView.bottomAnchor
            ),
            moduleSelectionPillGlassView.heightAnchor.constraint(equalToConstant: HeaderLayout.buttonSize),

            rightHeaderButton.topAnchor.constraint(
                equalTo: headerGlassContainerView.topAnchor
            ),
            rightHeaderButton.trailingAnchor.constraint(
                equalTo: mainPageView.safeAreaLayoutGuide.trailingAnchor,
                constant: -HeaderLayout.horizontalInset
            ),
            rightHeaderButton.widthAnchor.constraint(equalToConstant: HeaderLayout.buttonSize),
            rightHeaderButton.heightAnchor.constraint(equalToConstant: HeaderLayout.buttonSize)
        ])
    }

    private func configureComposerView() {
        composerView.translatesAutoresizingMaskIntoConstraints = false
        composerView.onSend = { [weak self] transition in
            self?.appendSentMessage(using: transition)
        }
        composerView.onLayoutChange = { [weak self] in
            self?.updateMessagesContentInsets()
        }
        mainPageView.addSubview(composerView)

        composerLeadingConstraint = composerView.leadingAnchor.constraint(
            equalTo: mainPageView.safeAreaLayoutGuide.leadingAnchor,
            constant: composerHorizontalInset
        )
        composerTrailingConstraint = composerView.trailingAnchor.constraint(
            equalTo: mainPageView.safeAreaLayoutGuide.trailingAnchor,
            constant: -composerHorizontalInset
        )
        composerKeyboardBottomConstraint = composerView.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor,
            constant: composerBottomSpacing
        )
        composerRestingBottomConstraint = composerView.bottomAnchor.constraint(
            equalTo: mainPageView.safeAreaLayoutGuide.bottomAnchor
        )

        NSLayoutConstraint.activate([
            composerLeadingConstraint,
            composerTrailingConstraint
        ])
        updateComposerBottomConstraint()
    }

    private func configureMessagesView() {
        messagesScrollView.translatesAutoresizingMaskIntoConstraints = false
        messagesScrollView.backgroundColor = .clear
        messagesScrollView.clipsToBounds = false
        messagesScrollView.showsVerticalScrollIndicator = false
        messagesScrollView.showsHorizontalScrollIndicator = false
        messagesScrollView.alwaysBounceVertical = true
        messagesScrollView.keyboardDismissMode = .interactive
        messagesScrollView.contentInsetAdjustmentBehavior = .never
        messagesScrollView.topEdgeEffect.style = .soft
        messagesScrollView.bottomEdgeEffect.style = .soft
        mainPageView.insertSubview(messagesScrollView, aboveSubview: backgroundView)

        messagesContentView.translatesAutoresizingMaskIntoConstraints = false
        messagesScrollView.addSubview(messagesContentView)

        messagesStackView.axis = .vertical
        messagesStackView.alignment = .trailing
        messagesStackView.distribution = .fill
        messagesStackView.spacing = MessagesLayout.itemSpacing
        messagesStackView.setContentHuggingPriority(.required, for: .vertical)
        messagesStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        messagesStackView.translatesAutoresizingMaskIntoConstraints = false
        messagesContentView.addSubview(messagesStackView)

        NSLayoutConstraint.activate([
            messagesScrollView.topAnchor.constraint(
                equalTo: mainPageView.topAnchor
            ),
            messagesScrollView.leadingAnchor.constraint(
                equalTo: mainPageView.safeAreaLayoutGuide.leadingAnchor,
                constant: MessagesLayout.horizontalInset
            ),
            messagesScrollView.trailingAnchor.constraint(
                equalTo: mainPageView.safeAreaLayoutGuide.trailingAnchor,
                constant: -MessagesLayout.horizontalInset
            ),
            messagesScrollView.bottomAnchor.constraint(
                equalTo: mainPageView.bottomAnchor
            ),

            messagesContentView.topAnchor.constraint(equalTo: messagesScrollView.contentLayoutGuide.topAnchor),
            messagesContentView.leadingAnchor.constraint(equalTo: messagesScrollView.contentLayoutGuide.leadingAnchor),
            messagesContentView.trailingAnchor.constraint(equalTo: messagesScrollView.contentLayoutGuide.trailingAnchor),
            messagesContentView.bottomAnchor.constraint(equalTo: messagesScrollView.contentLayoutGuide.bottomAnchor),
            messagesContentView.widthAnchor.constraint(equalTo: messagesScrollView.frameLayoutGuide.widthAnchor),
            messagesContentView.heightAnchor.constraint(
                greaterThanOrEqualTo: messagesScrollView.frameLayoutGuide.heightAnchor
            ),

            messagesStackView.leadingAnchor.constraint(equalTo: messagesContentView.leadingAnchor),
            messagesStackView.trailingAnchor.constraint(equalTo: messagesContentView.trailingAnchor),
            messagesStackView.bottomAnchor.constraint(
                equalTo: messagesContentView.bottomAnchor,
                constant: -MessagesLayout.verticalInset
            ),
            messagesStackView.topAnchor.constraint(
                greaterThanOrEqualTo: messagesContentView.topAnchor,
                constant: MessagesLayout.verticalInset
            )
        ])

        mainPageView.bringSubviewToFront(headerGlassContainerView)
        mainPageView.bringSubviewToFront(rightHeaderButton)
        mainPageView.bringSubviewToFront(composerView)
        addScrollEdgeInteraction(to: headerGlassContainerView, edge: .top)
        addScrollEdgeInteraction(to: rightHeaderButton, edge: .top)
        addScrollEdgeInteraction(to: composerView, edge: .bottom)
    }

    private func addScrollEdgeInteraction(to view: UIView, edge: UIRectEdge) {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.scrollView = messagesScrollView
        interaction.edge = edge
        view.addInteraction(interaction)
    }

    private func updateMessagesContentInsets() {
        guard messagesScrollView.superview != nil else {
            return
        }

        let headerBottom = max(headerGlassContainerView.frame.maxY, rightHeaderButton.frame.maxY)
        let topInset = headerBottom + MessagesLayout.topSpacing
        let bottomInset = max(
            0.0,
            mainPageView.bounds.maxY - composerView.frame.minY + MessagesLayout.bottomSpacing
        )
        let contentInsets = UIEdgeInsets(top: topInset, left: 0.0, bottom: bottomInset, right: 0.0)

        guard messagesScrollView.contentInset != contentInsets else {
            return
        }

        messagesScrollView.contentInset = contentInsets
        messagesScrollView.scrollIndicatorInsets = contentInsets
    }

    private func configureSideMenuDismissControl() {
        sideMenuDismissControl.translatesAutoresizingMaskIntoConstraints = false
        sideMenuDismissControl.backgroundColor = .clear
        sideMenuDismissControl.alpha = 0.0
        sideMenuDismissControl.isHidden = true
        sideMenuDismissControl.addTarget(self, action: #selector(closeSideMenu), for: .touchUpInside)
        view.addSubview(sideMenuDismissControl)

        NSLayoutConstraint.activate([
            sideMenuDismissControl.topAnchor.constraint(equalTo: view.topAnchor),
            sideMenuDismissControl.leadingAnchor.constraint(equalTo: sideMenuView.trailingAnchor),
            sideMenuDismissControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sideMenuDismissControl.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private var composerHorizontalInset: CGFloat {
        isKeyboardVisible ? ComposerLayout.keyboardHorizontalInset : view.safeAreaInsets.bottom
    }

    private var composerBottomSpacing: CGFloat {
        isKeyboardVisible ? -ComposerLayout.keyboardBottomSpacing : 0.0
    }

    private func installKeyboardObserver() {
        keyboardObservation = NotificationCenter.default.addObserver(
            of: UIScreen.self,
            for: .keyboardWillChangeFrame
        ) { [weak self] message in
            guard let self else {
                return
            }

            self.isKeyboardVisible = message.endFrame.minY < message.screen.bounds.maxY
            let options = UIView.AnimationOptions(rawValue: UInt(message.animationCurve.rawValue << 16))
                .union(.beginFromCurrentState)
            self.updateComposerLayout(
                animated: true,
                duration: message.animationDuration,
                options: options
            )
        }
    }

    private func updateComposerLayout(
        animated: Bool,
        duration: TimeInterval = 0.0,
        options: UIView.AnimationOptions = [.beginFromCurrentState]
    ) {
        guard composerLeadingConstraint != nil,
              composerTrailingConstraint != nil,
              composerKeyboardBottomConstraint != nil,
              composerRestingBottomConstraint != nil else {
            return
        }

        let inset = composerHorizontalInset
        composerLeadingConstraint.constant = inset
        composerTrailingConstraint.constant = -inset
        composerKeyboardBottomConstraint.constant = composerBottomSpacing
        updateComposerBottomConstraint()

        let layoutChanges = {
            self.view.layoutIfNeeded()
            self.updateMessagesContentInsets()
        }

        if animated {
            UIView.animate(
                withDuration: duration,
                delay: 0.0,
                options: options,
                animations: layoutChanges
            )
        } else {
            layoutChanges()
        }
    }

    @objc private func toggleSideMenu() {
        setSideMenuOpen(!isSideMenuOpen, animated: true)
    }

    @objc private func closeSideMenu() {
        setSideMenuOpen(false, animated: true)
    }

    @objc private func presentModelSelection() {
        guard presentedViewController == nil else {
            return
        }

        view.endEditing(true)

        let modelSelectionViewController = ModelSelectionViewController(
            selectedModelSelection: selectedModelSelection
        ) { [weak self] selection in
            self?.selectedModelSelection = selection
            self?.updateModuleSelectionTitle(animated: true)
        }
        let navigationController = UINavigationController(rootViewController: modelSelectionViewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }

    @objc private func presentSettings() {
        guard presentedViewController == nil else {
            return
        }

        view.endEditing(true)

        let settingsViewController = SettingsViewController(style: .insetGrouped)
        let navigationController = UINavigationController(rootViewController: settingsViewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }

    private func setSideMenuOpen(_ isOpen: Bool, animated: Bool) {
        guard isSideMenuOpen != isOpen else {
            return
        }

        isSideMenuOpen = isOpen
        if isOpen {
            view.endEditing(true)
            sideMenuView.alpha = 0.0
            sideMenuView.isHidden = false
            sideMenuView.isUserInteractionEnabled = true
            sideMenuDismissControl.isHidden = false
        } else {
            sideMenuView.resignSearchFocus()
            view.endEditing(true)
        }

        let animations = {
            self.updateSideMenuLayout()
            self.updateComposerLayout(animated: false)
            self.view.layoutIfNeeded()
        }
        let animatorCompletion: (UIViewAnimatingPosition) -> Void = { _ in
            guard !self.isSideMenuOpen else {
                return
            }

            self.sideMenuView.isUserInteractionEnabled = false
            self.sideMenuDismissControl.isHidden = true
        }

        if animated {
            let animator = UIViewPropertyAnimator(
                duration: SideMenuLayout.animationDuration,
                dampingRatio: SideMenuLayout.animationDampingRatio,
                animations: animations
            )
            animator.addCompletion(animatorCompletion)
            animator.startAnimation()
        } else {
            animations()
            animatorCompletion(.end)
        }
    }

    private func updateSideMenuLayout() {
        let revealWidth = view.bounds.width * SideMenuLayout.revealRatio
        let pageCornerRadius = currentPageCornerRadius

        mainPageContainerView.transform = isSideMenuOpen
            ? CGAffineTransform(translationX: revealWidth, y: 0.0)
            : .identity
        mainPageContainerView.layer.shadowOpacity = isSideMenuOpen
            ? SideMenuLayout.shadowOpacity
            : 0.0
        mainPageView.alpha = isSideMenuOpen ? SideMenuLayout.pageOpacity : 1.0
        mainPageView.layer.cornerRadius = isSideMenuOpen ? pageCornerRadius : 0.0
        mainPageView.layer.masksToBounds = isSideMenuOpen
        sideMenuView.alpha = isSideMenuOpen ? 1.0 : 0.0
        sideMenuDismissControl.alpha = isSideMenuOpen ? 1.0 : 0.0
        updateMainPageShadowPath(cornerRadius: isSideMenuOpen ? pageCornerRadius : 0.0)
    }

    private func updateComposerBottomConstraint() {
        let shouldTrackKeyboard = !isSideMenuOpen
        composerKeyboardBottomConstraint.isActive = shouldTrackKeyboard
        composerRestingBottomConstraint.isActive = !shouldTrackKeyboard
    }

    private func appendSentMessage(using transition: GlassComposerBarView.SendTransition) {
        mainPageView.layoutIfNeeded()
        let existingMessageFrames = visibleMessageFrames()

        let bubbleView = SentMessageBubbleView(text: transition.text)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.alpha = 0.0
        bubbleView.setContentHuggingPriority(.required, for: .vertical)
        bubbleView.setContentCompressionResistancePriority(.required, for: .vertical)

        messagesStackView.addArrangedSubview(bubbleView)
        bubbleView.widthAnchor.constraint(
            lessThanOrEqualTo: messagesScrollView.frameLayoutGuide.widthAnchor,
            multiplier: MessagesLayout.maximumBubbleWidthRatio
        ).isActive = true

        mainPageView.layoutIfNeeded()
        scrollMessagesToBottom(animated: false)
        mainPageView.layoutIfNeeded()

        animateExistingMessages(from: existingMessageFrames)
        animateSentMessage(bubbleView, from: transition)
    }

    private func visibleMessageFrames() -> [(view: UIView, frame: CGRect)] {
        let visibleFrame = messagesScrollView.convert(
            messagesScrollView.bounds.insetBy(
                dx: 0.0,
                dy: -MessagesLayout.existingMessageShiftVisibilityMargin
            ),
            to: mainPageView
        )

        return messagesStackView.arrangedSubviews.compactMap { messageView in
            let frame = messageView.convert(messageView.bounds, to: mainPageView)
            guard frame.intersects(visibleFrame) else {
                return nil
            }

            return (messageView, frame)
        }
    }

    private func animateExistingMessages(from previousFrames: [(view: UIView, frame: CGRect)]) {
        guard view.window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            return
        }

        let shiftedViews = previousFrames.compactMap { snapshot -> UIView? in
            guard snapshot.view.superview != nil else {
                return nil
            }

            let currentFrame = snapshot.view.convert(snapshot.view.bounds, to: mainPageView)
            let deltaY = snapshot.frame.minY - currentFrame.minY
            guard abs(deltaY) > 0.5 else {
                return nil
            }

            snapshot.view.transform = CGAffineTransform(translationX: 0.0, y: deltaY)
            return snapshot.view
        }

        guard !shiftedViews.isEmpty else {
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: MessagesLayout.sendAnimationDuration,
            dampingRatio: MessagesLayout.sendAnimationDampingRatio
        ) {
            shiftedViews.forEach { messageView in
                messageView.transform = .identity
            }
        }
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.addCompletion { _ in
            shiftedViews.forEach { messageView in
                messageView.transform = .identity
            }
        }
        animator.startAnimation()
    }

    private func scrollMessagesToBottom(animated: Bool) {
        messagesScrollView.layoutIfNeeded()
        updateMessagesContentInsets()

        let adjustedInsets = messagesScrollView.adjustedContentInset
        let targetOffsetY = max(
            -adjustedInsets.top,
            messagesScrollView.contentSize.height - messagesScrollView.bounds.height + adjustedInsets.bottom
        )
        messagesScrollView.setContentOffset(CGPoint(x: 0.0, y: targetOffsetY), animated: animated)
    }

    private func animateSentMessage(
        _ bubbleView: SentMessageBubbleView,
        from transition: GlassComposerBarView.SendTransition
    ) {
        guard view.window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            bubbleView.alpha = 1.0
            return
        }

        let sourceBackgroundFrame = mainPageView.convert(transition.backgroundGlobalFrame, from: nil)
        let targetBubbleFrame = bubbleView.convert(bubbleView.bounds, to: mainPageView)

        let animatedBubbleView = SentMessageBubbleView(text: transition.text)
        animatedBubbleView.frame = sourceBackgroundFrame
        animatedBubbleView.isUserInteractionEnabled = false
        animatedBubbleView.layoutIfNeeded()
        mainPageView.addSubview(animatedBubbleView)

        let animator = UIViewPropertyAnimator(
            duration: MessagesLayout.sendAnimationDuration,
            dampingRatio: MessagesLayout.sendAnimationDampingRatio
        ) {
            animatedBubbleView.frame = targetBubbleFrame
            animatedBubbleView.layoutIfNeeded()
        }
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.addCompletion { _ in
            UIView.performWithoutAnimation {
                animatedBubbleView.removeFromSuperview()
                bubbleView.alpha = 1.0
            }
        }
        animator.startAnimation()
    }

    private func updateMainPageShadowPath(cornerRadius: CGFloat? = nil) {
        let radius = cornerRadius ?? mainPageView.layer.cornerRadius
        mainPageContainerView.layer.shadowPath = UIBezierPath(
            roundedRect: mainPageContainerView.bounds,
            cornerRadius: radius
        ).cgPath
    }

    private var currentPageCornerRadius: CGFloat {
        view.window?.windowScene?.screen.displayCornerRadius ?? 0.0
    }

    private func updateModuleSelectionTitle(animated: Bool) {
        let title = selectedModelSelection?.displayName ?? HeaderLayout.defaultModuleSelectionTitle

        guard animated,
              view.window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            setModuleSelectionTitle(title)
            mainPageView.layoutIfNeeded()
            return
        }

        mainPageView.layoutIfNeeded()

        UIView.transition(
            with: moduleSelectionPillButton,
            duration: HeaderLayout.moduleSelectionTextAnimationDuration,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction, .allowAnimatedContent]
        ) {
            self.setModuleSelectionTitle(title)
        }

        let animator = UIViewPropertyAnimator(
            duration: HeaderLayout.moduleSelectionAnimationDuration,
            dampingRatio: HeaderLayout.moduleSelectionAnimationDampingRatio
        ) {
            self.mainPageView.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    private func setModuleSelectionTitle(_ title: String) {
        var configuration = moduleSelectionPillButton.configuration
        configuration?.title = title
        moduleSelectionPillButton.configuration = configuration
        moduleSelectionPillButton.accessibilityLabel = title
        moduleSelectionPillButton.invalidateIntrinsicContentSize()
        moduleSelectionPillGlassView.invalidateIntrinsicContentSize()
        headerStackView.invalidateIntrinsicContentSize()
        headerGlassContainerView.invalidateIntrinsicContentSize()
    }

    private static func makeHeaderButton(systemName: String, accessibilityLabel: String) -> UIButton {
        var configuration = UIButton.Configuration.clearGlass()
        configuration.image = UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: HeaderLayout.iconPointSize,
                weight: .semibold
            )
        )
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    private static func makeHeaderPill(title: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0.0,
            leading: HeaderLayout.modulePillHorizontalInset,
            bottom: 0.0,
            trailing: HeaderLayout.modulePillHorizontalInset
        )

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = title
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    private static func makeHeaderContentButton(
        systemName: String,
        accessibilityLabel: String
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: HeaderLayout.iconPointSize,
                weight: .semibold
            )
        )
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    private static func makeHeaderContainerEffect() -> UIGlassContainerEffect {
        let effect = UIGlassContainerEffect()
        effect.spacing = HeaderLayout.itemSpacing
        return effect
    }

    private static func makeHeaderGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }

}

private final class SideMenuView: UIView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 16.0
        static let titleTopSpacing: CGFloat = 18.0
        static let bottomSpacing: CGFloat = 10.0
        static let controlHeight: CGFloat = 48.0
        static let controlSpacing: CGFloat = 10.0
        static let searchHorizontalInset: CGFloat = 16.0
        static let searchIconSize: CGFloat = 17.0
        static let settingsButtonSize: CGFloat = 48.0
        static let settingsIconSize: CGFloat = 20.0
    }

    private let titleLabel = UILabel()
    private let bottomGlassContainerView = UIVisualEffectView(effect: SideMenuView.makeContainerEffect())
    private let bottomStackView = UIStackView()
    private let searchGlassView = UIVisualEffectView(effect: SideMenuView.makeGlassEffect())
    private let searchRowView = UIStackView()
    private let searchIconView = UIImageView()
    private let searchTextField = UITextField()
    private let settingsGlassView = UIVisualEffectView(effect: SideMenuView.makeGlassEffect())
    private let settingsButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func resignSearchFocus() {
        searchTextField.resignFirstResponder()
    }

    func addSettingsTarget(_ target: Any?, action: Selector) {
        settingsButton.addTarget(target, action: action, for: .touchUpInside)
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear

        configureTitle()
        configureBottomBar()
        configureSearchField()
        configureSettingsButton()
    }

    private func configureTitle() {
        titleLabel.text = "UniLLMs"
        titleLabel.font = .systemFont(ofSize: 28.0, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: Metrics.titleTopSpacing
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            )
        ])
    }

    private func configureBottomBar() {
        bottomGlassContainerView.translatesAutoresizingMaskIntoConstraints = false
        bottomGlassContainerView.backgroundColor = .clear
        addSubview(bottomGlassContainerView)

        bottomStackView.axis = .horizontal
        bottomStackView.alignment = .bottom
        bottomStackView.spacing = Metrics.controlSpacing
        bottomStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomGlassContainerView.contentView.addSubview(bottomStackView)

        bottomStackView.addArrangedSubview(searchGlassView)
        bottomStackView.addArrangedSubview(settingsGlassView)

        searchGlassView.translatesAutoresizingMaskIntoConstraints = false
        searchGlassView.cornerConfiguration = .corners(
            radius: .fixed(Double(Metrics.controlHeight * 0.5))
        )
        searchGlassView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchGlassView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        settingsGlassView.translatesAutoresizingMaskIntoConstraints = false
        settingsGlassView.cornerConfiguration = .capsule()
        settingsGlassView.setContentHuggingPriority(.required, for: .horizontal)
        settingsGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            bottomGlassContainerView.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            bottomGlassContainerView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            bottomGlassContainerView.bottomAnchor.constraint(
                equalTo: keyboardLayoutGuide.topAnchor,
                constant: -Metrics.bottomSpacing
            ),

            bottomStackView.topAnchor.constraint(equalTo: bottomGlassContainerView.contentView.topAnchor),
            bottomStackView.leadingAnchor.constraint(equalTo: bottomGlassContainerView.contentView.leadingAnchor),
            bottomStackView.trailingAnchor.constraint(equalTo: bottomGlassContainerView.contentView.trailingAnchor),
            bottomStackView.bottomAnchor.constraint(equalTo: bottomGlassContainerView.contentView.bottomAnchor),

            bottomGlassContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
            searchGlassView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
            settingsGlassView.widthAnchor.constraint(equalToConstant: Metrics.settingsButtonSize),
            settingsGlassView.heightAnchor.constraint(equalToConstant: Metrics.settingsButtonSize)
        ])
    }

    private func configureSearchField() {
        searchRowView.axis = .horizontal
        searchRowView.alignment = .center
        searchRowView.spacing = 8.0
        searchRowView.translatesAutoresizingMaskIntoConstraints = false
        searchGlassView.contentView.addSubview(searchRowView)

        searchIconView.image = UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Metrics.searchIconSize,
                weight: .medium
            )
        )
        searchIconView.tintColor = .secondaryLabel
        searchIconView.contentMode = .scaleAspectFit
        searchIconView.setContentHuggingPriority(.required, for: .horizontal)

        searchTextField.placeholder = "Search"
        searchTextField.borderStyle = .none
        searchTextField.backgroundColor = .clear
        searchTextField.clearButtonMode = .whileEditing
        searchTextField.returnKeyType = .search
        searchTextField.textColor = .label
        searchTextField.tintColor = .systemBlue
        searchTextField.font = .preferredFont(forTextStyle: .body)
        searchTextField.adjustsFontForContentSizeCategory = true
        searchTextField.accessibilityLabel = "Search"

        searchRowView.addArrangedSubview(searchIconView)
        searchRowView.addArrangedSubview(searchTextField)

        NSLayoutConstraint.activate([
            searchRowView.leadingAnchor.constraint(
                equalTo: searchGlassView.contentView.leadingAnchor,
                constant: Metrics.searchHorizontalInset
            ),
            searchRowView.trailingAnchor.constraint(
                equalTo: searchGlassView.contentView.trailingAnchor,
                constant: -Metrics.searchHorizontalInset
            ),
            searchRowView.centerYAnchor.constraint(equalTo: searchGlassView.contentView.centerYAnchor),
            searchRowView.topAnchor.constraint(
                greaterThanOrEqualTo: searchGlassView.contentView.topAnchor,
                constant: 6.0
            ),
            searchRowView.bottomAnchor.constraint(
                lessThanOrEqualTo: searchGlassView.contentView.bottomAnchor,
                constant: -6.0
            )
        ])
    }

    private func configureSettingsButton() {
        settingsButton.tintColor = .label
        settingsButton.setImage(
            UIImage(
                systemName: "gearshape",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: Metrics.settingsIconSize,
                    weight: .regular
                )
            ),
            for: .normal
        )
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsGlassView.contentView.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: settingsGlassView.contentView.topAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: settingsGlassView.contentView.leadingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: settingsGlassView.contentView.trailingAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: settingsGlassView.contentView.bottomAnchor)
        ])
    }

    private static func makeContainerEffect() -> UIGlassContainerEffect {
        let effect = UIGlassContainerEffect()
        effect.spacing = Metrics.controlSpacing
        return effect
    }

    private static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }
}

private final class SettingsViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Setting"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "config"
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "LLMs Provider"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(LLMsProviderViewController(), animated: true)
    }
}

private final class ModelSelectionViewController: UITableViewController {
    private let store: LLMProviderStore
    private var providers: [LLMProviderRecord] = []
    private var selectedModelSelection: LLMModelSelection?
    private let onSelect: (LLMModelSelection) -> Void

    init(
        store: LLMProviderStore = .shared,
        selectedModelSelection: LLMModelSelection?,
        onSelect: @escaping (LLMModelSelection) -> Void
    ) {
        self.store = store
        self.selectedModelSelection = selectedModelSelection
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        store = .shared
        selectedModelSelection = nil
        onSelect = { _ in }
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Select Model"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        reloadProviders()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadProviders()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func reloadProviders() {
        providers = store.fetchProviders()
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        providers.isEmpty ? 1 : providers.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard !providers.isEmpty else {
            return 1
        }

        return max(providers[section].models.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !providers.isEmpty else {
            return "Providers"
        }

        return providerDisplayName(providers[section])
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        nil
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard !providers.isEmpty else {
            return unavailableCell(
                title: "No LLMs Provider",
                detail: "Add providers in Settings before selecting a model."
            )
        }

        let provider = providers[indexPath.section]
        guard !provider.models.isEmpty else {
            return unavailableCell(
                title: "No Models",
                detail: "Refresh the model list for this provider in Settings."
            )
        }

        let model = provider.models[indexPath.row]
        let modelTitle = model.name.isEmpty ? model.id : model.name
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = UIListContentConfiguration.subtitleCell()
        contentConfiguration.text = modelTitle
        contentConfiguration.secondaryText = model.name.isEmpty ? nil : model.id
        contentConfiguration.image = UIImage(systemName: "cpu")
        contentConfiguration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = isSelected(model: model, provider: provider) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard !providers.isEmpty else {
            return
        }

        let provider = providers[indexPath.section]
        guard !provider.models.isEmpty else {
            return
        }

        let model = provider.models[indexPath.row]
        let selection = LLMModelSelection(
            providerID: provider.id,
            providerName: providerDisplayName(provider),
            modelID: model.id,
            modelName: model.name
        )
        selectedModelSelection = selection
        onSelect(selection)
        dismiss(animated: true)
    }

    private func unavailableCell(title: String, detail: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = UIListContentConfiguration.subtitleCell()
        contentConfiguration.text = title
        contentConfiguration.secondaryText = detail
        contentConfiguration.image = UIImage(systemName: "exclamationmark.circle")
        contentConfiguration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.selectionStyle = .none
        return cell
    }

    private func isSelected(model: LLMProviderModel, provider: LLMProviderRecord) -> Bool {
        selectedModelSelection?.providerID == provider.id
            && selectedModelSelection?.modelID == model.id
    }

    private func providerDisplayName(_ provider: LLMProviderRecord) -> String {
        let trimmedName = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? LLMProviderRecord.openRouterDisplayName : trimmedName
    }
}

private final class LLMsProviderViewController: UITableViewController {
    private let store: LLMProviderStore
    private var providers: [LLMProviderRecord] = []

    init(store: LLMProviderStore = .shared) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        store = .shared
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "LLMs Provider"

        configureAddButton()
        reloadProviders()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadProviders()
    }

    private func configureAddButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(presentNewOpenRouterProvider)
        )
    }

    private func reloadProviders() {
        providers = store.fetchProviders()
        tableView.reloadData()
    }

    @objc private func presentNewOpenRouterProvider() {
        let provider = store.makeOpenRouterProviderDraft()
        navigationController?.pushViewController(
            ProviderConfigurationViewController(
                provider: provider,
                store: store,
                isNewProvider: true
            ),
            animated: true
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        providers.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Providers"
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let provider = providers[indexPath.row]

        var contentConfiguration = UIListContentConfiguration.subtitleCell()
        contentConfiguration.text = provider.name.isEmpty
            ? LLMProviderRecord.openRouterDisplayName
            : provider.name
        contentConfiguration.secondaryText = provider.apiBase
        contentConfiguration.image = UIImage(systemName: "globe")

        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let provider = providers[indexPath.row]
        navigationController?.pushViewController(
            ProviderConfigurationViewController(provider: provider, store: store),
            animated: true
        )
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self,
                  indexPath.row < providers.count else {
                completion(false)
                return
            }

            let provider = providers.remove(at: indexPath.row)
            store.deleteProvider(id: provider.id)
            tableView.performBatchUpdates {
                tableView.deleteRows(at: [indexPath], with: .fade)
            } completion: { _ in
                completion(true)
            }
        }
        deleteAction.image = UIImage(systemName: "trash")

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

private final class ProviderConfigurationViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case configuration
        case models
    }

    private enum ConfigurationRow: Int, CaseIterable {
        case name
        case apiKey
        case apiBase
    }

    private let store: LLMProviderStore
    private let apiClient: OpenRouterAPIClient
    private var saveButtonItem: UIBarButtonItem?
    private var provider: LLMProviderRecord
    private var savedProvider: LLMProviderRecord
    private var isNewProvider: Bool
    private var isLoadingModels = false
    private var didStartInitialModelLoad = false

    private lazy var updatedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(
        provider: LLMProviderRecord,
        store: LLMProviderStore,
        isNewProvider: Bool = false,
        apiClient: OpenRouterAPIClient = OpenRouterAPIClient()
    ) {
        self.provider = provider
        savedProvider = provider
        self.isNewProvider = isNewProvider
        self.store = store
        self.apiClient = apiClient
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        provider = LLMProviderRecord(
            id: UUID(),
            kind: .openRouter,
            name: LLMProviderRecord.openRouterDisplayName,
            apiKey: "",
            apiBase: LLMProviderRecord.openRouterDefaultAPIBase,
            models: [],
            modelsUpdatedAt: nil,
            createdAt: Date()
        )
        savedProvider = provider
        isNewProvider = true
        store = .shared
        apiClient = OpenRouterAPIClient()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = provider.name
        tableView.register(
            ProviderTextFieldCell.self,
            forCellReuseIdentifier: ProviderTextFieldCell.reuseIdentifier
        )
        configureSaveButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !isNewProvider,
              !didStartInitialModelLoad else {
            return
        }

        didStartInitialModelLoad = true
        refreshModels()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .configuration:
            return ConfigurationRow.allCases.count
        case .models:
            return provider.models.count + 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            return nil
        }

        switch section {
        case .configuration:
            return "Configuration"
        case .models:
            return "Models"
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .configuration:
            return configurationCell(for: indexPath)
        case .models:
            return modelCell(for: indexPath)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        switch section {
        case .configuration:
            (tableView.cellForRow(at: indexPath) as? ProviderTextFieldCell)?.activateTextField()
        case .models where indexPath.row == 0:
            refreshModels()
        case .models:
            return
        }
    }

    private func configurationCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let row = ConfigurationRow(rawValue: indexPath.row),
              let cell = tableView.dequeueReusableCell(
                withIdentifier: ProviderTextFieldCell.reuseIdentifier,
                for: indexPath
              ) as? ProviderTextFieldCell else {
            return UITableViewCell()
        }

        switch row {
        case .name:
            cell.configure(
                title: "Name",
                text: provider.name,
                placeholder: LLMProviderRecord.openRouterDisplayName,
                isSecureTextEntry: false,
                keyboardType: .default,
                textContentType: .name
            )
            cell.onTextChange = { [weak self] text in
                self?.provider.name = text
                self?.title = text.isEmpty ? LLMProviderRecord.openRouterDisplayName : text
                self?.updateSaveButtonState()
            }
        case .apiKey:
            cell.configure(
                title: "Key",
                text: provider.apiKey,
                placeholder: "OpenRouter API Key",
                isSecureTextEntry: true,
                keyboardType: .asciiCapable,
                textContentType: .password
            )
            cell.onTextChange = { [weak self] text in
                self?.provider.apiKey = text
                self?.updateSaveButtonState()
            }
        case .apiBase:
            cell.configure(
                title: "API Base",
                text: provider.apiBase,
                placeholder: LLMProviderRecord.openRouterDefaultAPIBase,
                isSecureTextEntry: false,
                keyboardType: .URL,
                textContentType: .URL
            )
            cell.onTextChange = { [weak self] text in
                self?.provider.apiBase = text
                self?.updateSaveButtonState()
            }
        }

        return cell
    }

    private func modelCell(for indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var contentConfiguration = UIListContentConfiguration.subtitleCell()
            contentConfiguration.text = isLoadingModels ? "Refreshing Model List" : "Refresh Model List"
            contentConfiguration.secondaryText = modelRefreshDetailText
            contentConfiguration.image = UIImage(systemName: "arrow.clockwise")
            cell.contentConfiguration = contentConfiguration
            cell.selectionStyle = isLoadingModels ? .none : .default

            if isLoadingModels {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
            }

            return cell
        }

        let model = provider.models[indexPath.row - 1]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = UIListContentConfiguration.subtitleCell()
        contentConfiguration.text = model.name
        contentConfiguration.secondaryText = model.id
        contentConfiguration.image = UIImage(systemName: "cpu")
        contentConfiguration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.selectionStyle = .none
        return cell
    }

    private var modelRefreshDetailText: String? {
        guard let updatedAt = provider.modelsUpdatedAt else {
            return nil
        }

        return "Updated \(updatedDateFormatter.string(from: updatedAt))"
    }

    private func presentModelLoadError(_ error: Error) {
        guard presentedViewController == nil else {
            return
        }

        let alertController = UIAlertController(
            title: "Unable to Refresh Models",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    private func refreshModels() {
        guard !isLoadingModels else {
            return
        }

        isLoadingModels = true
        reloadModelsSection(animated: true)

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let models = try await apiClient.fetchModels(
                    apiBase: provider.apiBase,
                    apiKey: provider.apiKey
                )
                let modelsUpdatedAt = Date()
                provider.models = models
                provider.modelsUpdatedAt = modelsUpdatedAt
                savedProvider.models = models
                savedProvider.modelsUpdatedAt = modelsUpdatedAt
                if !isNewProvider {
                    store.updateProviderModels(
                        id: provider.id,
                        models: models,
                        modelsUpdatedAt: modelsUpdatedAt
                    )
                }
            } catch {
                presentModelLoadError(error)
            }

            isLoadingModels = false
            updateSaveButtonState()
            reloadModelsSection(animated: true)
        }
    }

    private func configureSaveButton() {
        let saveItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveConfiguration)
        )
        saveButtonItem = saveItem
        updateSaveButtonState()
    }

    @objc private func saveConfiguration() {
        view.endEditing(true)
        store.saveProvider(provider)
        isNewProvider = false
        savedProvider = provider
        title = provider.name.isEmpty ? LLMProviderRecord.openRouterDisplayName : provider.name
        updateSaveButtonState()
        navigationController?.popViewController(animated: true)
    }

    private func updateSaveButtonState() {
        navigationItem.rightBarButtonItem = canSaveConfiguration ? saveButtonItem : nil
    }

    private var canSaveConfiguration: Bool {
        hasUnsavedConfigurationChanges && hasRequiredConfigurationFields
    }

    private var hasRequiredConfigurationFields: Bool {
        !provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !provider.apiBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasUnsavedConfigurationChanges: Bool {
        provider.name != savedProvider.name
            || provider.apiKey != savedProvider.apiKey
            || provider.apiBase != savedProvider.apiBase
    }

    private func reloadModelsSection(animated: Bool) {
        let sectionIndexSet = IndexSet(integer: Section.models.rawValue)
        tableView.reloadSections(sectionIndexSet, with: animated ? .automatic : .none)
    }
}

private final class ProviderTextFieldCell: UITableViewCell {
    static let reuseIdentifier = "ProviderTextFieldCell"

    private let contentStackView = UIStackView()
    private let fieldTitleLabel = UILabel()
    private let textField = UITextField()

    var onTextChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        onTextChange = nil
        textField.text = nil
        textField.placeholder = nil
        textField.isSecureTextEntry = false
        textField.textContentType = nil
    }

    func configure(
        title: String,
        text: String,
        placeholder: String,
        isSecureTextEntry: Bool,
        keyboardType: UIKeyboardType,
        textContentType: UITextContentType?
    ) {
        fieldTitleLabel.text = title
        textField.text = text
        textField.placeholder = placeholder
        textField.isSecureTextEntry = isSecureTextEntry
        textField.keyboardType = keyboardType
        textField.textContentType = textContentType
    }

    func activateTextField() {
        textField.becomeFirstResponder()
    }

    private func configure() {
        selectionStyle = .none

        contentStackView.axis = .horizontal
        contentStackView.alignment = .firstBaseline
        contentStackView.spacing = UIStackView.spacingUseSystem
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        fieldTitleLabel.font = .preferredFont(forTextStyle: .body)
        fieldTitleLabel.adjustsFontForContentSizeCategory = true
        fieldTitleLabel.textColor = .label
        fieldTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        fieldTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textAlignment = .right
        textField.returnKeyType = .done
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        contentStackView.addArrangedSubview(fieldTitleLabel)
        contentStackView.addArrangedSubview(textField)
        contentView.addSubview(contentStackView)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: margins.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: margins.bottomAnchor)
        ])
    }

    @objc private func textFieldDidChange() {
        onTextChange?(textField.text ?? "")
    }
}

private final class SentMessageBubbleView: UIView {
    private enum Metrics {
        static let controlHeight: CGFloat = 44.0
        static let horizontalInset: CGFloat = 12.0
        static let verticalInset: CGFloat = 8.0
        static let multilineCornerRadius: CGFloat = 22.0
    }

    private let messageText: String
    private let glassView = UIVisualEffectView(effect: SentMessageBubbleView.makeGlassEffect())
    private let label = UILabel()

    var currentCornerRadius: CGFloat {
        isSingleLineLayout ? bounds.height * 0.5 : Metrics.multilineCornerRadius
    }

    init(text: String) {
        messageText = text
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        messageText = ""
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        label.preferredMaxLayoutWidth = label.bounds.width
        updateCornerConfiguration()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        glassView.backgroundColor = .clear
        glassView.isUserInteractionEnabled = false
        glassView.cornerConfiguration = .capsule()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        label.text = messageText
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            label.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            label.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Metrics.verticalInset
            ),
            label.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Metrics.verticalInset
            )
        ])
    }

    private func updateCornerConfiguration() {
        if isSingleLineLayout {
            glassView.cornerConfiguration = .capsule()
        } else {
            glassView.cornerConfiguration = .corners(
                radius: .fixed(Double(Metrics.multilineCornerRadius))
            )
        }
    }

    private var isSingleLineLayout: Bool {
        guard !messageText.contains("\n"),
              label.bounds.width > 0.0,
              let font = label.font else {
            return false
        }

        let fittingSize = label.sizeThatFits(
            CGSize(width: label.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        )
        return fittingSize.height <= ceil(font.lineHeight * 1.25)
    }

    private static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        return effect
    }
}

private final class GlassComposerBarView: UIVisualEffectView, UITextViewDelegate {
    struct SendTransition {
        let text: String
        let backgroundGlobalFrame: CGRect
    }

    private enum Metrics {
        static let controlHeight: CGFloat = 44.0
        static let spacing: CGFloat = 8.0
        static let fusionSpacing: CGFloat = 24.0
        static let capsuleHorizontalInset: CGFloat = 12.0
        static let capsuleComposingTrailingInset: CGFloat = 5.0
        static let capsuleVerticalInset: CGFloat = 5.0
        static let capsuleContentSpacing: CGFloat = 6.0
        static let textMinHeight: CGFloat = 32.0
        static let textMaxHeight: CGFloat = 118.0
        static let sendButtonSize: CGFloat = 34.0
        static let iconPointSize: CGFloat = 18.0
        static let transitionDuration: TimeInterval = 0.24
    }

    private let stackView = UIStackView()
    private let plusGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let capsuleGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let waveformGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let capsuleContentStackView = UIStackView()
    private let plusButton = UIButton(type: .system)
    private let waveformButton = UIButton(type: .system)
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)

    private var capsuleContentLeadingConstraint: NSLayoutConstraint!
    private var capsuleContentTrailingConstraint: NSLayoutConstraint!
    private var waveformWidthConstraint: NSLayoutConstraint!
    private var textHeightConstraint: NSLayoutConstraint!
    private var lastMeasuredTextWidth: CGFloat = 0.0
    private var isShowingSendControl = false

    var onSend: ((SendTransition) -> Void)?
    var onLayoutChange: (() -> Void)?

    private var containerGlassEffect: UIGlassContainerEffect? {
        effect as? UIGlassContainerEffect
    }

    init() {
        super.init(effect: GlassComposerBarView.makeContainerEffect())
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        effect = GlassComposerBarView.makeContainerEffect()
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = textView.bounds.width
        if abs(width - lastMeasuredTextWidth) > 0.5 {
            lastMeasuredTextWidth = width
            updateTextHeight(animated: false)
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let hasText = !textView.text.isEmpty
        placeholderLabel.isHidden = hasText
        updateInputMode(hasText: hasText, animated: true)
        updateTextHeight(animated: true)
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear

        configureStackView()
        configurePlusButton()
        configureWaveformButton()
        configureCapsule()
        updateInputMode(hasText: false, animated: false)
    }

    private func configureStackView() {
        stackView.axis = .horizontal
        stackView.alignment = .bottom
        stackView.spacing = Metrics.spacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        stackView.addArrangedSubview(plusGlassView)
        stackView.addArrangedSubview(capsuleGlassView)
        stackView.addArrangedSubview(waveformGlassView)

        plusGlassView.translatesAutoresizingMaskIntoConstraints = false
        plusGlassView.cornerConfiguration = .capsule()
        plusGlassView.setContentHuggingPriority(.required, for: .horizontal)
        plusGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)

        capsuleGlassView.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.cornerConfiguration = .corners(
            radius: .fixed(Double(Metrics.controlHeight * 0.5))
        )
        capsuleGlassView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        capsuleGlassView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        waveformGlassView.translatesAutoresizingMaskIntoConstraints = false
        waveformGlassView.cornerConfiguration = .capsule()
        waveformGlassView.setContentHuggingPriority(.required, for: .horizontal)
        waveformGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)
        waveformWidthConstraint = waveformGlassView.widthAnchor.constraint(equalToConstant: Metrics.controlHeight)

        NSLayoutConstraint.activate([
            plusGlassView.widthAnchor.constraint(equalToConstant: Metrics.controlHeight),
            plusGlassView.heightAnchor.constraint(equalToConstant: Metrics.controlHeight),
            capsuleGlassView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
            waveformWidthConstraint,
            waveformGlassView.heightAnchor.constraint(equalToConstant: Metrics.controlHeight)
        ])
    }

    private func configurePlusButton() {
        plusButton.tintColor = .label
        plusButton.setImage(
            UIImage(
                systemName: "plus",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .semibold)
            ),
            for: .normal
        )
        plusButton.accessibilityLabel = "Add"
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        plusGlassView.contentView.addSubview(plusButton)

        NSLayoutConstraint.activate([
            plusButton.topAnchor.constraint(equalTo: plusGlassView.contentView.topAnchor),
            plusButton.leadingAnchor.constraint(equalTo: plusGlassView.contentView.leadingAnchor),
            plusButton.trailingAnchor.constraint(equalTo: plusGlassView.contentView.trailingAnchor),
            plusButton.bottomAnchor.constraint(equalTo: plusGlassView.contentView.bottomAnchor)
        ])
    }

    private func configureWaveformButton() {
        waveformButton.tintColor = .label
        waveformButton.setImage(
            UIImage(
                systemName: "waveform",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .semibold)
            ),
            for: .normal
        )
        waveformButton.accessibilityLabel = "Waveform"
        waveformButton.translatesAutoresizingMaskIntoConstraints = false
        waveformGlassView.contentView.addSubview(waveformButton)

        NSLayoutConstraint.activate([
            waveformButton.topAnchor.constraint(equalTo: waveformGlassView.contentView.topAnchor),
            waveformButton.leadingAnchor.constraint(equalTo: waveformGlassView.contentView.leadingAnchor),
            waveformButton.trailingAnchor.constraint(equalTo: waveformGlassView.contentView.trailingAnchor),
            waveformButton.bottomAnchor.constraint(equalTo: waveformGlassView.contentView.bottomAnchor)
        ])
    }

    private func configureCapsule() {
        configureTextView()
        configureSendButton()

        capsuleContentStackView.axis = .horizontal
        capsuleContentStackView.alignment = .bottom
        capsuleContentStackView.spacing = Metrics.capsuleContentSpacing
        capsuleContentStackView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.contentView.addSubview(capsuleContentStackView)
        capsuleContentStackView.addArrangedSubview(textView)
        capsuleGlassView.contentView.addSubview(sendButton)

        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Metrics.textMinHeight)
        capsuleContentLeadingConstraint = capsuleContentStackView.leadingAnchor.constraint(
            equalTo: capsuleGlassView.contentView.leadingAnchor,
            constant: Metrics.capsuleHorizontalInset
        )
        capsuleContentTrailingConstraint = capsuleContentStackView.trailingAnchor.constraint(
            equalTo: capsuleGlassView.contentView.trailingAnchor,
            constant: -Metrics.capsuleHorizontalInset
        )

        NSLayoutConstraint.activate([
            capsuleContentStackView.topAnchor.constraint(
                equalTo: capsuleGlassView.contentView.topAnchor,
                constant: Metrics.capsuleVerticalInset
            ),
            capsuleContentLeadingConstraint,
            capsuleContentTrailingConstraint,
            capsuleContentStackView.bottomAnchor.constraint(
                equalTo: capsuleGlassView.contentView.bottomAnchor,
                constant: -Metrics.capsuleVerticalInset
            ),
            textHeightConstraint,

            sendButton.trailingAnchor.constraint(
                equalTo: capsuleGlassView.contentView.trailingAnchor,
                constant: -Metrics.capsuleComposingTrailingInset
            ),
            sendButton.bottomAnchor.constraint(
                equalTo: capsuleGlassView.contentView.bottomAnchor,
                constant: -Metrics.capsuleVerticalInset
            ),
            sendButton.widthAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
            sendButton.heightAnchor.constraint(equalToConstant: Metrics.sendButtonSize)
        ])
    }

    private func configureTextView() {
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.returnKeyType = .default
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 5.5, left: 0.0, bottom: 4.5, right: 0.0)
        textView.textContainer.lineFragmentPadding = 0.0
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        placeholderLabel.text = "Message"
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top)
        ])
    }

    private func configureSendButton() {
        var configuration = UIButton.Configuration.prominentClearGlass()
        configuration.image = UIImage(
            systemName: "arrow.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .bold)
        )
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        sendButton.configuration = configuration
        sendButton.accessibilityLabel = "Send"
        sendButton.addTarget(self, action: #selector(sendButtonPressed), for: .touchUpInside)
    }

    @objc private func sendButtonPressed() {
        let messageText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else {
            return
        }

        layoutIfNeeded()
        textView.layoutIfNeeded()

        let sourceTextBounds = currentTextBounds()
        let sourceBackgroundBounds = sourceBubbleBounds(around: sourceTextBounds)
        let transition = SendTransition(
            text: messageText,
            backgroundGlobalFrame: textView.convert(sourceBackgroundBounds, to: nil)
        )

        textView.text = ""
        placeholderLabel.isHidden = false
        updateInputMode(hasText: false, animated: true)
        updateTextHeight(animated: true)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSend?(transition)
    }

    private func currentTextBounds() -> CGRect {
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        let usedRect = textView.layoutManager.usedRect(for: textView.textContainer)
        let textBounds = CGRect(
            x: usedRect.minX + textView.textContainerInset.left,
            y: usedRect.minY + textView.textContainerInset.top,
            width: usedRect.width,
            height: usedRect.height
        ).insetBy(dx: -1.0, dy: -1.0)

        let visibleTextBounds = textBounds.integral.intersection(textView.bounds)
        guard !visibleTextBounds.isNull,
              visibleTextBounds.width > 0.0,
              visibleTextBounds.height > 0.0 else {
            return textView.bounds
        }

        return visibleTextBounds
    }

    private func sourceBubbleBounds(around textBounds: CGRect) -> CGRect {
        var bubbleBounds = textBounds.insetBy(
            dx: -Metrics.capsuleHorizontalInset,
            dy: -Metrics.capsuleVerticalInset
        )

        if bubbleBounds.height < Metrics.controlHeight {
            let heightDelta = Metrics.controlHeight - bubbleBounds.height
            bubbleBounds.origin.y -= heightDelta * 0.5
            bubbleBounds.size.height = Metrics.controlHeight
        }

        return bubbleBounds.integral
    }

    private func updateInputMode(hasText: Bool, animated: Bool) {
        let stateChanged = hasText != isShowingSendControl
        isShowingSendControl = hasText

        guard stateChanged || !animated else {
            return
        }

        let applyTargetState = { [self] in
            self.capsuleContentLeadingConstraint.constant = Metrics.capsuleHorizontalInset
            self.capsuleContentTrailingConstraint.constant = hasText
                ? -(Metrics.capsuleComposingTrailingInset + Metrics.sendButtonSize + Metrics.capsuleContentSpacing)
                : -Metrics.capsuleHorizontalInset
            self.waveformWidthConstraint.constant = hasText ? 0.0 : Metrics.controlHeight
            self.stackView.setCustomSpacing(hasText ? 0.0 : Metrics.spacing, after: self.capsuleGlassView)
            self.sendButton.alpha = hasText ? 1.0 : 0.0
            self.waveformGlassView.alpha = hasText ? 0.0 : 1.0
            self.superview?.layoutIfNeeded()
            self.layoutIfNeeded()
        }

        if animated {
            sendButton.isHidden = false
            waveformGlassView.isHidden = false
            sendButton.isUserInteractionEnabled = hasText
            waveformButton.isUserInteractionEnabled = !hasText
            if hasText {
                sendButton.alpha = 0.0
            }

            containerGlassEffect?.spacing = Metrics.fusionSpacing
            UIView.animate(
                withDuration: Metrics.transitionDuration,
                delay: 0.0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: {
                    applyTargetState()
                },
                completion: { _ in
                    guard self.isShowingSendControl == hasText else {
                        return
                    }

                    self.containerGlassEffect?.spacing = Metrics.spacing
                    self.sendButton.isHidden = !hasText
                    self.waveformGlassView.isHidden = hasText
                }
            )
        } else {
            containerGlassEffect?.spacing = Metrics.spacing
            applyTargetState()
            sendButton.isHidden = !hasText
            sendButton.isUserInteractionEnabled = hasText
            waveformGlassView.isHidden = hasText
            waveformButton.isUserInteractionEnabled = !hasText
        }
    }

    private func updateTextHeight(animated: Bool) {
        let fittingWidth = max(textView.bounds.width, 1.0)
        let fittingSize = textView.sizeThatFits(
            CGSize(width: fittingWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        let targetHeight = min(max(ceil(fittingSize.height), Metrics.textMinHeight), Metrics.textMaxHeight)

        textView.isScrollEnabled = fittingSize.height > Metrics.textMaxHeight

        guard abs(textHeightConstraint.constant - targetHeight) > 0.5 else {
            return
        }

        textHeightConstraint.constant = targetHeight

        let layoutChanges = {
            self.superview?.layoutIfNeeded()
            self.onLayoutChange?()
            return
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0.0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: layoutChanges
            )
        } else {
            layoutChanges()
        }
    }

    private static func makeContainerEffect() -> UIGlassContainerEffect {
        let effect = UIGlassContainerEffect()
        effect.spacing = Metrics.spacing
        return effect
    }

    private static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }
}

private final class AppGradientBackgroundView: UIView {
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isOpaque = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true

        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradientLayer.locations = [0.0, 0.5, 1.0]
        traitChangeRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AppGradientBackgroundView, _) in
            view.updateColors()
        }
        updateColors()
    }

    private func updateColors() {
        gradientLayer.colors = [
            UIColor.appBackgroundStart,
            UIColor.appBackgroundMiddle,
            UIColor.appBackgroundEnd
        ].map { $0.resolvedColor(with: traitCollection).cgColor }
    }
}

private extension UIScreen {
    var displayCornerRadius: CGFloat {
        CGFloat(truncating: value(forKey: "_displayCornerRadius") as! NSNumber)
    }
}
