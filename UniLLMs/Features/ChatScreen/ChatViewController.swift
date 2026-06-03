//
//  ChatViewController.swift
//  UniLLMs
//
//  Builds the main chat UI and forwards user interaction to ChatRuntime without depending on concrete provider APIs.
//  Created by Zayrick on 2026/5/11.
//

import UIKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

final class ChatViewController: UIViewController {
    private enum HeaderLayout {
        static var defaultModuleSelectionTitle: String { String(localized: .chatSelectModel) }
        static let emptyConversationButtonSystemName = "app.dashed"
        static let newConversationButtonSystemName = "plus.message"
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
        static let autoScrollAnimationDuration: TimeInterval = 0.24
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
    private let rootBackgroundView = UIView()
    private var providerStore: LLMsProviderStore {
        dependencies.providerStore
    }
    private var providerManager: LLMsProviderManager {
        dependencies.providerManager
    }
    private var chatRuntime: ChatRuntime {
        dependencies.chatRuntime
    }
    private var chatContinuationTaskCoordinator: ChatContinuationTaskCoordinator {
        dependencies.chatContinuationTaskCoordinator
    }
    private var chatHistoryStore: UserDefaultsChatStore {
        dependencies.chatHistoryStore
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
        accessibilityLabel: String(localized: .chatMenu)
    )
    private let moduleSelectionPillButton = ChatViewController.makeHeaderPill(
        title: HeaderLayout.defaultModuleSelectionTitle
    )
    private let rightHeaderButton = ChatViewController.makeHeaderButton(
        systemName: HeaderLayout.emptyConversationButtonSystemName,
        accessibilityLabel: String(localized: .chatLayout)
    )
    private let messagesScrollView = UIScrollView()
    private lazy var messagesScrollCoordinator = MessagesScrollCoordinator(
        scrollView: messagesScrollView,
        bottomLockTolerance: MessagesLayout.bottomLockTolerance,
        autoScrollAnimationDuration: MessagesLayout.autoScrollAnimationDuration
    )
    private let messagesContentView = MessagesContentView()
    /// Empty title label sitting in the chat header band. It is placed behind
    /// the three header glass elements and in front of the messages scroll
    /// view, and also hosts the messages scroll view's top
    /// `UIScrollEdgeElementContainerInteraction`. Because the host view is a
    /// plain non-glass `UILabel` (mirroring `SideMenuView`'s `titleLabel`),
    /// the system renders the `.soft` scroll edge effect — a progressive
    /// blur + fade — directly over this region.
    private let topTitleLabel = UILabel()
    private let messagesStackView = UIStackView()
    private var messagesContentMinimumHeightConstraint: NSLayoutConstraint!
    private let composerView = GlassComposerBarView()
    private var composerLeadingConstraint: NSLayoutConstraint!
    private var composerTrailingConstraint: NSLayoutConstraint!
    private var composerKeyboardBottomConstraint: NSLayoutConstraint!
    private var composerRestingBottomConstraint: NSLayoutConstraint!
    private var keyboardObservation: NotificationCenter.ObservationToken?
    private var selectedModelSelectionObservation: NSObjectProtocol?
    private var chatHistoryObservation: NSObjectProtocol?
    private var systemPromptObservation: NSObjectProtocol?
    private var historyReloadTask: Task<Void, Never>?
    private var historySelectionTask: Task<Void, Never>?
    private var isKeyboardVisible = false
    private var isSideMenuOpen = false
    private var selectedModelSelection: ChatModelSelection?
    private var activeResponseTask: Task<Void, Never>?
    private var activeContinuationTask: ChatContinuationTask?
    private weak var activeResponseView: AssistantResponseTextView?
    private var pendingAttachments: [ChatAttachment] = []
    private let attachmentStore = ChatAttachmentStore.shared
    private var attachmentPreviewItem: AttachmentPreviewItem?

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
        installChatHistoryObserver()
        installSystemPromptObserver()
        reloadSelectedModelSelection(animated: false)
        reloadSelectedSystemPrompt()
        reloadHistorySessions(selectedSessionID: nil)
    }

