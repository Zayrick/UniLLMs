//
//  ChatMarkdownImageLoadController.swift
//  UniLLMs
//
//  Owns Markdown image load task retention and cancellation.
//

import UIKit

final class ChatMarkdownImageLoadController {
    private final class LoadState {
        var didComplete = false
    }

    private var loadTask: (any ChatMarkdownImageLoadTask)?
    private var loadGeneration = 0

    deinit {
        loadTask?.cancel()
    }

    @MainActor
    func cancel() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
    }

    @discardableResult
    @MainActor
    func loadImage(
        source: String,
        loader: any ChatMarkdownImageLoading,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> Bool {
        cancel()
        let currentGeneration = loadGeneration

        let loadState = LoadState()
        let task = loader.loadImage(source: source) { [weak self, loadState] image in
            guard let self, self.loadGeneration == currentGeneration else {
                return
            }

            loadState.didComplete = true
            self.loadTask = nil
            completion(image)
        }

        guard let task else {
            return false
        }

        if !loadState.didComplete {
            loadTask = task
        }
        return true
    }
}
