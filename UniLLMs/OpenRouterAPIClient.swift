//
//  OpenRouterAPIClient.swift
//  UniLLMs
//
//  Created by OpenAI on 2026/5/10.
//

import Foundation

struct OpenRouterAPIClient {
    enum APIError: LocalizedError {
        case invalidAPIBase(String)
        case invalidResponse
        case serverStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case let .invalidAPIBase(apiBase):
                return "Invalid API Base: \(apiBase)"
            case .invalidResponse:
                return "OpenRouter returned an invalid response."
            case let .serverStatus(statusCode, message):
                if let message, !message.isEmpty {
                    return "OpenRouter returned HTTP \(statusCode): \(message)"
                }
                return "OpenRouter returned HTTP \(statusCode)."
            }
        }
    }

    private struct ModelsResponse: Decodable {
        var data: [Model]
    }

    private struct Model: Decodable {
        var id: String
        var name: String
        var contextLength: Int?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case contextLength = "context_length"
        }
    }

    var session: URLSession = .shared

    func fetchModels(apiBase: String, apiKey: String) async throws -> [LLMProviderModel] {
        var request = URLRequest(url: try modelsURL(apiBase: apiBase))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw APIError.serverStatus(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data
            .map {
                LLMProviderModel(
                    id: $0.id,
                    name: $0.name,
                    contextLength: $0.contextLength
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func modelsURL(apiBase: String) throws -> URL {
        let trimmedAPIBase = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseString = trimmedAPIBase.isEmpty
            ? LLMProviderRecord.openRouterDefaultAPIBase
            : trimmedAPIBase

        guard let baseURL = URL(string: baseString) else {
            throw APIError.invalidAPIBase(baseString)
        }

        return baseURL.appendingPathComponent("models")
    }
}
