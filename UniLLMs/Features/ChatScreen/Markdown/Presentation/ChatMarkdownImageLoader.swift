//
//  ChatMarkdownImageLoader.swift
//  UniLLMs
//
//  Loads remote images referenced by Markdown image blocks.
//

import UIKit

protocol ChatMarkdownImageLoadTask {
    func cancel()
}

protocol ChatMarkdownImageLoading {
    @discardableResult
    @MainActor
    func loadImage(
        source: String,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> (any ChatMarkdownImageLoadTask)?
}

extension URLSessionDataTask: ChatMarkdownImageLoadTask {}

struct URLSessionChatMarkdownImageLoader: ChatMarkdownImageLoading {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    @discardableResult
    func loadImage(
        source: String,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> (any ChatMarkdownImageLoadTask)? {
        guard let url = Self.imageURL(from: source) else {
            return nil
        }

        let task = session.dataTask(with: url) { data, response, _ in
            let image = Self.image(data: data, response: response)
            Task { @MainActor in
                completion(image)
            }
        }
        task.resume()
        return task
    }

    static func imageURL(from source: String) -> URL? {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedSource),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }

        return url
    }

    static func image(data: Data?, response: URLResponse?) -> UIImage? {
        guard let data,
              isSuccessfulResponse(response) else {
            return nil
        }

        return UIImage(data: data)
    }

    private static func isSuccessfulResponse(_ response: URLResponse?) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return (200..<300).contains(httpResponse.statusCode)
    }
}