    deinit {
        activeResponseTask?.cancel()
        if let activeContinuationTask {
            Task { @MainActor in
                activeContinuationTask.finish(success: false)
            }
        }
        historyReloadTask?.cancel()
        historySelectionTask?.cancel()
        if let keyboardObservation {
            NotificationCenter.default.removeObserver(keyboardObservation)
        }
        if let selectedModelSelectionObservation {
            NotificationCenter.default.removeObserver(selectedModelSelectionObservation)
        }
        if let chatHistoryObservation {
            NotificationCenter.default.removeObserver(chatHistoryObservation)
        }
        if let systemPromptObservation {
            NotificationCenter.default.removeObserver(systemPromptObservation)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadSelectedModelSelection(animated: false)
        reloadSelectedSystemPrompt()
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
        rootBackgroundView.isOpaque = true
        rootBackgroundView.backgroundColor = .appBackgroundMiddle
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
        sideMenuView.onSessionSelected = { [weak self] session in
            self?.selectHistorySession(session)
        }
        sideMenuView.onSessionDeleted = { [weak self] session in
            self?.deleteHistorySession(session)
        }
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
        rightHeaderButton.addTarget(self, action: #selector(startNewConversation), for: .touchUpInside)
        updateRightHeaderButtonState(animated: false)

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
        composerView.onPlusTap = { [weak self] in
            self?.presentComposerAddSheet()
        }
        composerView.onLayoutChange = { [weak self] in
            self?.updateMessagesContentInsets()
        }
        composerView.onRemoveAttachment = { [weak self] id in
            self?.removePendingAttachment(id: id)
        }
        composerView.onPreviewAttachment = { [weak self] id in
            self?.previewPendingAttachment(id: id)
        }
        composerView.onRemoveSystemPrompt = { [weak self] in
            self?.clearSelectedSystemPrompt()
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
        messagesContentView.onDidLayoutSubviews = { [weak self] in
            guard let self else {
                return
            }

            self.updateMessagesContentOffsetAfterLayoutChange()
        }
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
                equalTo: mainPageView.leadingAnchor
            ),
            messagesScrollView.trailingAnchor.constraint(
                equalTo: mainPageView.trailingAnchor
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

            messagesStackView.leadingAnchor.constraint(
                equalTo: messagesContentView.safeAreaLayoutGuide.leadingAnchor,
                constant: MessagesLayout.horizontalInset
            ),
            messagesStackView.trailingAnchor.constraint(
                equalTo: messagesContentView.safeAreaLayoutGuide.trailingAnchor,
                constant: -MessagesLayout.horizontalInset
            ),
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
        configureTopScrollEdgeAnchor()
        addScrollEdgeInteraction(to: composerView, edge: .bottom)
    }

    /// Add an empty title label across the chat header band, sitting in front
    /// of the messages scroll view and behind all three header glass elements
    /// (left button, module pill, right button). The label also hosts the
    /// messages scroll view's top `UIScrollEdgeElementContainerInteraction`,
    /// which makes the system render the `.soft` scroll edge effect
    /// (progressive blur + fade) directly over this region — matching the
    /// look of `SideMenuView`'s title label.
    private func configureTopScrollEdgeAnchor() {
        topTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        topTitleLabel.text = ""
        topTitleLabel.backgroundColor = .clear
        topTitleLabel.isUserInteractionEnabled = false
        topTitleLabel.isAccessibilityElement = false
        // Insert the label in front of the messages scroll view but behind the
        // three header glass elements. `headerGlassContainerView` is currently
        // the front-most header subview, so inserting below it is sufficient
        // to stay behind every header glass surface.
        mainPageView.insertSubview(topTitleLabel, belowSubview: headerGlassContainerView)

        NSLayoutConstraint.activate([
            topTitleLabel.topAnchor.constraint(equalTo: mainPageView.topAnchor),
            topTitleLabel.leadingAnchor.constraint(equalTo: mainPageView.leadingAnchor),
            topTitleLabel.trailingAnchor.constraint(equalTo: mainPageView.trailingAnchor),
            topTitleLabel.bottomAnchor.constraint(equalTo: headerGlassContainerView.bottomAnchor)
        ])

        addScrollEdgeInteraction(to: topTitleLabel, edge: .top)
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
            self.updateMessagesContentOffsetAfterLayoutChange(allowsAnimatedFollow: false)
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

    @objc private func startNewConversation() {
        guard activeResponseTask == nil,
              hasChatContent else {
            return
        }

        chatRuntime.resetConversation()
        removeChatContent()
        reloadSelectedSystemPrompt()
        messagesScrollCoordinator.lockToBottom()
        updateRightHeaderButtonState(animated: true)
        reloadHistorySessions(selectedSessionID: nil)
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

    private func presentComposerAddSheet() {
        view.endEditing(true)

        let addViewController = ComposerAddSheetViewController()
        addViewController.modalPresentationStyle = .pageSheet
        if let sheet = addViewController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        addViewController.preferredTransition = .zoom { [weak self] _ in
            self?.composerView.plusSourceView
        }
        addViewController.onAction = { [weak self] action in
            self?.handleComposerAddSheetAction(action)
        }
        present(addViewController, animated: true)
    }

    private func handleComposerAddSheetAction(_ action: ComposerAddSheetViewController.Action) {
        switch action {
        case .systemPrompt:
            presentSystemPromptSelection()
        case .camera:
            presentCameraPicker()
        case .photoLibrary:
            presentPhotoLibraryPicker()
        case .files:
            presentDocumentPicker()
        }
    }

    private func presentSystemPromptSelection() {
        guard presentedViewController == nil else {
            return
        }

        let promptsViewController = SystemPromptsViewController(
            dependencies: dependencies,
            mode: .select(
                selectedID: chatRuntime.selectedSystemPromptID,
                onSelect: { [weak self] prompt in
                    self?.selectSystemPrompt(prompt)
                },
                onClear: { [weak self] in
                    self?.clearSelectedSystemPrompt()
                }
            )
        )
        let navigationController = UINavigationController(rootViewController: promptsViewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }

    private func presentCameraPicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentAttachmentError(String(localized: .chatAttachmentCameraUnavailable))
            return
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentPhotoLibraryPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.item],
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentAttachmentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: .generalOk), style: .default))
        present(alert, animated: true)
    }

    private func appendPendingAttachments(_ attachments: [ChatAttachment]) {
        guard !attachments.isEmpty else { return }
        pendingAttachments.append(contentsOf: attachments)
        refreshComposerAttachmentPreview()
    }

    private func removePendingAttachment(id: UUID) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else {
            return
        }
        pendingAttachments.remove(at: index)
        refreshComposerAttachmentPreview()
    }

    private func clearPendingAttachments() {
        guard !pendingAttachments.isEmpty else { return }
        pendingAttachments.removeAll()
        refreshComposerAttachmentPreview()
    }

    private func selectSystemPrompt(_ prompt: SystemPromptRecord) {
        chatRuntime.selectSystemPrompt(id: prompt.id)
        reloadSelectedSystemPrompt()
    }

    private func clearSelectedSystemPrompt() {
        chatRuntime.clearSelectedSystemPrompt()
        reloadSelectedSystemPrompt()
    }

    private func previewPendingAttachment(id: UUID) {
        guard let attachment = pendingAttachments.first(where: { $0.id == id }) else {
            return
        }

        presentAttachmentPreview(for: attachment)
    }

    private func presentAttachmentPreview(for attachment: ChatAttachment) {
        guard presentedViewController == nil else {
            return
        }

        guard let url = attachmentStore.fileURL(for: attachment) else {
            presentAttachmentError(String(localized: .chatAttachmentFileMissing))
            return
        }

        let previewItem = AttachmentPreviewItem(url: url, title: attachment.filename)
        guard QLPreviewController.canPreview(previewItem) else {
            presentAttachmentError(String(localized: .chatAttachmentPreviewUnavailable))
            return
        }

        attachmentPreviewItem = previewItem
        view.endEditing(true)

        let previewController = QLPreviewController()
        previewController.dataSource = self
        previewController.delegate = self
        previewController.currentPreviewItemIndex = 0
        present(previewController, animated: true)
    }

