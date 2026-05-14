//
//  ChatViewController.swift
//  UniLLMs
//
//  Builds the main chat UI and forwards user interaction to ChatRuntime without depending on concrete provider APIs.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class ChatViewController: UIViewController {
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
        static let bottomLockTolerance: CGFloat = 2.0
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

    private var dependencies = AppEnvironment.shared.dependencies
    private let rootBackgroundView = AppGradientBackgroundView()
    private var providerStore: LLMsProviderStore {
        dependencies.providerStore
    }
    private var providerManager: LLMsProviderManager {
        dependencies.providerManager
    }
    private var chatRuntime: ChatRuntime {
        dependencies.chatRuntime
    }
    private let sideMenuView = SideMenuView()
    private let sideMenuDismissControl = UIControl()
    private let mainPageContainerView = UIView()
    private let mainPageView = UIView()
    private let backgroundView = AppGradientBackgroundView()
    private let headerGlassContainerView = UIVisualEffectView(effect: ChatViewController.makeHeaderContainerEffect())
    private let headerStackView = UIStackView()
    private let leftHeaderGlassView = UIVisualEffectView(effect: ChatViewController.makeHeaderGlassEffect())
    private let moduleSelectionPillGlassView = UIVisualEffectView(effect: ChatViewController.makeHeaderGlassEffect())
    private let leftHeaderButton = ChatViewController.makeHeaderContentButton(
        systemName: "list.bullet",
        accessibilityLabel: "Menu"
    )
    private let moduleSelectionPillButton = ChatViewController.makeHeaderPill(
        title: HeaderLayout.defaultModuleSelectionTitle
    )
    private let rightHeaderButton = ChatViewController.makeHeaderButton(
        systemName: "app.dashed",
        accessibilityLabel: "Layout"
    )
    private let messagesScrollView = UIScrollView()
    private let messagesContentView = UIView()
    private let messagesStackView = UIStackView()
    private var messagesContentMinimumHeightConstraint: NSLayoutConstraint!
    private let composerView = GlassComposerBarView()
    private var composerLeadingConstraint: NSLayoutConstraint!
    private var composerTrailingConstraint: NSLayoutConstraint!
    private var composerKeyboardBottomConstraint: NSLayoutConstraint!
    private var composerRestingBottomConstraint: NSLayoutConstraint!
    private var keyboardObservation: NotificationCenter.ObservationToken?
    private var selectedModelSelectionObservation: NSObjectProtocol?
    private var isKeyboardVisible = false
    private var isSideMenuOpen = false
    private var selectedModelSelection: ChatModelSelection?
    private var activeResponseTask: Task<Void, Never>?
    private weak var activeResponseView: AssistantResponseTextView?
    private var isMessagesBottomLocked = true

    func configure(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
    }

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
        installSelectedModelSelectionObserver()
        reloadSelectedModelSelection(animated: false)
    }

    deinit {
        activeResponseTask?.cancel()
        if let keyboardObservation {
            NotificationCenter.default.removeObserver(keyboardObservation)
        }
        if let selectedModelSelectionObservation {
            NotificationCenter.default.removeObserver(selectedModelSelectionObservation)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadSelectedModelSelection(animated: false)
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
        messagesScrollView.layoutIfNeeded()
        updateMessagesContentOffsetAfterLayoutChange()
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
        composerView.onStop = { [weak self] in
            self?.cancelAssistantResponseStream()
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
        messagesScrollView.delegate = self
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

        messagesContentMinimumHeightConstraint = messagesContentView.heightAnchor.constraint(
            greaterThanOrEqualTo: messagesScrollView.frameLayoutGuide.heightAnchor
        )

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
            messagesContentMinimumHeightConstraint,

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
        let visibleHeight = max(0.0, messagesScrollView.bounds.height - topInset - bottomInset)
        let minimumHeightConstant = visibleHeight - messagesScrollView.bounds.height

        if abs(messagesContentMinimumHeightConstraint.constant - minimumHeightConstant) > CGFloat.ulpOfOne {
            messagesContentMinimumHeightConstraint.constant = minimumHeightConstant
        }

        if messagesScrollView.contentInset != contentInsets {
            messagesScrollView.contentInset = contentInsets
            messagesScrollView.scrollIndicatorInsets = contentInsets
        }
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
            self.messagesScrollView.layoutIfNeeded()
            self.updateMessagesContentOffsetAfterLayoutChange()
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
            dependencies: dependencies,
            selectedModelSelection: selectedModelSelection
        ) { [weak self] selection in
            guard let self else {
                return
            }

            selectedModelSelection = selection
            providerStore.saveSelectedModelSelection(selection)
            updateModuleSelectionTitle(animated: true)
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

        let settingsViewController = SettingsViewController(dependencies: dependencies)
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

        let responseView = AssistantResponseTextView()
        responseView.translatesAutoresizingMaskIntoConstraints = false
        responseView.isHidden = true
        responseView.setContentHuggingPriority(.required, for: .vertical)
        responseView.setContentCompressionResistancePriority(.required, for: .vertical)

        messagesStackView.addArrangedSubview(bubbleView)
        bubbleView.widthAnchor.constraint(
            lessThanOrEqualTo: messagesScrollView.frameLayoutGuide.widthAnchor,
            multiplier: MessagesLayout.maximumBubbleWidthRatio
        ).isActive = true
        messagesStackView.addArrangedSubview(responseView)
        responseView.widthAnchor.constraint(
            equalTo: messagesScrollView.frameLayoutGuide.widthAnchor
        ).isActive = true

        mainPageView.layoutIfNeeded()
        scrollMessagesToBottom(animated: false)
        mainPageView.layoutIfNeeded()

        startAssistantResponseStream(for: transition.text, responseView: responseView)
        animateExistingMessages(from: existingMessageFrames)
        animateSentMessage(bubbleView, from: transition) { [weak self, weak responseView] in
            guard let self,
                  let responseView else {
                return
            }

            self.showAssistantLoadingIfNeeded(in: responseView)
        }
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
        messagesScrollView.layoutIfNeeded()

        let targetOffsetY = messagesBottomContentOffsetY()
        messagesScrollView.setContentOffset(CGPoint(x: 0.0, y: targetOffsetY), animated: animated)
        isMessagesBottomLocked = true
    }

    private func messagesBottomContentOffsetY() -> CGFloat {
        messagesContentOffsetBounds().maximum
    }

    private func isMessagesScrolledToBottom(
        offsetY: CGFloat? = nil,
        tolerance: CGFloat = MessagesLayout.bottomLockTolerance
    ) -> Bool {
        let candidateOffsetY = offsetY ?? messagesScrollView.contentOffset.y
        return candidateOffsetY >= messagesBottomContentOffsetY() - tolerance
    }

    private func messagesContentOffsetBounds() -> (minimum: CGFloat, maximum: CGFloat) {
        let adjustedInsets = messagesScrollView.adjustedContentInset
        let minimumOffsetY = -adjustedInsets.top
        let maximumOffsetY = max(
            minimumOffsetY,
            messagesScrollView.contentSize.height - messagesScrollView.bounds.height + adjustedInsets.bottom
        )

        return (minimumOffsetY, maximumOffsetY)
    }

    private func clampMessagesContentOffsetIfNeeded() {
        guard !messagesScrollView.isDragging,
              !messagesScrollView.isDecelerating else {
            return
        }

        let bounds = messagesContentOffsetBounds()
        let currentOffsetY = messagesScrollView.contentOffset.y
        let clampedOffsetY = min(max(currentOffsetY, bounds.minimum), bounds.maximum)
        guard abs(currentOffsetY - clampedOffsetY) > CGFloat.ulpOfOne else {
            return
        }

        messagesScrollView.setContentOffset(CGPoint(x: 0.0, y: clampedOffsetY), animated: false)
    }

    private func updateMessagesContentOffsetAfterLayoutChange() {
        if isMessagesBottomLocked {
            scrollMessagesToBottom(animated: false)
        } else {
            clampMessagesContentOffsetIfNeeded()
        }
    }

    private func animateSentMessage(
        _ bubbleView: SentMessageBubbleView,
        from transition: GlassComposerBarView.SendTransition,
        completion: (() -> Void)? = nil
    ) {
        guard view.window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            bubbleView.alpha = 1.0
            completion?()
            return
        }

        let sourceBackgroundFrame = mainPageView.convert(transition.backgroundGlobalFrame, from: nil)
        let targetBubbleFrame = bubbleView.convert(bubbleView.bounds, to: mainPageView)

        let animatedBubbleView = SentMessageBubbleView(text: transition.text)
        animatedBubbleView.frame = sourceBackgroundFrame
        animatedBubbleView.alpha = 0.0
        animatedBubbleView.isUserInteractionEnabled = false
        animatedBubbleView.layoutIfNeeded()
        mainPageView.addSubview(animatedBubbleView)

        let animator = UIViewPropertyAnimator(
            duration: MessagesLayout.sendAnimationDuration,
            dampingRatio: MessagesLayout.sendAnimationDampingRatio
        ) {
            animatedBubbleView.frame = targetBubbleFrame
            animatedBubbleView.alpha = 1.0
            animatedBubbleView.layoutIfNeeded()
        }
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.addCompletion { _ in
            UIView.performWithoutAnimation {
                animatedBubbleView.removeFromSuperview()
                bubbleView.alpha = 1.0
            }
            completion?()
        }
        animator.startAnimation()
    }

    private func startAssistantResponseStream(
        for prompt: String,
        responseView: AssistantResponseTextView
    ) {
        guard activeResponseTask == nil else {
            setAssistantResponseError("Wait for the current response to finish.", in: responseView)
            return
        }

        let responseStream: AsyncThrowingStream<ChatResponseDelta, Error>
        do {
            responseStream = try chatRuntime.startTurn(prompt: prompt)
        } catch {
            setAssistantResponseError(error.localizedDescription, in: responseView)
            return
        }

        activeResponseView = responseView
        composerView.isSendingEnabled = false
        composerView.setStreamingResponseActive(true, animated: true)

        activeResponseTask = Task { [weak self, weak responseView] in
            do {
                for try await delta in responseStream {
                    try Task.checkCancellation()

                    await MainActor.run {
                        guard let self,
                              let responseView else {
                            return
                        }

                        self.appendStreamingResponseDelta(delta, to: responseView)
                    }
                }

                await MainActor.run {
                    guard let self else {
                        return
                    }

                    self.finishAssistantResponseStream()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self else {
                        return
                    }

                    self.finishAssistantResponseStream()
                }
            } catch {
                await MainActor.run {
                    guard let self else {
                        return
                    }

                    if let responseView {
                        self.setAssistantResponseError(error.localizedDescription, in: responseView)
                    }
                    self.finishAssistantResponseStream()
                }
            }
        }
    }

    private func cancelAssistantResponseStream() {
        guard let activeResponseTask else {
            return
        }

        if let activeResponseView {
            applyAssistantResponseChange(to: activeResponseView) {
                activeResponseView.finishStreamingContent()
                activeResponseView.setLoadingVisible(false)
            }
        }
        activeResponseTask.cancel()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func appendStreamingResponseDelta(
        _ delta: ChatResponseDelta,
        to responseView: AssistantResponseTextView
    ) {
        guard !delta.isEmpty else {
            return
        }

        applyAssistantResponseChange(to: responseView) {
            responseView.append(content: delta.content, reasoning: delta.reasoning)
        }
    }

    private func showAssistantLoadingIfNeeded(in responseView: AssistantResponseTextView) {
        guard activeResponseView === responseView else {
            return
        }

        applyAssistantResponseChange(to: responseView) {
            responseView.showLoadingIfNeeded()
        }
    }

    private func setAssistantResponseError(
        _ message: String,
        in responseView: AssistantResponseTextView
    ) {
        applyAssistantResponseChange(to: responseView) {
            responseView.setError(message)
        }
    }

    private func applyAssistantResponseChange(
        to responseView: AssistantResponseTextView,
        update: () -> Void
    ) {
        mainPageView.layoutIfNeeded()
        let previousFrames = visibleMessageFrames()
        let previousHeight = responseView.isHidden ? 0.0 : responseView.bounds.height
        let shouldFollowBottom = isMessagesBottomLocked

        update()

        mainPageView.layoutIfNeeded()
        if shouldFollowBottom {
            scrollMessagesToBottom(animated: false)
        } else {
            clampMessagesContentOffsetIfNeeded()
        }
        mainPageView.layoutIfNeeded()

        let didGrow = responseView.bounds.height - previousHeight > 0.5
        if didGrow {
            animateExistingMessages(from: previousFrames)
        }
    }

    private func finishAssistantResponseStream() {
        if let activeResponseView {
            applyAssistantResponseChange(to: activeResponseView) {
                activeResponseView.finishStreamingContent()
                activeResponseView.setLoadingVisible(false)
            }
        }
        activeResponseView = nil
        activeResponseTask = nil
        composerView.isSendingEnabled = true
        composerView.setStreamingResponseActive(false, animated: true)
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

    private func installSelectedModelSelectionObserver() {
        selectedModelSelectionObservation = NotificationCenter.default.addObserver(
            forName: LLMsProviderStore.selectedModelSelectionDidChangeNotification,
            object: providerStore,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSelectedModelSelection(animated: true)
        }
    }

    private func reloadSelectedModelSelection(animated: Bool) {
        let selection = providerManager.fetchSelectedModelSelection()
        let currentTitle = selectedModelSelection?.displayName ?? HeaderLayout.defaultModuleSelectionTitle
        let updatedTitle = selection?.displayName ?? HeaderLayout.defaultModuleSelectionTitle
        guard selection != selectedModelSelection else {
            return
        }

        selectedModelSelection = selection
        guard currentTitle != updatedTitle else {
            return
        }

        updateModuleSelectionTitle(animated: animated)
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

extension ChatViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === messagesScrollView else {
            return
        }

        isMessagesBottomLocked = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === messagesScrollView,
              scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else {
            return
        }

        isMessagesBottomLocked = isMessagesScrolledToBottom()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView === messagesScrollView else {
            return
        }

        isMessagesBottomLocked = isMessagesScrolledToBottom(offsetY: targetContentOffset.pointee.y)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === messagesScrollView,
              !decelerate else {
            return
        }

        isMessagesBottomLocked = isMessagesScrolledToBottom()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === messagesScrollView else {
            return
        }

        isMessagesBottomLocked = isMessagesScrolledToBottom()
    }
}
