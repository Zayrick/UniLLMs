# Repository Guidelines

## Project Structure & Module Organization

`UniLLMs.xcodeproj/` contains the Xcode project, targets, and scheme metadata. The app target source lives in `UniLLMs/`. This is a UIKit app, not a SwiftUI app: `AppDelegate.swift` owns app lifecycle and the Core Data stack, `SceneDelegate.swift` connects the main scene, `Base.lproj/Main.storyboard` declares the initial `ViewController`, and `ViewController.swift` builds the current primary interface mostly in code.

Provider configuration and model metadata are handled by `LLMProviderStore.swift`, which persists Codable records in `UserDefaults`. `OpenRouterAPIClient.swift` contains the async URLSession client for loading OpenRouter models. Visual resources are in `UniLLMs/Assets.xcassets/`, including the app icon, accent color, and app background color sets. Unit tests live in `UniLLMsTests/`; UI test scaffolding lives in `UniLLMsUITests/`. `reference/Telegram-iOS/` is reference material only and should not be edited unless the user specifically asks for changes there.

## Agent-Specific Instructions

AI agents must not compile, build, archive, or launch the app for this repository unless the user explicitly asks for it. Do not run `xcodebuild build`, `xcodebuild test`, Xcode build actions, simulator launches, or equivalent commands that compile, build, install, or launch the app. It is acceptable to inspect, add, and edit unit tests or UI tests, as long as the agent does not run commands that trigger compilation or app launch. It is acceptable to inspect source files, storyboards, assets, and Xcode project metadata by reading files. Only run `xcodebuild -list` when the user explicitly asks for Xcode-reported project metadata.

AI agents may run read-only `git` commands for inspection. Do not perform Git operations that modify repository state unless the user explicitly asks for that specific action. 

Respect unrelated local changes. The worktree may contain user edits or generated files; do not revert files you did not change. Keep edits scoped to the requested app target, test target, or documentation files.

## Freshness & Web Research Requirement

Before generating content that depends on Apple SDKs, OpenRouter APIs, OpenAI APIs, third-party libraries, command-line tools, platform behavior, or other fast-moving interfaces, AI agents must use the available web lookup, browser, or official documentation tools to verify the latest API names, signatures, request and response shapes, setup steps, deprecations, and recommended usage. This check must happen before writing implementation plans, code changes, tests, documentation, or user-facing explanations that rely on those details.

Prefer primary sources: Apple Developer Documentation, OpenRouter documentation, OpenAI documentation, official package/library documentation, release notes, and official source repositories. When the answer or implementation relies on a specific external API or behavior, summarize the verified source and date in the response or working notes. Do not rely only on model memory for modern APIs, SDK behavior, authentication details, Info.plist/privacy requirements, entitlement usage, dependency setup, or request/response schemas.

If network access or documentation lookup is unavailable, explicitly state that current web verification could not be performed before making assumptions. In that case, make the smallest well-supported change possible, avoid speculative API usage, and ask the user before proceeding when the missing information could affect correctness, security, or data compatibility.

This requirement does not weaken the repository's build restrictions. Web research is allowed for freshness, but agents still must not compile, build, test, archive, install, or launch the app unless the user explicitly asks for that specific action.

## Implementation Principles

When work depends on Apple SDKs, OpenRouter APIs, or other fast-moving interfaces, follow the Freshness & Web Research Requirement above before generating content. Do not rely on stale memory for modern APIs. If network access is unavailable, state that limitation and make the smallest well-supported assumption.

Prefer native Apple frameworks and platform conventions over third-party dependencies or custom infrastructure. Use UIKit, Foundation, URLSession, UserDefaults, Core Data, Auto Layout, asset catalogs, and XCTest directly when they solve the problem cleanly. Add dependencies, wrappers, or abstractions only when they remove real complexity or are explicitly requested.

Keep architecture and behavior extremely simple, clean, and direct. Solve the root cause instead of layering workaround code. Avoid patchwork fixes: do not accumulate special cases, duplicate state, compatibility shims, or one-off branches unless there is a documented product or platform reason. When a temporary workaround is unavoidable, keep it isolated, name the reason, and remove obsolete code around it.

## Build, Test, and Development Commands

The following commands are for human contributors or for cases where the user explicitly requests them:

- `open UniLLMs.xcodeproj` opens the project in Xcode for simulator runs and interface editing.
- `xcodebuild -list -project UniLLMs.xcodeproj` lists available targets, configurations, and schemes.
- `xcodebuild -project UniLLMs.xcodeproj -scheme UniLLMs -configuration Debug -sdk iphonesimulator -derivedDataPath .DerivedData build` builds the app locally while keeping build output inside the repo.
- `xcodebuild test -project UniLLMs.xcodeproj -scheme UniLLMs -destination 'platform=iOS Simulator,name=<Device Name>' -derivedDataPath .DerivedData` runs the unit and UI test targets when an appropriate simulator is available.

## Coding Style & Naming Conventions

Use Swift 5 and UIKit conventions. Indent Swift with 4 spaces. Use `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and descriptive asset names such as `AppBackgroundStart`. Keep view-controller code organized into small private configuration methods, private helper methods, and focused private nested types or file-private view classes, matching the current `ViewController.swift` style.

Prefer Auto Layout constraints over frame math for persistent layout. Keep UI constants grouped in private enums when they describe a section of the interface. Use SF Symbols inline where they are configured, and provide accessibility labels for icon-only controls. Preserve UIKit lifecycle boundaries: app/session setup belongs in `AppDelegate` and `SceneDelegate`; screen behavior belongs in view controllers and view subclasses.

For persistence changes, keep `LLMProviderRecord` and `LLMProviderModel` Codable-compatible and consider migration for stored `UserDefaults` data. For network changes, keep `OpenRouterAPIClient` async/throws, validate URLs and HTTP status codes, and avoid logging secrets or full authorization headers.

## Testing Guidelines

XCTest targets already exist. Add focused unit tests in `UniLLMsTests/` for model, store, parsing, and non-UI behavior; name new files after the subject under test, for example `LLMProviderStoreTests.swift`. Use clear XCTest names such as `testAddingProviderAssignsUniqueName()` or `test_<behavior>_<expectedResult>()`, and keep test data isolated with dedicated `UserDefaults` suites when persistence is involved.

Use `UniLLMsUITests/` for launch and interaction coverage that genuinely needs the app process. For visible UIKit changes, manually verify common iPhone and iPad sizes, light/dark appearances if supported, Dynamic Type behavior, keyboard interactions, and safe-area layout. Agents may add or edit unit and UI test coverage, but should not run test commands that compile, build, install, or launch the app unless explicitly asked.

## Commit & Pull Request Guidelines

Recent history uses Conventional Commit-style messages such as `feat(ui): ...`, `fix(ui): ...`, `chore(xcode): ...`, `style: ...`, and `refactor(ui): ...`. Keep subjects imperative and scoped when useful. Pull requests should include a short summary, test/build results if they were run, linked issue when applicable, and screenshots or screen recordings for visible UI changes.

## Security & Configuration Tips

Do not commit Xcode user data, signing profiles, DerivedData, local simulator logs, API keys, bearer tokens, or personal provider configuration. Keep generated build artifacts in `.DerivedData/` or outside the repository. Review `project.pbxproj` diffs carefully; unrelated signing, bundle identifier, deployment target, or target membership changes should be called out explicitly.
