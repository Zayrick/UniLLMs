//
//  AppGradientBackgroundView.swift
//  UniLLMs
//
//  Provides the shared app gradient background view and updates colors for appearance changes.
//  Created by Zayrick on 2026/5/11.
//

import QuartzCore
import UIKit

final class AppGradientBackgroundView: UIView {
    private var traitChangeRegistration: (any UITraitChangeRegistration)?
    private let plasmaOverlayView = AppPlasmaFlowOverlayView()

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setFlowing(_ isFlowing: Bool, animated: Bool) {
        plasmaOverlayView.setFlowing(isFlowing, animated: animated)
    }

    private func configure() {
        isOpaque = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true

        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradientLayer.locations = [0.0, 0.5, 1.0]

        plasmaOverlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plasmaOverlayView)
        NSLayoutConstraint.activate([
            plasmaOverlayView.topAnchor.constraint(equalTo: topAnchor),
            plasmaOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            plasmaOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            plasmaOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        traitChangeRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AppGradientBackgroundView, _) in
            view.updateColors()
        }
        updateColors()
    }

    private func updateColors() {
        let backgroundColors = [
            UIColor.appBackgroundStart,
            UIColor.appBackgroundMiddle,
            UIColor.appBackgroundEnd
        ].map { $0.resolvedColor(with: traitCollection) }

        gradientLayer.colors = backgroundColors.map(\.cgColor)
        plasmaOverlayView.setPalette(backgroundColors)
    }
}

private final class AppPlasmaFlowOverlayView: UIView {
    private struct PlasmaLayerConfiguration {
        let paletteIndex: Int
        let accentColor: UIColor
        let phaseOffset: Double
        let widthRatio: CGFloat
        let heightRatio: CGFloat
        let xAmplitude: Double
        let yAmplitude: Double
        let xFrequency: Double
        let yFrequency: Double
        let opacity: Float
    }

    private enum Metrics {
        static let startResponse: Double = 1.15
        static let stopResponse: Double = 1.85
        static let maximumPhaseVelocity: Double = 0.62
        static let motionEpsilon: Double = 0.002
        static let minimumDeltaTime: CFTimeInterval = 1.0 / 120.0
        static let maximumDeltaTime: CFTimeInterval = 1.0 / 12.0
        static let idleOpacityScale: Double = 0.22
        static let activeOpacityScale: Double = 1.0
        static let lightAccentBlend: CGFloat = 0.28
        static let darkAccentBlend: CGFloat = 0.36
        static let lightCenterAlpha: CGFloat = 0.68
        static let darkCenterAlpha: CGFloat = 0.44
    }

    private let configurations: [PlasmaLayerConfiguration] = [
        PlasmaLayerConfiguration(
            paletteIndex: 0,
            accentColor: .systemBlue,
            phaseOffset: 0.15,
            widthRatio: 1.35,
            heightRatio: 0.88,
            xAmplitude: 0.33,
            yAmplitude: 0.24,
            xFrequency: 0.72,
            yFrequency: 0.55,
            opacity: 0.95
        ),
        PlasmaLayerConfiguration(
            paletteIndex: 1,
            accentColor: .systemPurple,
            phaseOffset: 1.55,
            widthRatio: 1.18,
            heightRatio: 1.05,
            xAmplitude: 0.28,
            yAmplitude: 0.31,
            xFrequency: 0.52,
            yFrequency: 0.78,
            opacity: 0.86
        ),
        PlasmaLayerConfiguration(
            paletteIndex: 2,
            accentColor: .systemPink,
            phaseOffset: 3.05,
            widthRatio: 1.42,
            heightRatio: 0.92,
            xAmplitude: 0.35,
            yAmplitude: 0.22,
            xFrequency: 0.64,
            yFrequency: 0.47,
            opacity: 0.78
        ),
        PlasmaLayerConfiguration(
            paletteIndex: 0,
            accentColor: .systemTeal,
            phaseOffset: 4.45,
            widthRatio: 1.05,
            heightRatio: 1.20,
            xAmplitude: 0.24,
            yAmplitude: 0.34,
            xFrequency: 0.82,
            yFrequency: 0.61,
            opacity: 0.70
        )
    ]