    private func presentMessageEditor(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        guard activeResponseTask == nil else {
            presentAttachmentError(String(localized: .chatResponseInProgress))
            return
        }

        guard presentedViewController == nil else {
            return
        }

        guard containsSentMessage(withID: messageID) else {
            presentAttachmentError(String(localized: .chatMessageUnavailable))
            return
        }

        view.endEditing(true)

        let editorViewController = MessageEditViewController(
            text: text,
            allowsEmptyText: !attachments.isEmpty
        )
        editorViewController.onSubmit = { [weak self, weak editorViewController] editedText in
            editorViewController?.dismiss(animated: true) {
                self?.resendEditedMessage(
                    messageID: messageID,
                    text: editedText,
                    attachments: attachments
                )
            }
        }

        let navigationController = UINavigationController(rootViewController: editorViewController)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    private func presentMessageRevisionHistory(messageID: UUID) {
        guard presentedViewController == nil else {
            return
        }

        guard containsSentMessage(withID: messageID) else {
            presentAttachmentError(String(localized: .chatMessageUnavailable))
            return
        }

        let revisions = chatRuntime.messageRevisions(for: messageID)
        guard !revisions.isEmpty else {
            return
        }

        view.endEditing(true)

        let historyViewController = MessageRevisionHistoryViewController(revisions: revisions)
        let navigationController = UINavigationController(rootViewController: historyViewController)
        historyViewController.onSelectRevision = { [weak self, weak navigationController] revision in
            navigationController?.dismiss(animated: true) {
                self?.switchToMessageRevision(
                    messageID: messageID,
                    revisionID: revision.id
                )
            }
        }
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    private func switchToMessageRevision(
        messageID: UUID,
        revisionID: UUID
    ) {
        guard activeResponseTask == nil else {
            presentAttachmentError(String(localized: .chatResponseInProgress))
            return
        }

        do {
            let events = try chatRuntime.switchToMessageRevision(
                anchorUserMessageID: messageID,
                revisionID: revisionID
            )
            renderConversationTimeline(events)
            messagesScrollCoordinator.lockToBottom()
            updateRightHeaderButtonState(animated: true)
            reloadHistorySessions(selectedSessionID: chatRuntime.currentSessionID)
        } catch {
            presentAttachmentError(error.localizedDescription)
        }
    }

    private func resendEditedMessage(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        let editedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        resendMessage(
            messageID: messageID,
            text: editedText,
            attachments: attachments
        )
    }

    private func resendMessage(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        guard activeResponseTask == nil else {
            presentAttachmentError(String(localized: .chatResponseInProgress))
            return
        }

        guard !text.isEmpty || !attachments.isEmpty else {
            return
        }

        mainPageView.layoutIfNeeded()
        let existingMessageFrames = visibleMessageFrames()

        guard let firstRemovedIndex = indexOfSentMessage(withID: messageID) else {
            presentAttachmentError(String(localized: .chatMessageUnavailable))
            return
        }

        let continuationTask: ChatContinuationTask?
        do {
            continuationTask = try beginResponseContinuationTaskIfNeeded()
        } catch {
            presentAttachmentError(error.localizedDescription)
            return
        }

        let responseStream: AsyncThrowingStream<ChatResponseDelta, Error>
        do {
            responseStream = try chatRuntime.startTurn(
                prompt: text,
                attachments: attachments,
                userMessageID: messageID,
                replacingUserMessageID: messageID
            )
        } catch {
            continuationTask?.finish(success: false)
            presentAttachmentError(error.localizedDescription)
            return
        }

        removeMessagesStarting(at: firstRemovedIndex)
        let (bubbleView, responseView) = appendOutgoingMessageViews(
            messageID: messageID,
            text: text,
            attachments: attachments
        )

        mainPageView.layoutIfNeeded()
        scrollMessagesToBottom(animated: false)
        mainPageView.layoutIfNeeded()

        activateAssistantResponseStream(
            responseStream,
            responseView: responseView,
            continuationTask: continuationTask
        )
        refreshEditHistory(for: bubbleView)
        animateExistingMessages(from: existingMessageFrames)
        showAssistantLoadingIfNeeded(in: responseView)
    }

    private func refreshEditHistory(for bubbleView: SentMessageBubbleView) {
        bubbleView.editHistoryCount = chatRuntime.messageRevisions(for: bubbleView.messageID).count
    }

    private func containsSentMessage(withID messageID: UUID) -> Bool {
        indexOfSentMessage(withID: messageID) != nil
    }

    private func indexOfSentMessage(withID messageID: UUID) -> Int? {
        messagesStackView.arrangedSubviews.firstIndex { view in
            (view as? SentMessageBubbleView)?.messageID == messageID
        }
    }

    private func removeMessagesStarting(at firstRemovedIndex: Int) {
        let removedViews = Array(messagesStackView.arrangedSubviews[firstRemovedIndex...])
        removedViews.forEach { messageView in
            messagesStackView.removeArrangedSubview(messageView)
            messageView.removeFromSuperview()
        }
    }

    private func refreshComposerAttachmentPreview() {
        let displays = pendingAttachments.map { attachment -> GlassComposerBarView.PendingAttachmentDisplay in
            let image: UIImage?
            switch attachment.kind {
            case .image:
                if let url = attachmentStore.fileURL(for: attachment),
                   let data = try? Data(contentsOf: url) {
                    image = UIImage(data: data)
                } else {
                    image = nil
                }
            case .file:
                image = nil
            }

            return GlassComposerBarView.PendingAttachmentDisplay(
                id: attachment.id,
                image: image,
                filename: attachment.filename,
                isFile: attachment.kind == .file
            )
        }
        composerView.setPendingAttachments(displays)
    }

    private func refreshComposerSystemPromptPreview() {
        let display = chatRuntime.selectedSystemPrompt().map {
            GlassComposerBarView.SelectedSystemPromptDisplay(
                id: $0.id,
                title: $0.displayTitle
            )
        }
        composerView.setSelectedSystemPrompt(display)
    }

    private func installSystemPromptObserver() {
        systemPromptObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsSystemPromptStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            self.reloadSelectedSystemPrompt()
        }
    }

    private func reloadSelectedSystemPrompt() {
        refreshComposerSystemPromptPreview()
    }

    private func appendOutgoingMessageViews(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment],
        initialBubbleAlpha: CGFloat = 1.0
    ) -> (bubbleView: SentMessageBubbleView, responseView: AssistantResponseTextView) {
        let bubbleView = SentMessageBubbleView(
            messageID: messageID,
            text: text,
            attachments: attachments
        )
        configureSentMessageActions(for: bubbleView)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.alpha = initialBubbleAlpha
        bubbleView.setContentHuggingPriority(.required, for: .vertical)
        bubbleView.setContentCompressionResistancePriority(.required, for: .vertical)

        let responseView = AssistantResponseTextView()
        responseView.translatesAutoresizingMaskIntoConstraints = false
        responseView.isHidden = true
        responseView.setContentHuggingPriority(.required, for: .vertical)
        responseView.setContentCompressionResistancePriority(.required, for: .vertical)

        messagesStackView.addArrangedSubview(bubbleView)
        bubbleView.widthAnchor.constraint(
            lessThanOrEqualTo: messagesStackView.widthAnchor,
            multiplier: MessagesLayout.maximumBubbleWidthRatio
        ).isActive = true
        messagesStackView.addArrangedSubview(responseView)
        responseView.widthAnchor.constraint(
            equalTo: messagesStackView.widthAnchor
        ).isActive = true

        return (bubbleView, responseView)
    }

