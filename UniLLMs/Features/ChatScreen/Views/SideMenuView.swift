//
//  SideMenuView.swift
//  UniLLMs
//
//  Displays the chat side menu entry points, search field, and settings button.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class SideMenuView: UIView {
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
