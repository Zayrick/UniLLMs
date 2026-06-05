//
//  ChatMarkdownImageLoaderTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatMarkdownImageLoaderTests: XCTestCase {
    func testImageURLTrimsWhitespaceAndAcceptsHTTPAndHTTPSOnly() throws {
        XCTAssertEqual(
            URLSessionChatMarkdownImageLoader.imageURL(from: " https://example.com/image.png ")?.absoluteString,
            "https://example.com/image.png"
        )
        XCTAssertEqual(
            URLSessionChatMarkdownImageLoader.imageURL(from: "http://example.com/image.png")?.absoluteString,
            "http://example.com/image.png"
        )
        XCTAssertNil(URLSessionChatMarkdownImageLoader.imageURL(from: "file:///tmp/image.png"))
        XCTAssertNil(URLSessionChatMarkdownImageLoader.imageURL(from: "not a url"))
    }

    func testImageDecodingRequiresSuccessfulHTTPResponseAndValidImageData() throws {
        let imageData = try makePNGData()

        XCTAssertNotNil(
            URLSessionChatMarkdownImageLoader.image(
                data: imageData,
                response: try makeHTTPResponse(statusCode: 200)
            )
        )
        XCTAssertNil(
            URLSessionChatMarkdownImageLoader.image(
                data: imageData,
                response: try makeHTTPResponse(statusCode: 404)
            )
        )
        XCTAssertNil(
            URLSessionChatMarkdownImageLoader.image(
                data: Data("not-image".utf8),
                response: try makeHTTPResponse(statusCode: 200)
            )
        )
        XCTAssertNil(
            URLSessionChatMarkdownImageLoader.image(
                data: imageData,
                response: URLResponse(
                    url: try makeImageURL(),
                    mimeType: "image/png",
                    expectedContentLength: imageData.count,
                    textEncodingName: nil
                )
            )
        )
    }

    func testImageViewUsesInjectedLoaderAndHandlesImmediateCompletion() throws {
        let image = try makeImage()
        let imageLoader = CompletingMarkdownImageLoader(image: image)
        var sizeDidChangeCount = 0

        var imageView: ChatMarkdownImageView? = ChatMarkdownImageView(
            imageBlock: ChatMarkdownImageBlock(
                source: "https://example.com/image.png",
                altText: "Diagram"
            ),
            style: .assistant,
            traitCollection: UITraitCollection(),
            imageLoader: imageLoader
        ) {
            sizeDidChangeCount += 1
        }

        XCTAssertEqual(imageLoader.loadedSources, ["https://example.com/image.png"])
        XCTAssertEqual(sizeDidChangeCount, 1)

        imageView = nil

        XCTAssertNil(imageView)
        XCTAssertEqual(imageLoader.task.cancelCallCount, 0)
    }

    func testImageViewCancelsInjectedLoadTaskOnDeinit() {
        let imageLoader = WaitingMarkdownImageLoader()
        var imageView: ChatMarkdownImageView? = ChatMarkdownImageView(
            imageBlock: ChatMarkdownImageBlock(
                source: "https://example.com/image.png",
                altText: "Diagram"
            ),
            style: .assistant,
            traitCollection: UITraitCollection(),
            imageLoader: imageLoader
        )

        XCTAssertEqual(imageLoader.task.cancelCallCount, 0)

        imageView = nil

        XCTAssertNil(imageView)
        XCTAssertEqual(imageLoader.task.cancelCallCount, 1)
    }

    func testImageLoadControllerDoesNotRetainImmediatelyCompletedTask() throws {
        let image = try makeImage()
        let imageLoader = CompletingMarkdownImageLoader(image: image)
        let controller = ChatMarkdownImageLoadController()
        var loadedImage: UIImage?

        let didStartLoad = controller.loadImage(
            source: "https://example.com/image.png",
            loader: imageLoader
        ) { image in
            loadedImage = image
        }

        XCTAssertTrue(didStartLoad)
        XCTAssertEqual(imageLoader.loadedSources, ["https://example.com/image.png"])
        XCTAssertNotNil(loadedImage)

        controller.cancel()

        XCTAssertEqual(imageLoader.task.cancelCallCount, 0)
    }

    func testImageLoadControllerRetainsAndCancelsPendingTask() {
        let imageLoader = WaitingMarkdownImageLoader()
        let controller = ChatMarkdownImageLoadController()

        let didStartLoad = controller.loadImage(
            source: "https://example.com/image.png",
            loader: imageLoader
        ) { _ in }

        XCTAssertTrue(didStartLoad)

        controller.cancel()

        XCTAssertEqual(imageLoader.task.cancelCallCount, 1)
    }

    func testImageLoadControllerIgnoresCompletionAfterCancel() throws {
        let image = try makeImage()
        let imageLoader = WaitingMarkdownImageLoader()
        let controller = ChatMarkdownImageLoadController()
        var loadedImage: UIImage?

        controller.loadImage(
            source: "https://example.com/image.png",
            loader: imageLoader
        ) { image in
            loadedImage = image
        }
        controller.cancel()
        imageLoader.complete(with: image)

        XCTAssertNil(loadedImage)
        XCTAssertEqual(imageLoader.task.cancelCallCount, 1)
    }

    func testImageLoadControllerClearsRetainedTaskAfterCompletion() throws {
        let image = try makeImage()
        let imageLoader = WaitingMarkdownImageLoader()
        let controller = ChatMarkdownImageLoadController()
        var loadedImage: UIImage?

        controller.loadImage(
            source: "https://example.com/image.png",
            loader: imageLoader
        ) { image in
            loadedImage = image
        }
        imageLoader.complete(with: image)

        XCTAssertNotNil(loadedImage)
        controller.cancel()

        XCTAssertEqual(imageLoader.task.cancelCallCount, 0)
    }

    func testImageLoadControllerReportsUnavailableWhenLoaderDoesNotStartTask() {
        let imageLoader = UnavailableMarkdownImageLoader()
        let controller = ChatMarkdownImageLoadController()
        var didComplete = false

        let didStartLoad = controller.loadImage(
            source: "not-a-loadable-image",
            loader: imageLoader
        ) { _ in
            didComplete = true
        }

        XCTAssertFalse(didStartLoad)
        XCTAssertEqual(imageLoader.loadedSources, ["not-a-loadable-image"])
        XCTAssertFalse(didComplete)

        controller.cancel()
    }

    private func makeHTTPResponse(statusCode: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(
            HTTPURLResponse(
                url: makeImageURL(),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )
        )
    }

    private func makeImageURL() throws -> URL {
        try XCTUnwrap(URL(string: "https://example.com/image.png"))
    }

    private func makeImage() throws -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2.0, height: 1.0))
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0.0, y: 0.0, width: 2.0, height: 1.0))
        }
    }

    private func makePNGData() throws -> Data {
        try XCTUnwrap(makeImage().pngData())
    }
}

