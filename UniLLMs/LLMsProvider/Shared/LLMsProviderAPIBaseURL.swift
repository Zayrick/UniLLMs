//
//  LLMsProviderAPIBaseURL.swift
//  UniLLMs
//
//  Shared validation and normalization for provider API base URLs.
//

import Foundation

nonisolated enum LLMsProviderAPIBaseURL {
    static func effectiveString(
        apiBase: String,
        defaultAPIBase: String
    ) -> String {
        let trimmedAPIBase = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAPIBase.isEmpty ? defaultAPIBase : trimmedAPIBase
    }

    static func normalizedURL(baseString: String) -> URL? {
        guard var components = URLComponents(string: baseString),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedPath.isEmpty ? "" : "/\(trimmedPath)"
        return components.url
    }
}