    private var plasmaLayers: [CAGradientLayer] = []
    private var palette: [UIColor] = []
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: AppPlasmaDisplayLinkProxy?
    private var reduceMotionObservation: NSObjectProtocol?
    private var lastTimestamp: CFTimeInterval?
    private var phase: Double = 0.0
    private var motion: Double = 0.0
    private var targetIsFlowing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        displayLink?.invalidate()
        if let reduceMotionObservation {
            NotificationCenter.default.removeObserver(reduceMotionObservation)
        }
    }

    func setPalette(_ palette: [UIColor]) {
        self.palette = palette
        updateLayerColors()
        updateLayerGeometry()
    }

    func setFlowing(_ isFlowing: Bool, animated: Bool) {
        targetIsFlowing = isFlowing

        if !animated {
            motion = effectiveTargetMotion
            updateLayerGeometry()
        }

        if shouldRunDisplayLink {
            startDisplayLinkIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerGeometry()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window == nil {
            stopDisplayLink()
        } else if shouldRunDisplayLink {
            startDisplayLinkIfNeeded()
        }
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        layer.masksToBounds = true

        plasmaLayers = configurations.map { _ in
            let gradientLayer = CAGradientLayer()
            gradientLayer.type = .radial
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
            gradientLayer.locations = [0.0, 0.58, 1.0]
            layer.addSublayer(gradientLayer)
            return gradientLayer
        }

        reduceMotionObservation = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleReduceMotionChange()
        }

        updateLayerColors()
        updateLayerGeometry()
    }

    private func handleReduceMotionChange() {
        if shouldRunDisplayLink {
            startDisplayLinkIfNeeded()
        }
    }

    private var effectiveTargetMotion: Double {
        targetIsFlowing && !UIAccessibility.isReduceMotionEnabled ? 1.0 : 0.0
    }

    private var shouldRunDisplayLink: Bool {
        window != nil && (effectiveTargetMotion > 0.0 || motion > Metrics.motionEpsilon)
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil,
              window != nil else {
            return
        }

        let proxy = AppPlasmaDisplayLinkProxy(target: self)
        let link = CADisplayLink(target: proxy, selector: #selector(AppPlasmaDisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 12.0, maximum: 30.0, preferred: 24.0)
        link.add(to: .main, forMode: .common)
        displayLinkProxy = proxy
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        lastTimestamp = nil
    }

    fileprivate func handleDisplayLinkTick(_ link: CADisplayLink) {
        let deltaTime = clampedDeltaTime(for: link)
        let targetMotion = effectiveTargetMotion
        let response = targetMotion > motion ? Metrics.startResponse : Metrics.stopResponse
        let smoothing = 1.0 - exp(-deltaTime / response)
        motion += (targetMotion - motion) * smoothing

        if motion < Metrics.motionEpsilon && targetMotion == 0.0 {
            motion = 0.0
        }

        phase += deltaTime * motion * Metrics.maximumPhaseVelocity
        updateLayerGeometry()

        if !shouldRunDisplayLink {
            stopDisplayLink()
        }
    }

    private func clampedDeltaTime(for link: CADisplayLink) -> CFTimeInterval {
        let deltaTime = lastTimestamp.map { link.timestamp - $0 } ?? (link.targetTimestamp - link.timestamp)
        lastTimestamp = link.timestamp
        return min(max(deltaTime, Metrics.minimumDeltaTime), Metrics.maximumDeltaTime)
    }

    private func updateLayerColors() {
        let centerAlpha = traitCollection.userInterfaceStyle == .dark
            ? Metrics.darkCenterAlpha
            : Metrics.lightCenterAlpha

        for (index, plasmaLayer) in plasmaLayers.enumerated() {
            let configuration = configurations[index]
            let baseColor = paletteColor(at: configuration.paletteIndex)
            let accentBlend = traitCollection.userInterfaceStyle == .dark
                ? Metrics.darkAccentBlend
                : Metrics.lightAccentBlend
            let color = blend(baseColor, with: configuration.accentColor, amount: accentBlend)

            plasmaLayer.colors = [
                color.withAlphaComponent(centerAlpha).cgColor,
                color.withAlphaComponent(centerAlpha * 0.24).cgColor,
                color.withAlphaComponent(0.0).cgColor
            ]
        }
    }

    private func updateLayerGeometry() {
        guard !bounds.isEmpty else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let size = bounds.size
        let safeWidth = max(size.width, 1.0)
        let safeHeight = max(size.height, 1.0)

        for (index, plasmaLayer) in plasmaLayers.enumerated() {
            let configuration = configurations[index]
            let t1 = phase + configuration.phaseOffset
            let t2 = phase * 0.7 + configuration.phaseOffset
            let t3 = phase * 1.3 + configuration.phaseOffset

            let x = 0.5 + sin(t1 * configuration.xFrequency) * configuration.xAmplitude
            let y = 0.5 + cos(t2 * configuration.yFrequency) * configuration.yAmplitude
            let intensity = plasmaIntensity(x: x, y: y, t1: t1, t2: t2, t3: t3)
            let breathing = 0.92 + CGFloat(intensity) * 0.16
            let width = safeWidth * configuration.widthRatio * breathing
            let height = safeHeight * configuration.heightRatio * (1.08 - CGFloat(intensity) * 0.10)
            let position = CGPoint(x: CGFloat(x) * safeWidth, y: CGFloat(y) * safeHeight)
            let angle = CGFloat(sin(t3 * 0.42) * 0.20)
            let opacityScale = Metrics.idleOpacityScale
                + (Metrics.activeOpacityScale - Metrics.idleOpacityScale) * motion

            plasmaLayer.bounds = CGRect(x: 0.0, y: 0.0, width: width, height: height)
            plasmaLayer.position = position
            plasmaLayer.opacity = configuration.opacity * Float(opacityScale) * Float(0.82 + intensity * 0.18)
            plasmaLayer.transform = CATransform3DMakeRotation(angle, 0.0, 0.0, 1.0)
        }

        CATransaction.commit()
    }

    private func plasmaIntensity(
        x: Double,
        y: Double,
        t1: Double,
        t2: Double,
        t3: Double
    ) -> Double {
        let val1 = sin(x * 5.0 + t1)
        let val2 = sin((x * sin(t2 / 2.0) + y * cos(t3 / 3.0)) * 5.0 + t2)
        let distance = sqrt(pow(x - 0.5, 2.0) + pow(y - 0.5, 2.0))
        let val3 = sin(distance * 5.0 + t3)
        return (val1 + val2 + val3 + 3.0) / 6.0
    }

    private func paletteColor(at index: Int) -> UIColor {
        guard !palette.isEmpty else {
            return .clear
        }

        return palette[index % palette.count].resolvedColor(with: traitCollection)
    }

    private func blend(_ color: UIColor, with overlayColor: UIColor, amount: CGFloat) -> UIColor {
        let resolvedColor = color.resolvedColor(with: traitCollection)
        let resolvedOverlayColor = overlayColor.resolvedColor(with: traitCollection)
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        var overlayRed: CGFloat = 0.0
        var overlayGreen: CGFloat = 0.0
        var overlayBlue: CGFloat = 0.0
        var overlayAlpha: CGFloat = 0.0

        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              resolvedOverlayColor.getRed(
                  &overlayRed,
                  green: &overlayGreen,
                  blue: &overlayBlue,
                  alpha: &overlayAlpha
              ) else {
            return resolvedColor
        }

        let clampedAmount = min(max(amount, 0.0), 1.0)
        return UIColor(
            red: red + (overlayRed - red) * clampedAmount,
            green: green + (overlayGreen - green) * clampedAmount,
            blue: blue + (overlayBlue - blue) * clampedAmount,
            alpha: alpha + (overlayAlpha - alpha) * clampedAmount
        )
    }
}

private final class AppPlasmaDisplayLinkProxy {
    weak var target: AppPlasmaFlowOverlayView?

    init(target: AppPlasmaFlowOverlayView) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        target?.handleDisplayLinkTick(link)
    }
}
