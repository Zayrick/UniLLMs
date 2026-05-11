//
//  UIScreen+DisplayCornerRadius.swift
//  UniLLMs
//
//  Provides screen corner radius access for matching device corners when the side menu is open.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

extension UIScreen {
    var displayCornerRadius: CGFloat {
        guard let radius = value(forKey: "_displayCornerRadius") as? NSNumber else {
            return 0.0
        }

        return CGFloat(truncating: radius)
    }
}
