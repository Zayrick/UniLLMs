//
//  AppDelegate.swift
//  UniLLMs
//
//  Application lifecycle entry point that owns the app dependency container and forwards Core Data saving.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    let dependencies = AppEnvironment.shared.dependencies

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {}

    func saveContext() {
        dependencies.coreDataStack.saveContext()
    }
}
