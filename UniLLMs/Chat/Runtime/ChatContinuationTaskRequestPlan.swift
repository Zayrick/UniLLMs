//
//  ChatContinuationTaskRequestPlan.swift
//  UniLLMs
//
//  Defines the BackgroundTasks identifier contract for a continued chat response.
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated struct ChatContinuationTaskRequestPlan: Equatable {
    static let identifierPrefix = "Zayrick.UniLLMs.chatTurn"
    static let permittedIdentifierPattern = "\(identifierPrefix).*"
    static let infoPlistPermittedIdentifiersKey = "BGTaskSchedulerPermittedIdentifiers"

    var identifier: String

    var registrationIdentifier: String {
        identifier
    }

    var isPermittedByDefaultPattern: Bool {
        isPermitted(by: [Self.permittedIdentifierPattern])
    }

    static func make(uuid: UUID = UUID()) -> ChatContinuationTaskRequestPlan {
        ChatContinuationTaskRequestPlan(
            suffix: uuid.uuidString.replacingOccurrences(of: "-", with: "")
        )
    }

    init(suffix: String) {
        let sanitizedSuffix = suffix
            .filter(Self.isIdentifierSuffixCharacter)
        let effectiveSuffix = sanitizedSuffix.isEmpty
            ? UUID().uuidString.replacingOccurrences(of: "-", with: "")
            : sanitizedSuffix
        identifier = "\(Self.identifierPrefix).\(effectiveSuffix)"
    }

    func isPermitted(by patterns: [String]) -> Bool {
        patterns.contains { pattern in
            matches(permittedIdentifierPattern: pattern)
        }
    }

    private func matches(permittedIdentifierPattern pattern: String) -> Bool {
        if pattern == identifier {
            return true
        }

        let wildcardSuffix = ".*"
        guard pattern.hasSuffix(wildcardSuffix) else {
            return false
        }

        let prefix = String(pattern.dropLast(wildcardSuffix.count))
        return identifier.hasPrefix("\(prefix).")
            && identifier.count > prefix.count + 1
    }

    private static func isIdentifierSuffixCharacter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }

        return (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
            || (48...57).contains(scalar.value)
    }
}
