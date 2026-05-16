//
//  ShimmerLabel.swift
//  UniLLMs
//
//  UILabel subclass that draws an animated linear-gradient mask over the text to
//  reproduce the VS Code chat "thinking" shimmer effect.
//

import UIKit

final class ShimmerLabel: UILabel {
    private enum Constants {
        static let animationKey = "ShimmerLabel.locations"
        static let duration: CFTimeInterval = 2.0
        static let restingStops: [NSNumber] = [0.0, 0.35, 0.5, 0.65, 1.0]
        static let startStops: [NSNumber] = [0.0, 0.0, 0.12, 0.24, 0.42]
        static let endStops: [NSNumber] = [0.58, 0.76, 0.88, 1.0, 1.0]
        static let dimAlpha: CGFloat = 0.42
        static let highlightAlpha: CGFloat = 1.0
    }

    private let gradientLayer = CAGradientLayer()
    private var isAnimating = false

    var isShimmering: Bool = false {
        didSet {
            guard isShimmering != oldValue else {
                return
            }
            updateAnimationState()
        }
    }

    /// Base color used for the static and masked text. Defaults to `.secondaryLabel`.
    var baseColor: UIColor = .secondaryLabel {
        didSet {
            textColor = baseColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGradientFrame()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimationState()
    }

    private func configure() {
        textColor = baseColor
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        gradientLayer.locations = Constants.restingStops
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionStatusDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    private func updateGradientFrame() {
        guard isShimmering else {
            return
        }
        let labelBounds = bounds
        guard labelBounds.width > 0.0, labelBounds.height > 0.0 else {
            return
        }
        gradientLayer.frame = labelBounds
    }

    private func applyGradientColors() {
        let dim = UIColor.black.withAlphaComponent(Constants.dimAlpha).cgColor
        let highlight = UIColor.black.withAlphaComponent(Constants.highlightAlpha).cgColor
        gradientLayer.colors = [dim, dim, highlight, dim, dim]
    }

    private func updateAnimationState() {
        if isShimmering, window != nil, !UIAccessibility.isReduceMotionEnabled {
            startShimmering()
        } else {
            stopShimmering()
        }
    }

    private func startShimmering() {
        guard !isAnimating else {
            return
        }
        isAnimating = true
        applyGradientColors()
        layer.mask = gradientLayer
        updateGradientFrame()

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = Constants.startStops
        animation.toValue = Constants.endStops
        animation.duration = Constants.duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        gradientLayer.add(animation, forKey: Constants.animationKey)
    }

    private func stopShimmering() {
        guard isAnimating else {
            return
        }
        isAnimating = false
        gradientLayer.removeAnimation(forKey: Constants.animationKey)
        gradientLayer.locations = Constants.restingStops
        layer.mask = nil
    }

    @objc private func reduceMotionStatusDidChange() {
        updateAnimationState()
    }
}