    private func appendSentMessage(using transition: GlassComposerBarView.SendTransition) {
        mainPageView.layoutIfNeeded()
        let existingMessageFrames = visibleMessageFrames()
        let messageID = UUID()

        let attachmentsForTurn = pendingAttachments
        pendingAttachments.removeAll()
        refreshComposerAttachmentPreview()

        let (bubbleView, responseView) = appendOutgoingMessageViews(
            messageID: messageID,
            text: transition.text,
            attachments: attachmentsForTurn,
            initialBubbleAlpha: 0.0
        )

        mainPageView.layoutIfNeeded()
        scrollMessagesToBottom(animated: false)
        mainPageView.layoutIfNeeded()

        startAssistantResponseStream(
            for: transition.text,
            attachments: attachmentsForTurn,
            userMessageID: messageID,
            responseView: responseView
        )
        animateExistingMessages(from: existingMessageFrames)
        animateSentMessage(
            bubbleView,
            from: transition,
            attachments: attachmentsForTurn
        ) { [weak self, weak responseView] in
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
        messagesScrollCoordinator.scrollToBottom(hostView: view, animated: animated)
    }

    private func updateMessagesContentOffsetAfterLayoutChange(allowsAnimatedFollow: Bool = true) {
        messagesScrollCoordinator.reconcileAfterLayout(
            hostView: view,
            allowsAnimatedFollow: allowsAnimatedFollow
        )
    }

    private func animateSentMessage(
        _ bubbleView: SentMessageBubbleView,
        from transition: GlassComposerBarView.SendTransition,
        attachments: [ChatAttachment] = [],
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

        let animatedBubbleView = SentMessageBubbleView(text: transition.text, attachments: attachments)
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
        attachments: [ChatAttachment] = [],
        userMessageID: UUID = UUID(),
        responseView: AssistantResponseTextView
    ) {
        guard activeResponseTask == nil else {
            setAssistantResponseError(String(localized: .chatResponseInProgress), in: responseView)
            updateRightHeaderButtonState(animated: true)
            return
        }

        let continuationTask: ChatContinuationTask?
        do {
            continuationTask = try beginResponseContinuationTaskIfNeeded()
        } catch {
            setAssistantResponseError(error.localizedDescription, in: responseView)
            updateRightHeaderButtonState(animated: true)
            return
        }

        let responseStream: AsyncThrowingStream<ChatResponseDelta, Error>
        do {
            responseStream = try chatRuntime.startTurn(
                prompt: prompt,
                attachments: attachments,
                userMessageID: userMessageID
            )
        } catch {
            continuationTask?.finish(success: false)
            setAssistantResponseError(error.localizedDescription, in: responseView)
            updateRightHeaderButtonState(animated: true)
            return
        }

        activateAssistantResponseStream(
            responseStream,
            responseView: responseView,
            continuationTask: continuationTask
        )
    }

    private func activateAssistantResponseStream(
        _ responseStream: AsyncThrowingStream<ChatResponseDelta, Error>,
        responseView: AssistantResponseTextView,
        continuationTask: ChatContinuationTask?
    ) {
        activeResponseView = responseView
        activeContinuationTask = continuationTask
        activeContinuationTask?.onExpiration = { [weak self] in
            self?.cancelAssistantResponseStream()
        }
        composerView.isSendingEnabled = false
        composerView.setStreamingResponseActive(true, animated: true)
        setBackgroundFlowing(true, animated: true)

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

                    self.finishAssistantResponseStream(success: true)
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self else {
                        return
                    }

                    self.finishAssistantResponseStream(success: false)
                }
            } catch {
                await MainActor.run {
                    guard let self else {
                        return
                    }

                    if let responseView {
                        self.setAssistantResponseError(error.localizedDescription, in: responseView)
                    }
                    self.finishAssistantResponseStream(success: false)
                }
            }
        }
        updateRightHeaderButtonState(animated: true)
    }

    private func beginResponseContinuationTaskIfNeeded() throws -> ChatContinuationTask? {
        guard dependencies.appSettingsStore.isBackgroundRuntimeEnabled else {
            return nil
        }

        return try chatContinuationTaskCoordinator.beginResponseTask()
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
        activeContinuationTask?.finish(success: false)
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

        activeContinuationTask?.report(delta: delta)
        applyAssistantResponseChange(to: responseView) {
            for part in delta.displayParts {
                responseView.appendDisplayPart(part)
            }
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
        to _: AssistantResponseTextView,
        update: () -> Void
    ) {
        update()

        messagesStackView.setNeedsLayout()
        messagesContentView.setNeedsLayout()
        messagesScrollView.setNeedsLayout()
        mainPageView.setNeedsLayout()
    }

    private func finishAssistantResponseStream(success: Bool) {
        if let activeResponseView {
            applyAssistantResponseChange(to: activeResponseView) {
                activeResponseView.finishStreamingContent()
                activeResponseView.setLoadingVisible(false)
            }
        }
        activeContinuationTask?.finish(success: success)
        activeContinuationTask = nil
        activeResponseView = nil
        activeResponseTask = nil
        composerView.isSendingEnabled = true
        composerView.setStreamingResponseActive(false, animated: true)
        setBackgroundFlowing(false, animated: true)
        updateRightHeaderButtonState(animated: true)
    }

    private func setBackgroundFlowing(_ isFlowing: Bool, animated: Bool) {
        backgroundView.setFlowing(isFlowing, animated: animated)
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

    private func installChatHistoryObserver() {
        chatHistoryObservation = NotificationCenter.default.addObserver(
            forName: ChatRuntime.historyDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            self.reloadHistorySessions(selectedSessionID: self.chatRuntime.currentSessionID)
        }
    }

    private func reloadHistorySessions(selectedSessionID: UUID?) {
        historyReloadTask?.cancel()
        historyReloadTask = Task { [weak self] in
            guard let self else {
                return
            }

            let sessions = (try? await self.chatHistoryStore.fetchSessions()) ?? []
            guard !Task.isCancelled else {
                return
            }

            self.sideMenuView.reloadHistory(
                sessions: sessions,
                selectedSessionID: selectedSessionID
            )
        }
    }

    private func selectHistorySession(_ session: ChatSession) {
        guard activeResponseTask == nil else {
            return
        }

        historySelectionTask?.cancel()
        historySelectionTask = Task { [weak self] in
            guard let self else {
                return
            }

            let events = (try? await self.chatHistoryStore.fetchEvents(sessionID: session.id)) ?? []
            guard !Task.isCancelled else {
                return
            }

            self.chatRuntime.loadConversation(session: session, events: events)
            self.renderConversationTimeline(events)
            self.reloadSelectedSystemPrompt()
            self.messagesScrollCoordinator.lockToBottom()
            self.updateRightHeaderButtonState(animated: true)
            self.reloadHistorySessions(selectedSessionID: session.id)
            self.setSideMenuOpen(false, animated: true)
        }
    }

    private func deleteHistorySession(_ session: ChatSession) {
        guard activeResponseTask == nil || session.id != chatRuntime.currentSessionID else {
            return
        }

        historySelectionTask?.cancel()
        historySelectionTask = Task { [weak self] in
            guard let self else {
                return
            }

            try? await self.chatHistoryStore.deleteSession(id: session.id)
            guard !Task.isCancelled else {
                return
            }

            if session.id == self.chatRuntime.currentSessionID {
                self.chatRuntime.resetConversation()
                self.removeChatContent()
                self.reloadSelectedSystemPrompt()
                self.messagesScrollCoordinator.lockToBottom()
                self.updateRightHeaderButtonState(animated: true)
                self.reloadHistorySessions(selectedSessionID: nil)
            } else {
                self.reloadHistorySessions(selectedSessionID: self.chatRuntime.currentSessionID)
            }
        }
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

    private var hasChatContent: Bool {
        !messagesStackView.arrangedSubviews.isEmpty
    }

    private func renderConversationTimeline(_ events: [ChatTimelineEvent]) {
        removeChatContent()

        var currentAssistantView: AssistantResponseTextView?

        func finishCurrentAssistantView() {
            currentAssistantView?.finishStreamingContent()
            currentAssistantView = nil
        }

        func assistantView() -> AssistantResponseTextView {
            if let currentAssistantView {
                return currentAssistantView
            }

            let responseView = makeStoredAssistantResponseView()
            currentAssistantView = responseView
            return responseView
        }

        for event in ChatTimelineEvent.sortedChronologically(events) {
            switch event.kind {
            case let .userMessage(text):
                finishCurrentAssistantView()
                appendStoredUserMessage(id: event.id, text: text, attachments: [])
            case let .userMessageWithAttachments(text, attachments):
                finishCurrentAssistantView()
                appendStoredUserMessage(id: event.id, text: text, attachments: attachments)
            case let .assistantReasoning(text):
                assistantView().appendStoredReasoning(text)
            case let .assistantContent(markdown):
                assistantView().appendStoredContentMarkdown(markdown)
            case let .assistantToolCalls(toolCalls):
                for toolCall in toolCalls {
                    assistantView().appendDisplayPart(.toolEvent(.started(toolCall)))
                }
            case let .toolEvent(event):
                assistantView().appendDisplayPart(.toolEvent(event))
            case .messageRevision:
                continue
            }
        }

        finishCurrentAssistantView()
        mainPageView.layoutIfNeeded()
        scrollMessagesToBottom(animated: false)
    }

    private func appendStoredUserMessage(id: UUID, text: String, attachments: [ChatAttachment]) {
        let bubbleView = SentMessageBubbleView(messageID: id, text: text, attachments: attachments)
        configureSentMessageActions(for: bubbleView)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.setContentHuggingPriority(.required, for: .vertical)
        bubbleView.setContentCompressionResistancePriority(.required, for: .vertical)

        messagesStackView.addArrangedSubview(bubbleView)
        bubbleView.widthAnchor.constraint(
            lessThanOrEqualTo: messagesStackView.widthAnchor,
            multiplier: MessagesLayout.maximumBubbleWidthRatio
        ).isActive = true
    }

    private func configureSentMessageActions(for bubbleView: SentMessageBubbleView) {
        let messageID = bubbleView.messageID
        bubbleView.editHistoryCount = chatRuntime.messageRevisions(for: messageID).count
        bubbleView.onPreviewAttachment = { [weak self] attachment in
            self?.presentAttachmentPreview(for: attachment)
        }
        bubbleView.onResend = { [weak self, messageID] text, attachments in
            self?.resendMessage(
                messageID: messageID,
                text: text,
                attachments: attachments
            )
        }
        bubbleView.onEditAndResend = { [weak self, messageID] text, attachments in
            self?.presentMessageEditor(
                messageID: messageID,
                text: text,
                attachments: attachments
            )
        }
        bubbleView.onShowHistory = { [weak self, messageID] in
            self?.presentMessageRevisionHistory(messageID: messageID)
        }
    }

    private func makeStoredAssistantResponseView() -> AssistantResponseTextView {
        let responseView = AssistantResponseTextView()
        responseView.translatesAutoresizingMaskIntoConstraints = false
        responseView.setContentHuggingPriority(.required, for: .vertical)
        responseView.setContentCompressionResistancePriority(.required, for: .vertical)
        messagesStackView.addArrangedSubview(responseView)
        responseView.widthAnchor.constraint(
            equalTo: messagesStackView.widthAnchor
        ).isActive = true
        return responseView
    }

    private func removeChatContent() {
        let messageViews = messagesStackView.arrangedSubviews
        guard !messageViews.isEmpty else {
            return
        }

        messageViews.forEach {
            messagesStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        mainPageView.layoutIfNeeded()
        scrollMessagesToBottom(animated: false)
    }

    private func updateRightHeaderButtonState(animated: Bool) {
        let isGeneratingResponse = activeResponseTask != nil
        let systemName = hasChatContent
            ? HeaderLayout.newConversationButtonSystemName
            : HeaderLayout.emptyConversationButtonSystemName
        let accessibilityLabel = isGeneratingResponse
            ? String(localized: .chatGeneratingResponse)
            : (hasChatContent ? String(localized: .chatNewChat) : String(localized: .chatLayout))
        let image = isGeneratingResponse
            ? nil
            : UIImage(
                systemName: systemName,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: HeaderLayout.iconPointSize,
                    weight: .semibold
                )
            )

        let update = {
            var configuration = self.rightHeaderButton.configuration
            configuration?.image = image
            configuration?.showsActivityIndicator = isGeneratingResponse
            self.rightHeaderButton.configuration = configuration
            self.rightHeaderButton.accessibilityLabel = accessibilityLabel
            self.rightHeaderButton.isEnabled = true
        }

        guard animated,
              view.window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            update()
            return
        }

        UIView.transition(
            with: rightHeaderButton,
            duration: HeaderLayout.moduleSelectionTextAnimationDuration,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction, .allowAnimatedContent],
            animations: update
        )
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

    private final class MessagesContentView: UIView {
        var onDidLayoutSubviews: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onDidLayoutSubviews?()
        }
    }

    private final class MessagesScrollCoordinator {
        private enum Metrics {
            static let layoutEpsilon: CGFloat = 0.5
        }

        private weak var scrollView: UIScrollView?
        private let bottomLockTolerance: CGFloat
        private let autoScrollAnimationDuration: TimeInterval

        private var isBottomLocked = true
        private var hasRecordedLayout = false
        private var lastContentSize: CGSize = .zero
        private var lastBoundsSize: CGSize = .zero
        private var lastAdjustedInsets: UIEdgeInsets = .zero
        private var lastBottomOffsetY: CGFloat = 0.0
        private var animationGeneration = 0

        init(
            scrollView: UIScrollView,
            bottomLockTolerance: CGFloat,
            autoScrollAnimationDuration: TimeInterval
        ) {
            self.scrollView = scrollView
            self.bottomLockTolerance = bottomLockTolerance
            self.autoScrollAnimationDuration = autoScrollAnimationDuration
        }

        func lockToBottom() {
            isBottomLocked = true
        }

        func scrollToBottom(hostView: UIView?, animated: Bool) {
            guard let scrollView else {
                return
            }

            isBottomLocked = true
            setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: bottomOffsetY()),
                hostView: hostView,
                animated: animated
            )
            recordCurrentLayout()
        }

        func reconcileAfterLayout(hostView: UIView?, allowsAnimatedFollow: Bool) {
            guard let scrollView else {
                return
            }

            let currentBottomOffsetY = bottomOffsetY()
            let contentHeightIncreased = hasRecordedLayout
                && scrollView.contentSize.height - lastContentSize.height > Metrics.layoutEpsilon
            let bottomMovedDown = hasRecordedLayout
                && currentBottomOffsetY - lastBottomOffsetY > Metrics.layoutEpsilon
            let viewportChanged = hasRecordedLayout
                && (
                    abs(scrollView.bounds.size.height - lastBoundsSize.height) > Metrics.layoutEpsilon
                    || abs(scrollView.adjustedContentInset.top - lastAdjustedInsets.top) > Metrics.layoutEpsilon
                    || abs(scrollView.adjustedContentInset.bottom - lastAdjustedInsets.bottom) > Metrics.layoutEpsilon
                )

            if isBottomLocked {
                let shouldAnimate = allowsAnimatedFollow
                    && contentHeightIncreased
                    && bottomMovedDown
                    && !viewportChanged
                    && !isUserInteracting
                setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: currentBottomOffsetY),
                    hostView: hostView,
                    animated: shouldAnimate
                )
            } else {
                clampContentOffsetIfNeeded()
            }

            recordCurrentLayout()
        }

        func userWillBeginDragging() {
            isBottomLocked = false
            cancelInFlightScrollAnimation()
        }

        func userDidScroll() {
            isBottomLocked = isScrolledToBottom()
        }

        func userWillEndDragging(targetOffsetY: CGFloat) {
            isBottomLocked = isScrolledToBottom(offsetY: targetOffsetY)
        }

        func userDidFinishScrolling() {
            isBottomLocked = isScrolledToBottom()
        }

        private func setContentOffset(
            _ contentOffset: CGPoint,
            hostView: UIView?,
            animated: Bool
        ) {
            guard let scrollView else {
                return
            }

            guard animated,
                  hostView?.window != nil,
                  !UIAccessibility.isReduceMotionEnabled,
                  abs(scrollView.contentOffset.y - contentOffset.y) > Metrics.layoutEpsilon else {
                animationGeneration += 1
                scrollView.setContentOffset(contentOffset, animated: false)
                return
            }

            animationGeneration += 1
            let generation = animationGeneration
            UIView.animate(
                withDuration: autoScrollAnimationDuration,
                delay: 0.0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
            ) {
                scrollView.contentOffset = contentOffset
            } completion: { [weak self, weak scrollView] _ in
                guard let self,
                      let scrollView,
                      generation == self.animationGeneration,
                      self.isBottomLocked,
                      !self.isUserInteracting else {
                    return
                }

                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: self.bottomOffsetY()),
                    animated: false
                )
                self.recordCurrentLayout()
            }
        }

        private func cancelInFlightScrollAnimation() {
            animationGeneration += 1
            scrollView?.layer.removeAnimation(forKey: "bounds")
        }

        private var isUserInteracting: Bool {
            guard let scrollView else {
                return false
            }

            return scrollView.isTracking
                || scrollView.isDragging
                || scrollView.isDecelerating
        }

        private func isScrolledToBottom(offsetY: CGFloat? = nil) -> Bool {
            guard let scrollView else {
                return true
            }

            let candidateOffsetY = offsetY ?? scrollView.contentOffset.y
            return candidateOffsetY >= bottomOffsetY() - bottomLockTolerance
        }

        private func bottomOffsetY() -> CGFloat {
            contentOffsetBounds().maximum
        }

        private func contentOffsetBounds() -> (minimum: CGFloat, maximum: CGFloat) {
            guard let scrollView else {
                return (0.0, 0.0)
            }

            let adjustedInsets = scrollView.adjustedContentInset
            let minimumOffsetY = -adjustedInsets.top
            let maximumOffsetY = max(
                minimumOffsetY,
                scrollView.contentSize.height - scrollView.bounds.height + adjustedInsets.bottom
            )

            return (minimumOffsetY, maximumOffsetY)
        }

        private func clampContentOffsetIfNeeded() {
            guard let scrollView,
                  !isUserInteracting else {
                return
            }

            let bounds = contentOffsetBounds()
            let currentOffsetY = scrollView.contentOffset.y
            let clampedOffsetY = min(max(currentOffsetY, bounds.minimum), bounds.maximum)
            guard abs(currentOffsetY - clampedOffsetY) > CGFloat.ulpOfOne else {
                return
            }

            animationGeneration += 1
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: clampedOffsetY),
                animated: false
            )
        }

        private func recordCurrentLayout() {
            guard let scrollView else {
                return
            }

            hasRecordedLayout = true
            lastContentSize = scrollView.contentSize
            lastBoundsSize = scrollView.bounds.size
            lastAdjustedInsets = scrollView.adjustedContentInset
            lastBottomOffsetY = bottomOffsetY()
        }
    }

}

