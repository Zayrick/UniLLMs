//
//  AppGradientBackgroundView.swift
//  UniLLMs
//
//  Provides the shared app gradient background view and updates colors for appearance changes.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class AppGradientBackgroundView: UIView {
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

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

    private func configure() {
        isOpaque = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true

        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradientLayer.locations = [0.0, 0.5, 1.0]
        traitChangeRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AppGradientBackgroundView, _) in
            view.updateColors()
        }
        updateColors()
    }

    private func updateColors() {
        gradientLayer.colors = [
            UIColor.appBackgroundStart,
            UIColor.appBackgroundMiddle,
            UIColor.appBackgroundEnd
        ].map { $0.resolvedColor(with: traitCollection).cgColor }
    }
}
