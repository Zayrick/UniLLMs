//
//  AboutViewController.swift
//  UniLLMs
//
//  Hosts app, contact, open-source, and policy information.
//

import SwiftUI
import UIKit

final class AboutViewController: UIHostingController<AboutForm> {
    private let router: AboutRouter

    init() {
        let router = AboutRouter()
        self.router = router
        super.init(rootView: AboutForm(router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let router = AboutRouter()
        self.router = router
        super.init(coder: coder, rootView: AboutForm(router: router))
        router.hostViewController = self
    }
}

struct AboutForm: View {
    @Environment(\.openURL) private var openURL

    private enum Constants {
        static let contactEmail = "tvefxt@gmail.com"
        static let headerImageName = "AboutAppIcon"
        static let sourceRepositoryDisplay = "Zayrick/UniLLMs"
        static let contactEmailURL = URL(string: "mailto:tvefxt@gmail.com")
        static let sourceRepositoryURL = URL(string: "https://github.com/Zayrick/UniLLMs")
        static let licenseURL = URL(string: "https://github.com/Zayrick/UniLLMs/blob/main/LICENSE")
    }

    private let router: AboutRouter

    fileprivate init(router: AboutRouter) {
        self.router = router
    }

    var body: some View {
        Form {
            headerSection
            contactSection
            legalSection
        }
        .navigationTitle(String(localized: "about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        Section {
            VStack(spacing: 14.0) {
                Image(Constants.headerImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92.0, height: 92.0)
                    .accessibilityHidden(true)

                VStack(spacing: 8.0) {
                    Text(String(localized: "about.summary.title"))
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(String(localized: "about.summary.detail"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14.0)
        }
        .listRowBackground(Color.clear)
    }

    private var contactSection: some View {
        Section(String(localized: "about.section.contact")) {
            AboutLinkRow(
                title: String(localized: "about.email.title"),
                detail: Constants.contactEmail,
                symbolName: "envelope",
                tintColor: .systemGreen
            ) {
                open(Constants.contactEmailURL)
            }

            AboutLinkRow(
                title: String(localized: "about.open_source.title"),
                detail: Constants.sourceRepositoryDisplay,
                symbolName: "chevron.left.forwardslash.chevron.right",
                tintColor: .systemPurple
            ) {
                open(Constants.sourceRepositoryURL)
            }
        }
    }

    private var legalSection: some View {
        Section(String(localized: "about.section.legal")) {
            SettingsNavigationRow(
                title: String(localized: "about.privacy_policy.title"),
                subtitle: String(localized: "about.privacy_policy.detail"),
                symbolName: "hand.raised",
                tintColor: .systemIndigo,
                action: router.showPrivacyPolicy
            )

            AboutLinkRow(
                title: String(localized: "about.license.title"),
                detail: String(localized: "about.license.detail"),
                symbolName: "doc.text",
                tintColor: .systemGray
            ) {
                open(Constants.licenseURL)
            }
        }
    }

    private func open(_ url: URL?) {
        guard let url else {
            return
        }

        openURL(url)
    }
}

private struct AboutLinkRow: View {
    let title: String
    let detail: String
    let symbolName: String
    let tintColor: UIColor
    let action: () -> Void

    var body: some View {
        SettingsNavigationRow(
            title: title,
            subtitle: detail,
            symbolName: symbolName,
            tintColor: tintColor,
            action: action
        )
        .accessibilityLabel("\(title), \(detail)")
    }
}

@MainActor
private final class AboutRouter {
    weak var hostViewController: UIViewController?

    func showPrivacyPolicy() {
        hostViewController?.navigationController?.pushViewController(
            PrivacyPolicyViewController(),
            animated: true
        )
    }
}