extension ChatViewController: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        attachmentPreviewItem == nil ? 0 : 1
    }

    func previewController(
        _ controller: QLPreviewController,
        previewItemAt index: Int
    ) -> any QLPreviewItem {
        guard let attachmentPreviewItem else {
            fatalError("Attachment preview requested without a preview item.")
        }

        return attachmentPreviewItem
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        attachmentPreviewItem = nil
    }
}

extension ChatViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === messagesScrollView else {
            return
        }

        messagesScrollCoordinator.userWillBeginDragging()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === messagesScrollView,
              scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else {
            return
        }

        messagesScrollCoordinator.userDidScroll()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView === messagesScrollView else {
            return
        }

        messagesScrollCoordinator.userWillEndDragging(targetOffsetY: targetContentOffset.pointee.y)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === messagesScrollView,
              !decelerate else {
            return
        }

        messagesScrollCoordinator.userDidFinishScrolling()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === messagesScrollView else {
            return
        }

        messagesScrollCoordinator.userDidFinishScrolling()
    }
}

extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)

        guard let image = info[.originalImage] as? UIImage else { return }
        importCapturedImage(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func importCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            presentAttachmentError(String(localized: .chatAttachmentPhotoEncodingFailed))
            return
        }

        let timestamp = Self.timestampFilenameFormatter.string(from: Date())
        let filename = "\(String(localized: .chatAttachmentPhotoFilenameFormat(timestamp))).jpg"
        do {
            let attachment = try attachmentStore.store(
                data: data,
                filename: filename,
                kind: .image,
                contentType: "image/jpeg",
                preferredExtension: "jpg"
            )
            appendPendingAttachments([attachment])
        } catch {
            presentAttachmentError(error.localizedDescription)
        }
    }

    private static let timestampFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

