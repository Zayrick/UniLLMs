//
//  ChatMarkdownImageView.swift
//  UniLLMs
//
//  Block-level Markdown image rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

final class ChatMarkdownImageView: UIView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 8.0
        static let placeholderHeight: CGFloat = 150.0
        static let maxImageHeight: CGFloat = 400.0
        static let verticalSpacing: CGFloat = 4.0
        static let iconPointSize: CGFloat = 36.0
        static let labelHorizontalInset: CGFloat = 16.0
        static let labelTopSpacing: CGFloat = 8.0
    }

    var onImageSizeDidChange: (() -> Void)?

    private let imageBlock: ChatMarkdownImageBlock
    private let imageView = UIImageView()
    private let placeholderOverlayView = UIView()
    private let placeholderIconView = UIImageView()
    private let placeholderLabel = UILabel()
    private var imageWidthConstraint: NSLayoutConstraint!
    private var imageHeightConstraint: NSLayoutConstraint!
    private var loadTask: URLSessionDataTask?
    private var loadedImage: UIImage?
    private var lastAppliedMaxWidth: CGFloat = 0.0

    init(
        imageBlock: ChatMarkdownImageBlock,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) {
        self.imageBlock = imageBlock
        super.init(frame: .zero)
        configure(style: style, traitCollection: traitCollection)
        loadImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateImageSize(maxWidth: bounds.width)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingWidth = max(1.0, size.width)
        return systemLayoutSizeFitting(
            CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        return systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let fittingWidth = max(1.0, targetSize.width)
        updateImageSize(maxWidth: fittingWidth, force: true)
        let fittingSize = super.systemLayoutSizeFitting(
            CGSize(width: fittingWidth, height: targetSize.height),
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
        return CGSize(width: fittingWidth, height: ceil(fittingSize.height))
    }

    private func configure(style: ChatMarkdownRenderStyle, traitCollection: UITraitCollection) {
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = accessibilityText
        accessibilityTraits = .image
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
        translatesAutoresizingMaskIntoConstraints = false

        configureImageView()
        configurePlaceholder(style: style, traitCollection: traitCollection)
        updateImageSize(maxWidth: 1.0, force: true)
    }

    private func configureImageView() {
        imageView.backgroundColor = .secondarySystemFill
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Metrics.cornerRadius
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: 1.0)
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: Metrics.placeholderHeight)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalSpacing),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: Metrics.verticalSpacing),
            imageWidthConstraint,
            imageHeightConstraint
        ])
    }

    private func configurePlaceholder(style: ChatMarkdownRenderStyle, traitCollection: UITraitCollection) {
        placeholderOverlayView.isUserInteractionEnabled = false
        placeholderOverlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderOverlayView)

        placeholderIconView.image = UIImage(
            systemName: "photo",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Metrics.iconPointSize,
                weight: .light
            )
        )
        placeholderIconView.tintColor = .secondaryLabel
        placeholderIconView.contentMode = .scaleAspectFit
        placeholderIconView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.text = placeholderText
        placeholderLabel.font = style.calloutFont(compatibleWith: traitCollection)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.textAlignment = .center
        placeholderLabel.lineBreakMode = .byTruncatingMiddle
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        placeholderOverlayView.addSubview(placeholderIconView)
        placeholderOverlayView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderOverlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
            placeholderOverlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            placeholderOverlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            placeholderOverlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            placeholderIconView.centerXAnchor.constraint(equalTo: placeholderOverlayView.centerXAnchor),
            placeholderIconView.centerYAnchor.constraint(equalTo: placeholderOverlayView.centerYAnchor, constant: -14.0),

            placeholderLabel.topAnchor.constraint(equalTo: placeholderIconView.bottomAnchor, constant: Metrics.labelTopSpacing),
            placeholderLabel.leadingAnchor.constraint(
                equalTo: placeholderOverlayView.leadingAnchor,
                constant: Metrics.labelHorizontalInset
            ),
            placeholderLabel.trailingAnchor.constraint(
                equalTo: placeholderOverlayView.trailingAnchor,
                constant: -Metrics.labelHorizontalInset
            )
        ])
    }

    private func loadImage() {
        guard let url = imageURL(from: imageBlock.source) else {
            placeholderLabel.text = unavailableText
            return
        }

        loadTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self else {
                return
            }

            let image = data.flatMap { data -> UIImage? in
                guard Self.isSuccessfulResponse(response) else {
                    return nil
                }
                return UIImage(data: data)
            }

            DispatchQueue.main.async {
                self.loadTask = nil
                guard let image, image.size != .zero else {
                    self.placeholderLabel.text = self.unavailableText
                    return
                }

                self.loadedImage = image
                self.imageView.image = image
                self.imageView.backgroundColor = .clear
                self.placeholderOverlayView.isHidden = true
                self.updateImageSize(maxWidth: self.bounds.width, force: true)
                self.setNeedsLayout()
                self.onImageSizeDidChange?()
            }
        }
        loadTask?.resume()
    }

    private static func isSuccessfulResponse(_ response: URLResponse?) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return (200..<300).contains(httpResponse.statusCode)
    }

    private func updateImageSize(maxWidth: CGFloat, force: Bool = false) {
        let effectiveMaxWidth = max(1.0, maxWidth)
        guard force || abs(effectiveMaxWidth - lastAppliedMaxWidth) > 0.5 else {
            return
        }

        let imageSize = scaledImageSize(maxWidth: effectiveMaxWidth)
        imageWidthConstraint.constant = imageSize.width
        imageHeightConstraint.constant = imageSize.height
        lastAppliedMaxWidth = effectiveMaxWidth
    }

    private func scaledImageSize(maxWidth: CGFloat) -> CGSize {
        guard let loadedImage,
              loadedImage.size.width > 0.0,
              loadedImage.size.height > 0.0 else {
            return CGSize(width: max(1.0, maxWidth), height: Metrics.placeholderHeight)
        }

        let aspectRatio = loadedImage.size.width / loadedImage.size.height
        var targetWidth = min(loadedImage.size.width, maxWidth)
        var targetHeight = targetWidth / aspectRatio

        if targetHeight > Metrics.maxImageHeight {
            targetHeight = Metrics.maxImageHeight
            targetWidth = targetHeight * aspectRatio
        }

        return CGSize(
            width: ceil(max(1.0, targetWidth)),
            height: ceil(max(1.0, targetHeight))
        )
    }

    private func imageURL(from source: String) -> URL? {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedSource),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }

        return url
    }

    private var placeholderText: String {
        imageBlock.altText.isEmpty ? String(localized: .markdownLoadingImage) : imageBlock.altText
    }

    private var unavailableText: String {
        imageBlock.altText.isEmpty ? String(localized: .markdownImageUnavailable) : imageBlock.altText
    }

    private var accessibilityText: String {
        imageBlock.altText.isEmpty ? String(localized: .markdownImage) : String(localized: .markdownImageWithAltFormat(imageBlock.altText))
    }
}
