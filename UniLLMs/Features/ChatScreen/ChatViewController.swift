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
        static var defaultModuleSelectionTitle: String { String(localized: .chatSelectModel) }
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
        static let attachmentThumbnailPointSize: CGFloat = 110.0
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
        static let sentAttachmentThumbnailPointSize: CGFloat = 48.0
    }

    private enum SideMenuLayout {
        static let revealRatio: CGFloat = 0.8
        static let pageOpacity: CGFloat = 0.72
        static let animationDuration: TimeInterval = 0.44
        static let animationDampingRatio: CGFloat = 0.86
        static let shadowOpacity: Float = 0.18
        static let shadowRadius: CGFloat = 28.0
        static let shadowOffset = CGSize(width: -10.0, height: 0.0)
        static let pageCornerRadius: CGFloat = 32.0
    }

    private typealias ActiveAssistantResponseContext = ChatActiveAssistantResponseContext<
        SentMessageBubbleView,
        AssistantResponseTextView
    >

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
        presentation: .make(
            isGeneratingResponse: false,
            isPrivateModeEnabled: false,
            hasChatContent: false
        )
    )
    private let messagesScrollView = UIScrollView()
    private lazy var messagesScrollCoordinator = MessagesScrollCoordinator(
        scrollView: messagesScrollView,
        bottomLockTolerance: MessagesLayout.bottomLockTolerance,
        autoScrollAnimationDuration: MessagesLayout.autoScrollAnimationDuration
    )
    private lazy var existingMessagesShiftAnimator: ChatExistingMessagesShiftAnimator = {
        ChatExistingMessagesShiftAnimator(
            hostView: view,
            referenceView: mainPageView,
            scrollView: messagesScrollView,
            stackView: messagesStackView,
            visibilityMargin: MessagesLayout.existingMessageShiftVisibilityMargin,
            animationDuration: MessagesLayout.sendAnimationDuration,
            dampingRatio: MessagesLayout.sendAnimationDampingRatio
        )
    }()
    private lazy var sentMessageSendAnimator: ChatSentMessageSendAnimator = {
        ChatSentMessageSendAnimator(
            hostView: view,
            referenceView: mainPageView,
            animationDuration: MessagesLayout.sendAnimationDuration,
            dampingRatio: MessagesLayout.sendAnimationDampingRatio,
            attachmentDisplayBuilder: { [weak self] attachments in
                self?.attachmentPreviewDisplayBuilder.cachedDisplays(
                    for: attachments,
                    thumbnailMaxPointSize: MessagesLayout.sentAttachmentThumbnailPointSize
                )
                    ?? ChatAttachmentPreviewDisplay.placeholders(for: attachments)
            }
        )
    }()
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
    private lazy var messageStackAdapter: ChatMessageStackAdapter = {
        ChatMessageStackAdapter(
            stackView: messagesStackView,
            maximumBubbleWidthRatio: MessagesLayout.maximumBubbleWidthRatio,
            attachmentDisplayBuilder: { [weak self] attachments in
                self?.attachmentPreviewDisplayBuilder.cachedDisplays(
                    for: attachments,
                    thumbnailMaxPointSize: MessagesLayout.sentAttachmentThumbnailPointSize
                )
                    ?? ChatAttachmentPreviewDisplay.placeholders(for: attachments)
            }
        ) { [weak self] bubbleView, messageID in
            self?.configureSentMessageActions(for: bubbleView, messageID: messageID)
        }
    }()
    private var messagesContentMinimumHeightConstraint: NSLayoutConstraint!
    private let composerView = GlassComposerBarView()
    private var composerLeadingConstraint: NSLayoutConstraint!
    private var composerTrailingConstraint: NSLayoutConstraint!
    private var composerKeyboardBottomConstraint: NSLayoutConstraint!
    private var composerRestingBottomConstraint: NSLayoutConstraint!
    private var keyboardObservation: NSObjectProtocol?
    private var selectedModelSelectionObservation: NSObjectProtocol?
    private var chatHistoryObservation: NSObjectProtocol?
    private var attachmentCleanupObservation: NSObjectProtocol?
    private var attachmentThumbnailMemoryWarningObservation: NSObjectProtocol?
    private var systemPromptObservation: NSObjectProtocol?
    private var isKeyboardVisible = false
    private var isSideMenuOpen = false
    private var selectedModelSelection: ChatModelSelection?
    private let responseStreamController = ChatResponseStreamController()
    private lazy var assistantResponseMutationAdapter = ChatAssistantResponseMutationAdapter<AssistantResponseTextView>(
        invalidateLayout: { [weak self] in
            self?.messagesStackView.setNeedsLayout()
            self?.messagesContentView.setNeedsLayout()
            self?.messagesScrollView.setNeedsLayout()
            self?.mainPageView.setNeedsLayout()
        }
    )
    private lazy var responseActivationPresentationAdapter = ChatResponseActivationPresentationAdapter(
        setComposerSendingEnabled: { [weak self] isEnabled in
            self?.composerView.isSendingEnabled = isEnabled
        },
        setComposerStreamingActive: { [weak self] isActive, animated in
            self?.composerView.setStreamingResponseActive(isActive, animated: animated)
        },
        setBackgroundFlowing: { [weak self] isFlowing, animated in
            self?.backgroundView.setFlowing(isFlowing, animated: animated)
        },
        updateHeader: { [weak self] animated in
            self?.updateRightHeaderButtonState(animated: animated)
        }
    )
    private lazy var assistantResponseFailurePresentationWorkflow = makeAssistantResponseFailurePresentationWorkflow()
    private lazy var historyWorkflowController = ChatHistoryWorkflowController(historyStore: chatHistoryStore)
    private lazy var conversationResetWorkflow = makeConversationResetWorkflow()
    private lazy var historyPresentationWorkflow = makeHistoryPresentationWorkflow()
    private lazy var messageRevisionSwitchWorkflow = makeMessageRevisionSwitchWorkflow()
    private lazy var messageResendWorkflow = makeMessageResendWorkflow()
    private lazy var messageActionPresentationWorkflow = makeMessageActionPresentationWorkflow()
    private weak var activeResponseView: AssistantResponseTextView?
    private var activeResponseContext: ActiveAssistantResponseContext?
    private let attachmentStore = ChatAttachmentStore.shared
    private lazy var attachmentThumbnailProvider = ChatAttachmentThumbnailProvider(
        scale: { [weak self] in
            self?.view.window?.windowScene?.screen.scale
                ?? self?.traitCollection.displayScale
                ?? 2.0
        }
    )
    private lazy var attachmentPreviewDisplayBuilder = ChatAttachmentPreviewDisplayBuilder(
        thumbnailProvider: attachmentThumbnailProvider
    )
    private lazy var attachmentPreviewDisplayPipeline = ChatAttachmentPreviewDisplayPipeline(
        displayBuilder: attachmentPreviewDisplayBuilder,
        asyncLoader: ChatAttachmentAsyncThumbnailLoader(
            fileURL: { [attachmentStore] attachment in
                attachmentStore.fileURL(for: attachment)
            },
            scale: { [weak self] in
                self?.view.window?.windowScene?.screen.scale
                    ?? self?.traitCollection.displayScale
                    ?? 2.0
            }
        )
    )
    private lazy var sentMessageAttachmentDisplayUpdater = ChatMessageAttachmentDisplayUpdater(
        messageStackAdapter: messageStackAdapter,
        attachmentPreviewDisplayPipeline: attachmentPreviewDisplayPipeline,
        thumbnailMaxPointSize: MessagesLayout.sentAttachmentThumbnailPointSize
    )
    private lazy var attachmentImporter = ChatAttachmentImporter(attachmentStore: attachmentStore)
    private lazy var systemPromptSelectionWorkflow = makeSystemPromptSelectionWorkflow()
    private lazy var composerAddWorkflow = makeComposerAddWorkflow()
    private lazy var idleModalPresenter = makeIdleModalPresenter()
    private lazy var attachmentPreviewController = ChatAttachmentPreviewController { [attachmentStore] attachment in
        attachmentStore.fileURL(for: attachment)
    }
    private lazy var attachmentPreviewWorkflow = makeAttachmentPreviewWorkflow()
    private lazy var composerAttachmentWorkflow = makeComposerAttachmentWorkflow()
    private lazy var attachmentAcquisitionWorkflow = makeAttachmentAcquisitionWorkflow()
    private lazy var outgoingMessageTransactionWorkflow = makeOutgoingMessageTransactionWorkflow()
    private lazy var outgoingTurnPreparationWorkflow = makeOutgoingTurnPreparationWorkflow()
    private lazy var composerSendWorkflow = makeComposerSendWorkflow()

    func configure(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
        systemPromptSelectionWorkflow = makeSystemPromptSelectionWorkflow()
        outgoingTurnPreparationWorkflow = makeOutgoingTurnPreparationWorkflow()
        if isViewLoaded {
            installHistoryPersistenceFailureHandler()
        }
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
        installAttachmentThumbnailCacheObservers()
        installHistoryPersistenceFailureHandler()
        installSystemPromptObserver()
        reloadSelectedModelSelection(animated: false)
        reloadSelectedSystemPrompt()
        reloadHistorySessions(selectedSessionID: nil)
    }

    deinit {
        let responseStreamController = responseStreamController
        let historyWorkflowController = historyWorkflowController
        let attachmentAcquisitionWorkflow = attachmentAcquisitionWorkflow
        let composerAttachmentWorkflow = composerAttachmentWorkflow
        let attachmentPreviewDisplayPipeline = attachmentPreviewDisplayPipeline
        let chatRuntime = chatRuntime
        Task { @MainActor in
            responseStreamController.cancel()
            historyWorkflowController.cancel()
            attachmentAcquisitionWorkflow.cancel()
            attachmentPreviewDisplayPipeline.cancelAll()
            if chatRuntime.isPrivacyModeEnabled {
                composerAttachmentWorkflow.discardPrivateModeAttachments(
                    including: chatRuntime.currentConversationAttachments
                )
            }
        }
        if let keyboardObservation {
            NotificationCenter.default.removeObserver(keyboardObservation)
        }
        if let selectedModelSelectionObservation {
            NotificationCenter.default.removeObserver(selectedModelSelectionObservation)
        }
        if let chatHistoryObservation {
            NotificationCenter.default.removeObserver(chatHistoryObservation)
        }
        if let attachmentCleanupObservation {
            NotificationCenter.default.removeObserver(attachmentCleanupObservation)
        }
        if let attachmentThumbnailMemoryWarningObservation {
            NotificationCenter.default.removeObserver(attachmentThumbnailMemoryWarningObservation)
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
        rightHeaderButton.addTarget(self, action: #selector(rightHeaderButtonPressed), for: .touchUpInside)
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
            self?.appendSentMessage(using: transition) ?? false
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
            self?.composerAttachmentWorkflow.removePendingAttachment(id: id)
        }
        composerView.onPreviewAttachment = { [weak self] id in
            self?.composerAttachmentWorkflow.previewPendingAttachment(id: id)
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
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let keyboardFrameChange = ChatKeyboardFrameChange(
                    notification: notification,
                    screenBounds: self.view.window?.windowScene?.screen.bounds ?? self.view.bounds
                  ) else {
                return
            }

            self.isKeyboardVisible = keyboardFrameChange.isKeyboardVisible
            self.updateComposerLayout(
                animated: true,
                duration: keyboardFrameChange.animationDuration,
                options: keyboardFrameChange.animationOptions
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
        idleModalPresenter.presentIfIdle {
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
            return ChatPageSheetPresentation.wrapInNavigationController(
                rootViewController: modelSelectionViewController
            )
        }
    }

    @objc private func presentSettings() {
        idleModalPresenter.presentIfIdle {
            let settingsViewController = SettingsViewController(dependencies: dependencies)
            return ChatPageSheetPresentation.wrapInNavigationController(
                rootViewController: settingsViewController
            )
        }
    }

    @objc private func rightHeaderButtonPressed() {
        switch ChatHeaderActionPolicy.action(
            isResponseActive: responseStreamController.isActive,
            hasChatContent: hasChatContent
        ) {
        case .startNewConversation:
            startNewConversation()
        case .togglePrivacyMode:
            togglePrivacyMode()
        case .ignore:
            return
        }
    }

    private func startNewConversation() {
        guard ChatHeaderActionPolicy.action(
            isResponseActive: responseStreamController.isActive,
            hasChatContent: hasChatContent
        ) == .startNewConversation else {
            return
        }

        conversationResetWorkflow.perform(
            .startNewConversation(isPrivacyModeEnabled: chatRuntime.isPrivacyModeEnabled)
        )
    }

    private func togglePrivacyMode() {
        guard ChatHeaderActionPolicy.action(
            isResponseActive: responseStreamController.isActive,
            hasChatContent: hasChatContent
        ) == .togglePrivacyMode else {
            return
        }

        conversationResetWorkflow.perform(
            .togglePrivacyMode(isPrivacyModeEnabled: chatRuntime.isPrivacyModeEnabled)
        )
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
        let geometry = ChatSideMenuPageGeometry.make(
            isOpen: isSideMenuOpen,
            pageWidth: view.bounds.width,
            revealRatio: SideMenuLayout.revealRatio,
            openPageOpacity: SideMenuLayout.pageOpacity,
            openCornerRadius: SideMenuLayout.pageCornerRadius,
            openShadowOpacity: SideMenuLayout.shadowOpacity
        )

        mainPageContainerView.transform = CGAffineTransform(
            translationX: geometry.pageTranslationX,
            y: 0.0
        )
        mainPageContainerView.layer.shadowOpacity = geometry.shadowOpacity
        mainPageView.alpha = geometry.pageAlpha
        mainPageView.layer.cornerRadius = geometry.pageCornerRadius
        mainPageView.layer.masksToBounds = geometry.pageMasksToBounds
        sideMenuView.alpha = geometry.sideMenuAlpha
        sideMenuDismissControl.alpha = geometry.dismissControlAlpha
        updateMainPageShadowPath(cornerRadius: geometry.pageCornerRadius)
    }

    private func updateComposerBottomConstraint() {
        let shouldTrackKeyboard = !isSideMenuOpen
        composerKeyboardBottomConstraint.isActive = shouldTrackKeyboard
        composerRestingBottomConstraint.isActive = !shouldTrackKeyboard
    }

    private func presentComposerAddSheet() {
        idleModalPresenter.presentIfIdle {
            composerAddWorkflow.makeAddSheetViewController()
        }
    }

    private func presentSystemPromptSelection() {
        idleModalPresenter.presentIfIdle(endEditing: false) {
            systemPromptSelectionWorkflow.makeSelectionViewController()
        }
    }

    private func presentAttachmentError(_ message: String) {
        presentChatAlert(title: nil, message: message)
    }

    private func presentChatHistoryPersistenceError(_ error: Error) {
        presentChatAlert(
            title: String(localized: .chatHistorySaveFailed),
            message: error.localizedDescription
        )
    }

    private func presentChatAlert(title: String?, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: .generalOk), style: .default))
        present(alert, animated: true)
    }

    private func selectSystemPrompt(_ prompt: SystemPromptRecord) {
        systemPromptSelectionWorkflow.select(prompt)
    }

    private func clearSelectedSystemPrompt() {
        systemPromptSelectionWorkflow.clearSelection()
    }

    private func presentMessageEditor(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        messageActionPresentationWorkflow.presentEditor(
            messageID: messageID,
            text: text,
            attachments: attachments
        )
    }

    private func presentMessageRevisionHistory(messageID: UUID) {
        messageActionPresentationWorkflow.presentRevisionHistory(messageID: messageID)
    }

    private func switchToMessageRevision(
        messageID: UUID,
        revisionID: UUID
    ) {
        messageRevisionSwitchWorkflow.switchRevision(
            messageID: messageID,
            revisionID: revisionID
        )
    }

    private func resendEditedMessage(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        messageResendWorkflow.resendEditedMessage(
            messageID: messageID,
            text: text,
            attachments: attachments
        )
    }

    private func resendMessage(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        messageResendWorkflow.resendMessage(
            messageID: messageID,
            text: text,
            attachments: attachments
        )
    }

    private func presentMessageActionFailure(_ reason: ChatMessageActionPolicy.FailureReason) {
        let presentation = ChatMessageActionFailurePresentation.make(reason: reason)
        presentAttachmentError(presentation.message.localizedString)
    }

    private func loadSentMessageAttachmentDisplays(
        messageID: UUID,
        attachments: [ChatAttachment]
    ) {
        sentMessageAttachmentDisplayUpdater.loadDisplays(
            messageID: messageID,
            attachments: attachments
        )
    }

    private func refreshComposerSystemPromptPreview() {
        systemPromptSelectionWorkflow.reloadComposerDisplay()
    }

    private func makeAssistantResponseFailurePresentationWorkflow() -> ChatAssistantResponseFailurePresentationWorkflow {
        ChatAssistantResponseFailurePresentationWorkflow(
            cancelMessageAttachmentDisplays: { [weak self] messageID in
                self?.attachmentPreviewDisplayPipeline.cancel(scope: .message(messageID))
            },
            removeViews: { [weak self] views in
                self?.messageStackAdapter.removeViews(views)
            },
            restoreComposerDraft: { [weak self] text, attachments in
                self?.composerAttachmentWorkflow.append(attachments)
                self?.composerView.setMessageText(text)
            },
            presentError: { [weak self] message in
                self?.presentAttachmentError(message)
            },
            setResponseError: { [weak self] message, responseView in
                self?.assistantResponseMutationAdapter.setError(message, in: responseView)
            },
            invalidateRemovedViewsLayout: { [weak self] in
                self?.messagesStackView.setNeedsLayout()
                self?.messagesContentView.setNeedsLayout()
                self?.messagesScrollView.setNeedsLayout()
                self?.mainPageView.setNeedsLayout()
            },
            reconcileAfterRemovedViews: { [weak self] in
                self?.updateMessagesContentOffsetAfterLayoutChange(allowsAnimatedFollow: false)
            }
        )
    }

    private func makeHistoryPresentationWorkflow() -> ChatHistoryPresentationWorkflow {
        ChatHistoryPresentationWorkflow(
            isPrivacyModeEnabled: { [weak self] in
                self?.chatRuntime.isPrivacyModeEnabled ?? false
            },
            clearPendingAttachments: { [weak self] deleteFiles in
                self?.composerAttachmentWorkflow.clearPendingAttachments(deleteFiles: deleteFiles)
            },
            loadConversation: { [weak self] session, events in
                self?.chatRuntime.loadConversation(session: session, events: events) ?? []
            },
            resetCurrentConversation: { [weak self] in
                self?.conversationResetWorkflow.perform(.deleteCurrentHistorySession)
            },
            discardPrivateModeAttachments: { [weak self] attachments in
                self?.composerAttachmentWorkflow.discardPrivateModeAttachments(including: attachments)
            },
            renderConversationTimeline: { [weak self] events in
                self?.renderConversationTimeline(events)
            },
            removeChatContent: { [weak self] in
                self?.removeChatContent()
            },
            reloadSelectedSystemPrompt: { [weak self] in
                self?.reloadSelectedSystemPrompt()
            },
            lockMessagesToBottom: { [weak self] in
                self?.messagesScrollCoordinator.lockToBottom()
            },
            updateHeader: { [weak self] in
                self?.updateRightHeaderButtonState(animated: true)
            },
            confirmPendingSessionSelection: { [weak self] sessionID in
                self?.sideMenuView.confirmPendingSessionSelection(sessionID)
            },
            reloadHistorySessions: { [weak self] selectedSessionID in
                self?.reloadHistorySessions(selectedSessionID: selectedSessionID)
            },
            closeSideMenu: { [weak self] in
                self?.setSideMenuOpen(false, animated: true)
            },
            currentSessionID: { [weak self] in
                self?.chatRuntime.currentSessionID ?? UUID()
            }
        )
    }

    private func makeConversationResetWorkflow() -> ChatConversationResetWorkflow {
        ChatConversationResetWorkflow(
            clearPendingAttachments: { [weak self] deleteFiles in
                self?.composerAttachmentWorkflow.clearPendingAttachments(deleteFiles: deleteFiles)
            },
            resetConversation: { [weak self] privacyMode in
                if let privacyMode {
                    return self?.chatRuntime.resetConversation(privacyMode: privacyMode) ?? []
                }
                return self?.chatRuntime.resetConversation() ?? []
            },
            discardPrivateModeAttachments: { [weak self] attachments in
                self?.composerAttachmentWorkflow.discardPrivateModeAttachments(including: attachments)
            },
            removeChatContent: { [weak self] in
                self?.removeChatContent()
            },
            reloadSelectedSystemPrompt: { [weak self] in
                self?.reloadSelectedSystemPrompt()
            },
            lockMessagesToBottom: { [weak self] in
                self?.messagesScrollCoordinator.lockToBottom()
            },
            updateHeader: { [weak self] in
                self?.updateRightHeaderButtonState(animated: true)
            },
            reloadHistorySessions: { [weak self] selectedSessionID in
                self?.reloadHistorySessions(selectedSessionID: selectedSessionID)
            }
        )
    }

    private func makeMessageRevisionSwitchWorkflow() -> ChatMessageRevisionSwitchWorkflow {
        ChatMessageRevisionSwitchWorkflow(
            isResponseActive: { [weak self] in
                self?.responseStreamController.isActive ?? true
            },
            switchToMessageRevision: { [weak self] messageID, revisionID in
                guard let self else {
                    return []
                }
                return try self.chatRuntime.switchToMessageRevision(
                    anchorUserMessageID: messageID,
                    revisionID: revisionID
                )
            },
            renderConversationTimeline: { [weak self] events in
                self?.renderConversationTimeline(events)
            },
            lockMessagesToBottom: { [weak self] in
                self?.messagesScrollCoordinator.lockToBottom()
            },
            updateHeader: { [weak self] in
                self?.updateRightHeaderButtonState(animated: true)
            },
            reloadHistorySessions: { [weak self] selectedSessionID in
                self?.reloadHistorySessions(selectedSessionID: selectedSessionID)
            },
            currentSessionID: { [weak self] in
                self?.chatRuntime.currentSessionID ?? UUID()
            },
            presentActionFailure: { [weak self] reason in
                self?.presentMessageActionFailure(reason)
            },
            presentError: { [weak self] message in
                self?.presentAttachmentError(message)
            }
        )
    }

    private func makeMessageActionPresentationWorkflow() -> ChatMessageActionPresentationWorkflow {
        ChatMessageActionPresentationWorkflow(
            isResponseActive: { [weak self] in
                self?.responseStreamController.isActive ?? true
            },
            isPresentingModal: { [weak self] in
                self?.idleModalPresenter.isPresentingModal ?? true
            },
            containsMessage: { [weak self] messageID in
                self?.messageStackAdapter.containsSentMessage(withID: messageID) ?? false
            },
            messageRevisions: { [weak self] messageID in
                self?.chatRuntime.messageRevisions(for: messageID) ?? []
            },
            endEditing: { [weak self] in
                self?.idleModalPresenter.endEditing()
            },
            makeEditor: { text, attachments, onSubmit in
                ChatMessageActionPresentation.makeEditor(
                    text: text,
                    attachments: attachments,
                    onSubmit: onSubmit
                )
            },
            makeRevisionHistory: { revisions, onSelectRevision in
                ChatMessageActionPresentation.makeRevisionHistory(
                    revisions: revisions,
                    onSelectRevision: onSelectRevision
                )
            },
            presentViewController: { [weak self] viewController in
                self?.idleModalPresenter.presentPrepared(viewController)
            },
            presentActionFailure: { [weak self] reason in
                self?.presentMessageActionFailure(reason)
            },
            resendEditedMessage: { [weak self] messageID, text, attachments in
                self?.resendEditedMessage(
                    messageID: messageID,
                    text: text,
                    attachments: attachments
                )
            },
            switchToMessageRevision: { [weak self] messageID, revisionID in
                self?.switchToMessageRevision(
                    messageID: messageID,
                    revisionID: revisionID
                )
            }
        )
    }

    private func makeMessageResendWorkflow() -> ChatMessageResendWorkflow {
        ChatMessageResendWorkflow(
            isResponseActive: { [weak self] in
                self?.responseStreamController.isActive ?? true
            },
            firstRemovedIndex: { [weak self] messageID in
                self?.messageStackAdapter.arrangedSubviewIndexOfSentMessage(withID: messageID)
            },
            layoutIfNeeded: { [weak self] in
                self?.mainPageView.layoutIfNeeded()
            },
            captureExistingMessagesSnapshot: { [weak self] in
                self?.existingMessagesShiftAnimator.captureSnapshot() ?? .empty
            },
            prepareOutgoingTurn: { [weak self] transactionPlan in
                guard let self else {
                    throw ChatMessageResendWorkflowFailure.unavailable
                }
                return try self.outgoingTurnPreparationWorkflow.prepare(transactionPlan)
            },
            performTransaction: { [weak self] transactionPlan, preparedStream, existingMessagesSnapshot in
                self?.outgoingMessageTransactionWorkflow.perform(
                    transactionPlan,
                    preparedStream: preparedStream,
                    existingMessagesSnapshot: existingMessagesSnapshot,
                    sendTransition: nil
                )
            },
            presentActionFailure: { [weak self] reason in
                self?.presentMessageActionFailure(reason)
            },
            presentError: { [weak self] message in
                self?.presentAttachmentError(message)
            }
        )
    }

    private func makeSystemPromptSelectionWorkflow() -> ChatSystemPromptSelectionWorkflow {
        ChatSystemPromptSelectionWorkflow(
            dependencies: dependencies,
            chatRuntime: chatRuntime
        ) { [weak self] display in
            self?.setComposerSelectedSystemPromptDisplay(display)
        }
    }

    private func makeComposerAddWorkflow() -> ChatComposerAddWorkflow {
        ChatComposerAddWorkflow(
            sourceView: { [weak self] in
                self?.composerView.plusSourceView
            },
            presentSystemPromptSelection: { [weak self] in
                self?.presentSystemPromptSelection()
            },
            presentCameraPicker: { [weak self] in
                self?.attachmentAcquisitionWorkflow.present(.camera)
            },
            presentPhotoLibraryPicker: { [weak self] in
                self?.attachmentAcquisitionWorkflow.present(.photoLibrary)
            },
            presentDocumentPicker: { [weak self] in
                self?.attachmentAcquisitionWorkflow.present(.documents)
            }
        )
    }

    private func makeAttachmentPreviewWorkflow() -> ChatAttachmentPreviewWorkflow {
        ChatAttachmentPreviewWorkflow(
            previewController: attachmentPreviewController,
            isPresentingModal: { [weak self] in
                self?.idleModalPresenter.isPresentingModal ?? true
            },
            endEditing: { [weak self] in
                self?.idleModalPresenter.endEditing()
            },
            presentViewController: { [weak self] viewController in
                self?.idleModalPresenter.presentPrepared(viewController)
            },
            presentError: { [weak self] message in
                self?.presentAttachmentError(message)
            }
        )
    }

    private func makeAttachmentAcquisitionWorkflow() -> ChatAttachmentAcquisitionWorkflow {
        ChatAttachmentAcquisitionWorkflow(
            importController: ChatAttachmentImportController(
                attachmentImporter: attachmentImporter
            ),
            photoLibraryImportController: ChatPhotoLibraryImportController(
                attachmentImporter: attachmentImporter
            ),
            acceptImportedAttachments: { [weak self] attachments in
                self?.composerAttachmentWorkflow.append(attachments)
            },
            presentError: { [weak self] message in
                self?.presentAttachmentError(message)
            },
            presentViewController: { [weak self] makeViewController in
                _ = self?.idleModalPresenter.presentIfIdle {
                    makeViewController()
                }
            }
        )
    }

    private func makeIdleModalPresenter() -> ChatIdleModalPresenter {
        ChatIdleModalPresenter(
            isPresentingModal: { [weak self] in
                self?.presentedViewController != nil
            },
            endEditing: { [weak self] in
                self?.view.endEditing(true)
            },
            presentViewController: { [weak self] viewController in
                self?.present(viewController, animated: true)
            }
        )
    }

    private func makeComposerAttachmentWorkflow() -> ChatComposerAttachmentWorkflow {
        let attachmentDraft = ChatAttachmentDraft(
            attachmentStore: attachmentStore,
            attachmentCleanupDidComplete: { [weak self] result in
                self?.removeCachedAttachmentThumbnails(for: result)
            },
            didFail: { [weak self] error in
                guard let self,
                      self.viewIfLoaded?.window != nil,
                      self.presentedViewController == nil else {
                    return
                }

                self.presentAttachmentError(error.localizedDescription)
            }
        )
        return ChatComposerAttachmentWorkflow(
            attachmentDraft: attachmentDraft,
            previewWorkflow: attachmentPreviewWorkflow,
            previewDisplayPipeline: attachmentPreviewDisplayPipeline,
            privacyModeEnabled: { [weak self] in
                self?.chatRuntime.isPrivacyModeEnabled ?? false
            },
            retainedConversationAttachments: { [weak self] in
                self?.chatRuntime.currentConversationAttachments ?? []
            },
            thumbnailMaxPointSize: ComposerLayout.attachmentThumbnailPointSize,
            updatePendingDisplays: { [weak self] displays in
                self?.setComposerPendingAttachmentDisplays(displays)
            }
        )
    }

    private func setComposerPendingAttachmentDisplays(_ displays: [ChatPendingAttachmentDisplay]) {
        composerView.setPendingAttachments(
            displays.map { display in
                GlassComposerBarView.PendingAttachmentDisplay(
                    id: display.id,
                    image: display.image,
                    filename: display.filename,
                    isFile: display.isFile
                )
            }
        )
    }

    private func setComposerSelectedSystemPromptDisplay(_ display: ChatSelectedSystemPromptDisplay?) {
        composerView.setSelectedSystemPrompt(
            display.map {
                GlassComposerBarView.SelectedSystemPromptDisplay(
                    id: $0.id,
                    title: $0.title
                )
            }
        )
    }

    private func makeOutgoingMessageTransactionWorkflow() -> ChatOutgoingMessageTransactionWorkflow {
        ChatOutgoingMessageTransactionWorkflow(
            messages: ChatOutgoingMessageTransactionMessageAdapter(
                messageStackAdapter: messageStackAdapter,
                attachmentDisplayUpdater: sentMessageAttachmentDisplayUpdater,
                editHistoryCount: { [weak self] messageID in
                    self?.chatRuntime.messageRevisions(for: messageID).count ?? 0
                }
            ),
            screen: ChatOutgoingMessageTransactionScreenAdapter(
                layoutView: mainPageView,
                existingMessagesShiftAnimator: existingMessagesShiftAnimator,
                sentMessageSendAnimator: sentMessageSendAnimator,
                scrollToBottom: { [weak self] in
                    self?.scrollMessagesToBottom(animated: false)
                },
                presentLoading: { [weak self] responseView in
                    self?.showAssistantLoadingIfNeeded(in: responseView)
                }
            ),
            responseActivator: ChatOutgoingMessageTransactionResponseActivationAdapter { [weak self]
                responseStream,
                responseView,
                continuationTask,
                context in
                self?.activateAssistantResponseStream(
                    responseStream,
                    responseView: responseView,
                    continuationTask: continuationTask,
                    context: context
                )
            }
        )
    }

    private func makeComposerSendWorkflow() -> ChatComposerSendWorkflow {
        ChatComposerSendWorkflow(
            isResponseActive: { [weak self] in
                self?.responseStreamController.isActive ?? true
            },
            layoutIfNeeded: { [weak self] in
                self?.mainPageView.layoutIfNeeded()
            },
            captureExistingMessagesSnapshot: { [weak self] in
                self?.existingMessagesShiftAnimator.captureSnapshot() ?? .empty
            },
            prepareNewMessage: { [weak self] text in
                guard let self else {
                    throw ChatComposerSendWorkflowFailure.unavailable
                }

                return try self.outgoingTurnPreparationWorkflow.prepareNewMessage(text: text)
            },
            performTransaction: { [weak self] preparedTurn, existingMessagesSnapshot, transition in
                self?.outgoingMessageTransactionWorkflow.perform(
                    preparedTurn.transactionPlan,
                    preparedStream: preparedTurn.preparedStream,
                    existingMessagesSnapshot: existingMessagesSnapshot,
                    sendTransition: transition
                )
            },
            presentError: { [weak self] message in
                self?.presentAttachmentError(message)
            },
            updateHeaderAfterPrepareFailure: { [weak self] in
                self?.updateRightHeaderButtonState(animated: true)
            }
        )
    }

    private func makeOutgoingTurnPreparationWorkflow() -> ChatOutgoingTurnPreparationWorkflow {
        ChatOutgoingTurnPreparationWorkflow(
            turnStarter: chatRuntime,
            continuationTaskPolicy: ChatAssistantResponseBackgroundContinuationTaskPolicy(
                continuationTaskBeginner: chatContinuationTaskCoordinator,
                isBackgroundRuntimeEnabled: { [weak self] in
                    self?.dependencies.appSettingsStore.isBackgroundRuntimeEnabled ?? false
                }
            ),
            composerAttachmentStaging: composerAttachmentWorkflow
        )
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

    private func appendSentMessage(using transition: GlassComposerBarView.SendTransition) -> Bool {
        composerSendWorkflow.send(
            ChatComposerSendTransition(
                text: transition.text,
                backgroundGlobalFrame: transition.backgroundGlobalFrame
            )
        )
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

    private func activateAssistantResponseStream(
        _ responseStream: AsyncThrowingStream<ChatResponseDelta, Error>,
        responseView: AssistantResponseTextView,
        continuationTask: ChatContinuationTask?,
        context: ActiveAssistantResponseContext
    ) {
        activeResponseView = responseView
        activeResponseContext = context
        responseActivationPresentationAdapter.prepareActivation(animated: true)

        let didActivateResponseStream = responseStreamController.activate(
            responseStream: responseStream,
            continuationTask: continuationTask,
            handlers: ChatResponseStreamController.Handlers(
                didReceiveDelta: { [weak self, weak responseView] delta in
                    guard let self,
                          let responseView else {
                        return
                    }

                    self.appendStreamingResponseDelta(delta, to: responseView)
                },
                didFail: { [weak self, weak responseView] error in
                    guard let self,
                          let responseView else {
                        return
                    }

                    let result = self.assistantResponseFailurePresentationWorkflow.presentFailure(
                        message: error.localizedDescription,
                        responseView: responseView,
                        context: self.activeResponseContext,
                        activeResponseView: self.activeResponseView
                    )
                    self.applyActiveResponseLifecyclePlan(
                        .presentedFailure(
                            shouldClearActiveResponseView: result.shouldClearActiveResponseView
                        ),
                        responseView: responseView
                    )
                },
                didFinish: { [weak self] success in
                    self?.finishAssistantResponseStream(success: success)
                }
            )
        )
        assert(didActivateResponseStream, "Assistant response stream was already active.")
        responseActivationPresentationAdapter.completeActivation(animated: true)
    }

    private func cancelAssistantResponseStream() {
        applyActiveResponseLifecyclePlan(
            .cancelled(didCancel: responseStreamController.cancel()),
            responseView: activeResponseView
        )
    }

    private func appendStreamingResponseDelta(
        _ delta: ChatResponseDelta,
        to responseView: AssistantResponseTextView
    ) {
        applyActiveResponseLifecyclePlan(.received(delta: delta), responseView: responseView)
    }

    private func showAssistantLoadingIfNeeded(in responseView: AssistantResponseTextView) {
        guard activeResponseView === responseView else {
            return
        }

        assistantResponseMutationAdapter.showLoadingIfNeeded(in: responseView)
    }

    private func finishAssistantResponseStream(success _: Bool) {
        applyActiveResponseLifecyclePlan(
            .finished(hasActiveResponseView: activeResponseView != nil),
            responseView: activeResponseView
        )
    }

    private func applyActiveResponseLifecyclePlan(
        _ plan: ChatActiveAssistantResponseLifecyclePlan,
        responseView: AssistantResponseTextView?
    ) {
        for action in plan.actions {
            applyActiveResponseLifecycleAction(action, responseView: responseView)
        }
    }

    private func applyActiveResponseLifecycleAction(
        _ action: ChatActiveAssistantResponseLifecyclePlan.Action,
        responseView: AssistantResponseTextView?
    ) {
        switch action {
        case let .recordVisibleProgress(delta):
            activeResponseContext?.recordVisibleProgress(from: delta)
        case let .reportDelta(delta):
            responseStreamController.report(delta: delta)
        case let .appendDisplayParts(displayParts):
            guard let responseView else {
                assertionFailure("Missing response view for assistant display parts.")
                return
            }
            assistantResponseMutationAdapter.appendDisplayParts(displayParts, to: responseView)
        case .clearActiveResponseView:
            activeResponseView = nil
        case .finishActiveResponseView:
            guard let responseView else {
                assertionFailure("Missing response view to finish assistant response.")
                return
            }
            assistantResponseMutationAdapter.finishStreamingContent(in: responseView)
        case .clearActiveResponseContext:
            activeResponseContext = nil
        case .deactivatePresentation:
            responseActivationPresentationAdapter.deactivate(animated: true)
        case .playCancellationFeedback:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func updateMainPageShadowPath(cornerRadius: CGFloat? = nil) {
        let radius = cornerRadius ?? mainPageView.layer.cornerRadius
        mainPageContainerView.layer.shadowPath = UIBezierPath(
            roundedRect: mainPageContainerView.bounds,
            cornerRadius: radius
        ).cgPath
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

    private func installAttachmentThumbnailCacheObservers() {
        attachmentCleanupObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsChatStore.attachmentCleanupDidCompleteNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let result = notification.userInfo?[UserDefaultsChatStore.attachmentCleanupResultUserInfoKey]
                as? ChatAttachmentCleanupResult else {
                return
            }

            self?.removeCachedAttachmentThumbnails(for: result)
        }
        attachmentThumbnailMemoryWarningObservation = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.attachmentThumbnailProvider.removeAllCachedThumbnails()
            }
        }
    }

    private func removeCachedAttachmentThumbnails(for result: ChatAttachmentCleanupResult) {
        attachmentThumbnailProvider.removeCachedThumbnails(
            for: result.removedUnreferencedAttachments
        )
    }

    private func installHistoryPersistenceFailureHandler() {
        chatRuntime.setHistoryPersistenceFailureHandler { [weak self] error in
            self?.presentChatHistoryPersistenceError(error)
        }
    }

    private func reloadHistorySessions(selectedSessionID: UUID?) {
        historyWorkflowController.reloadSessions(
            selectedSessionID: selectedSessionID
        ) { [weak self] sessions, selectedSessionID in
            guard let self else {
                return
            }

            self.sideMenuView.reloadHistory(
                sessions: sessions,
                selectedSessionID: selectedSessionID
            )
        } didFail: { [weak self] error in
            self?.presentAttachmentError(error.localizedDescription)
        }
    }

    private func selectHistorySession(_ session: ChatSession) {
        historyWorkflowController.selectSession(
            session,
            isResponseActive: { [weak self] in
                self?.responseStreamController.isActive ?? true
            }
        ) { [weak self] session, events in
            guard let self else {
                return
            }

            self.historyPresentationWorkflow.presentLoadedSession(session, events: events)
        } didReject: { [weak self] in
            self?.sideMenuView.rejectPendingSessionSelection()
        } didFail: { [weak self] error in
            self?.sideMenuView.rejectPendingSessionSelection()
            self?.presentAttachmentError(error.localizedDescription)
        }
    }

    private func deleteHistorySession(_ session: ChatSession) {
        historyWorkflowController.deleteSession(
            session,
            currentSessionID: chatRuntime.currentSessionID,
            isResponseActive: { [weak self] in
                self?.responseStreamController.isActive ?? true
            },
            currentSessionIDProvider: { [weak self] in
                self?.chatRuntime.currentSessionID ?? session.id
            }
        ) { [weak self] completionDecision in
            self?.historyPresentationWorkflow.presentDeleteCompletion(completionDecision)
        } didFail: { [weak self] error in
            self?.presentAttachmentError(error.localizedDescription)
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
        !messageStackAdapter.isEmpty
    }

    private func renderConversationTimeline(_ events: [ChatTimelineEvent]) {
        removeChatContent()

        let plan = ChatTimelinePresentationPlan(events: events)
        for row in plan.rows {
            appendTimelineRow(row)
        }

        mainPageView.layoutIfNeeded()
        scrollMessagesToBottom(animated: false)
    }

    private func appendTimelineRow(_ row: ChatTimelinePresentationPlan.Row) {
        switch row {
        case let .userMessage(id, text, attachments):
            _ = messageStackAdapter.appendStoredUserMessage(
                id: id,
                text: text,
                attachments: attachments
            )
            loadSentMessageAttachmentDisplays(messageID: id, attachments: attachments)
        case let .assistantResponse(steps):
            appendStoredAssistantResponse(steps)
        }
    }

    private func appendStoredAssistantResponse(_ steps: [ChatTimelinePresentationPlan.AssistantStep]) {
        let responseView = messageStackAdapter.appendAssistantResponseView()
        for step in steps {
            switch step {
            case let .reasoning(text):
                responseView.appendStoredReasoning(text)
            case let .contentMarkdown(markdown):
                responseView.appendStoredContentMarkdown(markdown)
            case let .toolEvent(event):
                responseView.appendDisplayPart(.toolEvent(event))
            }
        }
        responseView.finishStreamingContent()
    }

    private func configureSentMessageActions(for bubbleView: SentMessageBubbleView, messageID: UUID) {
        bubbleView.editHistoryCount = chatRuntime.messageRevisions(for: messageID).count
        bubbleView.onPreviewAttachment = { [weak self] attachment in
            self?.attachmentPreviewWorkflow.presentPreview(for: attachment)
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

    private func removeChatContent() {
        attachmentPreviewDisplayPipeline.cancelMessageLoads()
        guard messageStackAdapter.removeAll() else {
            return
        }
        mainPageView.layoutIfNeeded()
        scrollMessagesToBottom(animated: false)
    }

    private func updateRightHeaderButtonState(animated: Bool) {
        let presentation = ChatHeaderActionPresentation.make(
            isGeneratingResponse: responseStreamController.isActive,
            isPrivateModeEnabled: chatRuntime.isPrivacyModeEnabled,
            hasChatContent: hasChatContent
        )
        let image = Self.image(for: presentation.iconSystemName)

        let update = {
            var configuration = self.rightHeaderButton.configuration
            configuration?.image = image
            configuration?.showsActivityIndicator = presentation.showsActivityIndicator
            configuration?.baseForegroundColor = presentation.usesAccentColor ? .systemBlue : .label
            self.rightHeaderButton.configuration = configuration
            self.rightHeaderButton.accessibilityLabel = presentation.accessibilityLabel.localizedString
            self.rightHeaderButton.accessibilityHint = presentation.accessibilityHint?.localizedString
            self.rightHeaderButton.isSelected = presentation.isSelected
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

    private static func makeHeaderButton(presentation: ChatHeaderActionPresentation) -> UIButton {
        var configuration = UIButton.Configuration.clearGlass()
        configuration.image = image(for: presentation.iconSystemName)
        configuration.baseForegroundColor = presentation.usesAccentColor ? .systemBlue : .label
        configuration.showsActivityIndicator = presentation.showsActivityIndicator
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = presentation.accessibilityLabel.localizedString
        button.accessibilityHint = presentation.accessibilityHint?.localizedString
        button.isSelected = presentation.isSelected
        return button
    }

    private static func image(for systemName: String?) -> UIImage? {
        guard let systemName else {
            return nil
        }

        return UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: HeaderLayout.iconPointSize,
                weight: .semibold
            )
        )
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
