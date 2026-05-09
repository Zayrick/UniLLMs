//
//  ViewController.swift
//  UniLLMs
//
//  Created by Zayrick on 2026/5/9.
//

import UIKit

class ViewController: UIViewController {
    private enum HeaderLayout {
        static let buttonSize: CGFloat = 44.0
        static let horizontalInset: CGFloat = 16.0
        static let topSpacing: CGFloat = 10.0
        static let iconPointSize: CGFloat = 18.0
    }

    private enum ComposerLayout {
        static let keyboardHorizontalInset: CGFloat = 14.0
        static let keyboardBottomSpacing: CGFloat = 8.0
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
    private let leftHeaderButton = ViewController.makeHeaderButton(
        systemName: "list.bullet",
        accessibilityLabel: "Menu"
    )
    private let rightHeaderButton = ViewController.makeHeaderButton(
        systemName: "app.dashed",
        accessibilityLabel: "Layout"
    )
    private let composerView = GlassComposerBarView()
    private var composerLeadingConstraint: NSLayoutConstraint!
    private var composerTrailingConstraint: NSLayoutConstraint!
    private var composerKeyboardBottomConstraint: NSLayoutConstraint!
    private var composerRestingBottomConstraint: NSLayoutConstraint!
    private var keyboardObservation: NotificationCenter.ObservationToken?
    private var isKeyboardVisible = false
    private var isSideMenuOpen = false
    private var isSettingsPresentationPending = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .appBackgroundMiddle

        configureRootBackground()
        configureSideMenu()
        configureMainPage()
        configureHeaderButtons()
        configureComposerView()
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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateSideMenuLayout()
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
        [leftHeaderButton, rightHeaderButton].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            mainPageView.addSubview(button)
        }
        leftHeaderButton.addTarget(self, action: #selector(toggleSideMenu), for: .touchUpInside)

        NSLayoutConstraint.activate([
            leftHeaderButton.topAnchor.constraint(
                equalTo: mainPageView.safeAreaLayoutGuide.topAnchor,
                constant: HeaderLayout.topSpacing
            ),
            leftHeaderButton.leadingAnchor.constraint(
                equalTo: mainPageView.safeAreaLayoutGuide.leadingAnchor,
                constant: HeaderLayout.horizontalInset
            ),
            leftHeaderButton.widthAnchor.constraint(equalToConstant: HeaderLayout.buttonSize),
            leftHeaderButton.heightAnchor.constraint(equalToConstant: HeaderLayout.buttonSize),

            rightHeaderButton.topAnchor.constraint(
                equalTo: leftHeaderButton.topAnchor
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

    @objc private func presentSettings() {
        guard !isSettingsPresentationPending,
              presentedViewController == nil else {
            return
        }

        isSettingsPresentationPending = true
        view.endEditing(true)

        let presentSheet = { [weak self] in
            guard let self else {
                return
            }

            self.isSettingsPresentationPending = false
            guard self.presentedViewController == nil else {
                return
            }

            let settingsViewController = SettingsViewController()
            let navigationController = UINavigationController(rootViewController: settingsViewController)
            navigationController.modalPresentationStyle = .pageSheet
            navigationController.navigationBar.prefersLargeTitles = false

            if let sheetPresentationController = navigationController.sheetPresentationController {
                sheetPresentationController.detents = [.large()]
                sheetPresentationController.prefersGrabberVisible = false
            }

            self.present(navigationController, animated: true)
        }

        presentSheet()
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
    private enum Section: Int, CaseIterable {
        case config

        var title: String {
            switch self {
            case .config:
                return "config"
            }
        }
    }

    private enum ConfigRow: Int, CaseIterable {
        case llmsProvider

        var title: String {
            switch self {
            case .llmsProvider:
                return "LLMs Provider"
            }
        }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Setting"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal

        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .config:
            return ConfigRow.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default

        var content = cell.defaultContentConfiguration()
        content.text = configRow(at: indexPath)?.title
        content.textProperties.color = .label
        cell.contentConfiguration = content

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch configRow(at: indexPath) {
        case .llmsProvider:
            navigationController?.pushViewController(LLMsProviderViewController(), animated: true)
        case nil:
            break
        }
    }

    private func configRow(at indexPath: IndexPath) -> ConfigRow? {
        guard Section(rawValue: indexPath.section) == .config else {
            return nil
        }

        return ConfigRow(rawValue: indexPath.row)
    }
}

private final class LLMsProviderViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "LLMs Provider"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addProvider)
        )
    }

    @objc private func addProvider() {
    }
}

private final class GlassComposerBarView: UIVisualEffectView, UITextViewDelegate {
    private enum Metrics {
        static let controlHeight: CGFloat = 44.0
        static let spacing: CGFloat = 8.0
        static let capsuleHorizontalInset: CGFloat = 12.0
        static let capsuleVerticalInset: CGFloat = 6.0
        static let textMinHeight: CGFloat = 32.0
        static let textMaxHeight: CGFloat = 118.0
        static let sendButtonSize: CGFloat = 34.0
    }

    private let stackView = UIStackView()
    private let plusGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let capsuleGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let plusButton = UIButton(type: .system)
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)

    private var textHeightConstraint: NSLayoutConstraint!
    private var lastMeasuredTextWidth: CGFloat = 0.0

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
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateTextHeight(animated: true)
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear

        configureStackView()
        configurePlusButton()
        configureCapsule()
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

        plusGlassView.translatesAutoresizingMaskIntoConstraints = false
        plusGlassView.cornerConfiguration = .capsule()
        plusGlassView.setContentHuggingPriority(.required, for: .horizontal)
        plusGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)

        capsuleGlassView.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.cornerConfiguration = .corners(
            radius: .fixed(Double(Metrics.controlHeight * 0.5))
        )

        NSLayoutConstraint.activate([
            plusGlassView.widthAnchor.constraint(equalToConstant: Metrics.controlHeight),
            plusGlassView.heightAnchor.constraint(equalToConstant: Metrics.controlHeight),
            capsuleGlassView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight)
        ])
    }

    private func configurePlusButton() {
        plusButton.tintColor = .label
        plusButton.setImage(
            UIImage(
                systemName: "plus",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)
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

    private func configureCapsule() {
        configureTextView()
        configureSendButton()

        textView.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.contentView.addSubview(textView)
        capsuleGlassView.contentView.addSubview(sendButton)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Metrics.textMinHeight)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: capsuleGlassView.contentView.topAnchor, constant: Metrics.capsuleVerticalInset),
            textView.leadingAnchor.constraint(equalTo: capsuleGlassView.contentView.leadingAnchor, constant: Metrics.capsuleHorizontalInset),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8.0),
            textView.bottomAnchor.constraint(equalTo: capsuleGlassView.contentView.bottomAnchor, constant: -Metrics.capsuleVerticalInset),
            textHeightConstraint,

            sendButton.trailingAnchor.constraint(equalTo: capsuleGlassView.contentView.trailingAnchor, constant: -5.0),
            sendButton.bottomAnchor.constraint(equalTo: capsuleGlassView.contentView.bottomAnchor, constant: -5.0),
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