private final class CompletingMarkdownImageLoader: ChatMarkdownImageLoading {
    private let image: UIImage
    let task = FakeMarkdownImageLoadTask()
    private(set) var loadedSources: [String] = []

    init(image: UIImage) {
        self.image = image
    }

    @discardableResult
    func loadImage(
        source: String,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> (any ChatMarkdownImageLoadTask)? {
        loadedSources.append(source)
        completion(image)
        return task
    }
}

private final class WaitingMarkdownImageLoader: ChatMarkdownImageLoading {
    let task = FakeMarkdownImageLoadTask()
    private var completion: (@MainActor (UIImage?) -> Void)?

    @discardableResult
    func loadImage(
        source _: String,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> (any ChatMarkdownImageLoadTask)? {
        self.completion = completion
        return task
    }

    func complete(with image: UIImage?) {
        completion?(image)
    }
}

private final class UnavailableMarkdownImageLoader: ChatMarkdownImageLoading {
    private(set) var loadedSources: [String] = []

    @discardableResult
    func loadImage(
        source: String,
        completion _: @escaping @MainActor (UIImage?) -> Void
    ) -> (any ChatMarkdownImageLoadTask)? {
        loadedSources.append(source)
        return nil
    }
}

private final class FakeMarkdownImageLoadTask: ChatMarkdownImageLoadTask {
    private(set) var cancelCallCount = 0

    func cancel() {
        cancelCallCount += 1
    }
}
