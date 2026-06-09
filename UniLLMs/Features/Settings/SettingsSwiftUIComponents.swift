//
//  SettingsSwiftUIComponents.swift
//  UniLLMs
//
//  Shared SwiftUI building blocks for settings screens.
//

import SwiftUI
import UIKit

struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let tintColor: UIColor
    var subtitleLineLimit: Int?

    init(
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        tintColor: UIColor,
        subtitleLineLimit: Int? = 2
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.tintColor = tintColor
        self.subtitleLineLimit = subtitleLineLimit
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(Color(uiColor: tintColor))
        }
    }
}

struct SettingsNavigationRow: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let tintColor: UIColor
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        tintColor: UIColor,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.tintColor = tintColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsRowLabel(
                    title: title,
                    subtitle: subtitle,
                    symbolName: symbolName,
                    tintColor: tintColor
                )
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsTextEditor: View {
    @Binding var text: String

    let placeholder: String
    let accessibilityLabel: String
    var minimumHeight: CGFloat = 180.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Color(uiColor: .placeholderText))
                    .padding(.top, 8.0)
                    .padding(.leading, 5.0)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .frame(minHeight: minimumHeight)
                .scrollContentBackground(.hidden)
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

extension View {
    func settingsAlert(_ alert: Binding<SettingsAlert?>) -> some View {
        self.alert(
            alert.wrappedValue?.title ?? "",
            isPresented: Binding {
                alert.wrappedValue != nil
            } set: { isPresented in
                if !isPresented {
                    alert.wrappedValue = nil
                }
            },
            presenting: alert.wrappedValue
        ) { _ in
            Button(String(localized: .generalOk), role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}
