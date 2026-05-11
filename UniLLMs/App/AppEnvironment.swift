//
//  AppEnvironment.swift
//  UniLLMs
//
//  Provides the process-wide application environment and exposes the default dependency container.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class AppEnvironment {
    static let shared = AppEnvironment()

    let dependencies: AppDependencyContainer

    init(dependencies: AppDependencyContainer = AppDependencyContainer()) {
        self.dependencies = dependencies
    }
}