extension ChatViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else { return }

        let providers = results.map(\.itemProvider)

        Task { [weak self] in
            var attachments: [ChatAttachment] = []
            for (index, provider) in providers.enumerated() {
                guard provider.canLoadObject(ofClass: UIImage.self) else {
                    continue
                }

                let image: UIImage? = await withCheckedContinuation { continuation in
                    provider.loadObject(ofClass: UIImage.self) { object, _ in
                        continuation.resume(returning: object as? UIImage)
                    }
                }

                guard let image,
                      let data = image.jpegData(compressionQuality: 0.9),
                      let self else {
                    continue
                }

                let suggestedName = provider.suggestedName.flatMap { name -> String? in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : "\(trimmed).jpg"
                } ?? "\(String(localized: .chatAttachmentImageFilenameFormat(index + 1))).jpg"

                if let attachment = try? self.attachmentStore.store(
                    data: data,
                    filename: suggestedName,
                    kind: .image,
                    contentType: "image/jpeg",
                    preferredExtension: "jpg"
                ) {
                    attachments.append(attachment)
                }
            }

            let importedAttachments = attachments
            await MainActor.run { [weak self] in
                self?.appendPendingAttachments(importedAttachments)
            }
        }
    }
}

extension ChatViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        var attachments: [ChatAttachment] = []
        for url in urls {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer {
                if needsScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let kind: ChatAttachment.Kind
            if let type = UTType(filenameExtension: url.pathExtension),
               type.conforms(to: .image) {
                kind = .image
            } else {
                kind = .file
            }

            do {
                let attachment = try attachmentStore.importFile(
                    from: url,
                    suggestedFilename: url.lastPathComponent,
                    kind: kind
                )
                attachments.append(attachment)
            } catch {
                presentAttachmentError(error.localizedDescription)
            }
        }
        appendPendingAttachments(attachments)
    }
}

