//
//  ChatConnectorLineView.swift
//  UniLLMs
//
//  Draws the 1-pixel connector line used between adjacent thinking items.
//

import UIKit

final class ChatConnectorLineView: UIView {
    private struct ConnectedCircle {
        var center: CGPoint
        var radius: CGFloat
    }

    private enum Layout {
        /// Stroke width.
        static let lineWidth: CGFloat = 1.0
    }

    private let lineLayer = CAShapeLayer()
    private var circleViews: [UIView] = []
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setConnectedCircleViews(_ circleViews: [UIView]) {
        self.circleViews = circleViews
        updatePath()
    }

    func updateForCurrentCircleLayout() {
        updatePath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePath()
    }

    private func configure() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        lineLayer.fillColor = nil
        lineLayer.lineCap = .round
        lineLayer.lineWidth = Layout.lineWidth
        layer.addSublayer(lineLayer)

        traitChangeRegistration = registerForTraitChanges(
            [
                UITraitUserInterfaceStyle.self,
                UITraitDisplayScale.self
            ]
        ) { (view: ChatConnectorLineView, _) in
            view.updatePath()
        }
    }

    private func updatePath() {
        let path = UIBezierPath()
        var hasSegment = false

        let circles = connectedCircles()

        for (startNode, endNode) in zip(circles, circles.dropFirst()) {
            let deltaX = endNode.center.x - startNode.center.x
            let deltaY = endNode.center.y - startNode.center.y
            let distance = hypot(deltaX, deltaY)
            let endpointInset = startNode.radius + endNode.radius

            guard distance > endpointInset else {
                continue
            }

            let unitX = deltaX / distance
            let unitY = deltaY / distance
            let startPoint = CGPoint(
                x: startNode.center.x + unitX * startNode.radius,
                y: startNode.center.y + unitY * startNode.radius
            )
            let endPoint = CGPoint(
                x: endNode.center.x - unitX * endNode.radius,
                y: endNode.center.y - unitY * endNode.radius
            )

            path.move(to: startPoint)
            path.addLine(to: endPoint)
            hasSegment = true
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.frame = CGRect(origin: .zero, size: bounds.size)
        lineLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
        lineLayer.strokeColor = UIColor.separator
            .resolvedColor(with: traitCollection)
            .withAlphaComponent(0.65)
            .cgColor
        lineLayer.path = hasSegment ? path.cgPath : nil
        CATransaction.commit()

        isHidden = !hasSegment
    }

    private func connectedCircles() -> [ConnectedCircle] {
        circleViews.compactMap { circleView -> ConnectedCircle? in
            guard !circleView.isHidden,
                  circleView.bounds.width > 0.0,
                  circleView.bounds.height > 0.0 else {
                return nil
            }

            let center = CGPoint(x: circleView.bounds.midX, y: circleView.bounds.midY)
            return ConnectedCircle(
                center: convert(center, from: circleView),
                radius: min(circleView.bounds.width, circleView.bounds.height) / 2.0
            )
        }
    }
}
