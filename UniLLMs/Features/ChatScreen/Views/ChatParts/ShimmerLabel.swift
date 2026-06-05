//
//  ShimmerLabel.swift
//  UniLLMs
//
//  UILabel subclass that draws an animated linear-gradient mask over an overlaid label
//  to reproduce a ShinyText shimmer effect.
//

import UIKit

final class ShimmerLabel: UILabel {
    private enum Constants {
        static let animationKey = "ShimmerLabel.shine"
        static let speed: CFTimeInterval = 2.0
    }

    private let shineLabel = UILabel()
    private let gradientMask = CAGradientLayer()
    private var isAnimating = false

    var isShimmering: Bool = false {
        didSet {
            guard isShimmering != oldValue else {
                return
            }
            updateAnimationState()
        }
    }

    /// Base color used for the static text. Defaults to `.secondaryLabel`.
    var baseColor: UIColor = .secondaryLabel {
        didSet {
            textColor = baseColor
        }
    }

    /// The color of the sweeping shine highlight.
    var shineColor: UIColor = .label {
        didSet {
            shineLabel.textColor = shineColor
        }
    }

    override var text: String? {
        didSet { shineLabel.text = text }
    }

    override var font: UIFont! {
        didSet { shineLabel.font = font }
    }

    override var textAlignment: NSTextAlignment {
        didSet { shineLabel.textAlignment = textAlignment }
    }

    override var adjustsFontForContentSizeCategory: Bool {
        didSet { shineLabel.adjustsFontForContentSizeCategory = adjustsFontForContentSizeCategory }
    }

    override var numberOfLines: Int {
        didSet { shineLabel.numberOfLines = numberOfLines }
    }

    override var lineBreakMode: NSLineBreakMode {
        didSet { shineLabel.lineBreakMode = lineBreakMode }
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
        gradientMask.frame = shineLabel.bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimationState()
    }

    private func configure() {
        textColor = baseColor

        shineLabel.translatesAutoresizingMaskIntoConstraints = false
        shineLabel.textColor = shineColor
        shineLabel.isAccessibilityElement = false
        shineLabel.isHidden = true
        addSubview(shineLabel)

        NSLayoutConstraint.activate([
            shineLabel.topAnchor.constraint(equalTo: topAnchor),
            shineLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            shineLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            shineLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        gradientMask.colors = [
            UIColor.clear.cgColor,
            UIColor.black.cgColor,
            UIColor.clear.cgColor
        ]
        gradientMask.locations = [0.0, 0.5, 1.0]
        gradientMask.startPoint = CGPoint(x: -1.0, y: 0.5)
        gradientMask.endPoint = CGPoint(x: 0.0, y: 0.5)
        shineLabel.layer.mask = gradientMask

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionStatusDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
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
        shineLabel.isHidden = false

        setNeedsLayout()
        layoutIfNeeded()

        let startPointAnim = CABasicAnimation(keyPath: "startPoint")
        startPointAnim.fromValue = CGPoint(x: -1.0, y: 0.5)
        startPointAnim.toValue = CGPoint(x: 1.0, y: 0.5)

        let endPointAnim = CABasicAnimation(keyPath: "endPoint")
        endPointAnim.fromValue = CGPoint(x: 0.0, y: 0.5)
        endPointAnim.toValue = CGPoint(x: 2.0, y: 0.5)

        let animGroup = CAAnimationGroup()
        animGroup.animations = [startPointAnim, endPointAnim]
        animGroup.duration = Constants.speed
        animGroup.repeatCount = .infinity
        animGroup.isRemovedOnCompletion = false

        gradientMask.add(animGroup, forKey: Constants.animationKey)
    }

    private func stopShimmering() {
        guard isAnimating else {
            return
        }
        isAnimating = false
        shineLabel.isHidden = true
        gradientMask.removeAnimation(forKey: Constants.animationKey)
    }

    @objc private func reduceMotionStatusDidChange() {
        updateAnimationState()
    }
}