private final class MessageEditViewController: UIViewController, UITextViewDelegate {
    private enum Metrics {
        static let horizontalInset: CGFloat = 16.0
        static let topInset: CGFloat = 16.0
        static let bottomInset: CGFloat = 16.0
        static let textInset: CGFloat = 12.0
        static let cornerRadius: CGFloat = 14.0
        static let minimumTextHeight: CGFloat = 180.0
    }

    private let initialText: String
    private let allowsEmptyText: Bool
    private let textView = UITextView()
    private var sendButtonItem: UIBarButtonItem?

    var onSubmit: ((String) -> Void)?

    init(text: String, allowsEmptyText: Bool) {
        initialText = text
        self.allowsEmptyText = allowsEmptyText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        initialText = ""
        allowsEmptyText = false
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavigationItem()
        configureTextView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        textView.becomeFirstResponder()
    }

    func textViewDidChange(_ textView: UITextView) {
        updateSendAvailability()
    }

    private func configureNavigationItem() {
        title = String(localized: .chatEditMessage)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonPressed)
        )
        let sendItem = UIBarButtonItem(
            title: String(localized: .generalSend),
            style: .prominent,
            target: self,
            action: #selector(sendButtonPressed)
        )
        navigationItem.rightBarButtonItem = sendItem
        sendButtonItem = sendItem
        updateSendAvailability()
    }

    private func configureTextView() {
        view.backgroundColor = .clear

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .secondarySystemBackground
        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.text = initialText
        textView.textContainerInset = UIEdgeInsets(
            top: Metrics.textInset,
            left: Metrics.textInset,
            bottom: Metrics.textInset,
            right: Metrics.textInset
        )
        textView.textContainer.lineFragmentPadding = 0.0
        textView.layer.cornerRadius = Metrics.cornerRadius
        textView.layer.cornerCurve = .continuous
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Metrics.topInset
            ),
            textView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            textView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            textView.bottomAnchor.constraint(
                equalTo: view.keyboardLayoutGuide.topAnchor,
                constant: -Metrics.bottomInset
            ),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumTextHeight)
        ])
        updateSendAvailability()
    }

    private func updateSendAvailability() {
        let trimmedText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        sendButtonItem?.isEnabled = allowsEmptyText || !trimmedText.isEmpty
    }

    @objc private func cancelButtonPressed() {
        dismiss(animated: true)
    }

    @objc private func sendButtonPressed() {
        let trimmedText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsEmptyText || !trimmedText.isEmpty else {
            return
        }

        onSubmit?(trimmedText)
    }
}

