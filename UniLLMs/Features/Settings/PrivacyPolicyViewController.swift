//
//  PrivacyPolicyViewController.swift
//  UniLLMs
//
//  Hosts the app privacy policy.
//

import SwiftUI
import UIKit

final class PrivacyPolicyViewController: UIHostingController<PrivacyPolicyView> {
    init() {
        super.init(rootView: PrivacyPolicyView())
    }

    @MainActor
    required init?(coder: NSCoder) {
        super.init(coder: coder, rootView: PrivacyPolicyView())
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(String(localized: "privacy.body"))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16.0)
                .padding(.top, 20.0)
                .padding(.bottom, 32.0)
                .textSelection(.enabled)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(String(localized: "privacy.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel(String(localized: "privacy.title"))
    }
}