private final class MessageRevisionHistoryViewController: UITableViewController {
    private enum ReuseIdentifier {
        static let revisionCell = "MessageRevisionHistoryCell"
    }

    private let revisions: [ChatMessageRevision]
    var onSelectRevision: ((ChatMessageRevision) -> Void)?

    init(revisions: [ChatMessageRevision]) {
        self.revisions = revisions
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        revisions = []
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: .generalHistory)
        view.backgroundColor = .clear
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonPressed)
        )
        tableView.register(MessageRevisionHistoryCell.self, forCellReuseIdentifier: ReuseIdentifier.revisionCell)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        revisions.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let revision = revisions[indexPath.row]
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ReuseIdentifier.revisionCell,
            for: indexPath
        )
        (cell as? MessageRevisionHistoryCell)?.configure(with: revision)
        cell.accessoryType = .none
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectRevision?(revisions[indexPath.row])
    }

    @objc private func doneButtonPressed() {
        dismiss(animated: true)
    }
}

private final class MessageRevisionHistoryCell: UITableViewCell {
    private enum Metrics {
        static let horizontalInset: CGFloat = 16.0
        static let verticalInset: CGFloat = 10.0
        static let rowSpacing: CGFloat = 4.0
        static let subtitleSpacing: CGFloat = 8.0
        static let tagCornerRadius: CGFloat = 7.0
    }

    private let titleLabel = UILabel()
    private let subtitleStackView = UIStackView()
    private let dateLabel = UILabel()
    private let countTagLabel = MessageRevisionCountTagLabel()
    private let stackView = UIStackView()

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

        titleLabel.text = nil
        dateLabel.text = nil
        countTagLabel.text = nil
        countTagLabel.isHidden = true
    }

    func configure(with revision: ChatMessageRevision) {
        titleLabel.text = revision.historyTitle
        dateLabel.text = revision.historySubtitle

        let followUpCount = revision.followUpUserMessageCount
        countTagLabel.text = "+\(followUpCount)"
        countTagLabel.isHidden = followUpCount == 0
    }

    private func configure() {
        selectionStyle = .default

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = .secondaryLabel
        dateLabel.numberOfLines = 1
        dateLabel.lineBreakMode = .byTruncatingTail
        dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countTagLabel.font = .preferredFont(forTextStyle: .caption1)
        countTagLabel.adjustsFontForContentSizeCategory = true
        countTagLabel.textColor = .secondaryLabel
        countTagLabel.textAlignment = .center
        countTagLabel.backgroundColor = .tertiarySystemFill
        countTagLabel.layer.cornerRadius = Metrics.tagCornerRadius
        countTagLabel.layer.cornerCurve = .continuous
        countTagLabel.clipsToBounds = true
        countTagLabel.numberOfLines = 1
        countTagLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countTagLabel.setContentHuggingPriority(.required, for: .horizontal)

        subtitleStackView.axis = .horizontal
        subtitleStackView.alignment = .center
        subtitleStackView.spacing = Metrics.subtitleSpacing
        subtitleStackView.translatesAutoresizingMaskIntoConstraints = false
        subtitleStackView.addArrangedSubview(dateLabel)
        subtitleStackView.addArrangedSubview(countTagLabel)

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Metrics.rowSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleStackView)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: Metrics.verticalInset
            ),
            stackView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            stackView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            stackView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Metrics.verticalInset
            )
        ])
    }
}

private final class MessageRevisionCountTagLabel: UILabel {
    private let textInsets = UIEdgeInsets(top: 2.0, left: 7.0, bottom: 2.0, right: 7.0)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingSize = super.sizeThatFits(
            CGSize(
                width: max(0.0, size.width - textInsets.left - textInsets.right),
                height: max(0.0, size.height - textInsets.top - textInsets.bottom)
            )
        )
        return CGSize(
            width: fittingSize.width + textInsets.left + textInsets.right,
            height: fittingSize.height + textInsets.top + textInsets.bottom
        )
    }
}

private extension ChatMessageRevision {
    var historyTitle: String {
        let title = userMessageText.singleLineHistoryTitle
        guard !title.isEmpty else {
            return firstAttachmentTitle ?? String(localized: .chatAttachment)
        }

        return title
    }

    var historySubtitle: String {
        Self.historyDateFormatter.string(from: archivedAt)
    }

    var followUpUserMessageCount: Int {
        var hasSeenAnchorMessage = false
        var count = 0
        for event in events {
            switch event.kind {
            case .userMessage,
                 .userMessageWithAttachments:
                if hasSeenAnchorMessage {
                    count += 1
                } else {
                    hasSeenAnchorMessage = true
                }
            case .assistantReasoning,
                 .assistantContent,
                 .assistantToolCalls,
                 .toolEvent:
                continue
            }
        }
        return count
    }

    private var userMessageText: String {
        for event in events {
            switch event.kind {
            case let .userMessage(text),
                 let .userMessageWithAttachments(text, _):
                return text
            case .assistantReasoning,
                 .assistantContent,
                 .assistantToolCalls,
                 .toolEvent:
                continue
            }
        }
        return ""
    }

    private var firstAttachmentTitle: String? {
        for event in events {
            guard case let .userMessageWithAttachments(_, attachments) = event.kind else {
                continue
            }

            let filename = attachments.first?.filename
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return filename.isEmpty ? nil : filename
        }

        return nil
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension String {
    var singleLineHistoryTitle: String {
        components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class AttachmentPreviewItem: NSObject, QLPreviewItem {
    private let url: URL
    private let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        super.init()
    }

    var previewItemURL: URL? {
        url
    }

    var previewItemTitle: String? {
        title
    }
}
