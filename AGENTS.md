# Repository Guidelines

## Project Structure & Module Organization

`UniLLMs.xcodeproj/` contains the Xcode project, targets, and scheme metadata. The app target source lives in `UniLLMs/`. This is a UIKit app, not a SwiftUI app: `AppDelegate.swift` owns app lifecycle and the Core Data stack, `SceneDelegate.swift` connects the main scene, `Base.lproj/Main.storyboard` declares the initial `ViewController`, and `ViewController.swift` builds the current primary interface mostly in code.

Provider configuration and model metadata are handled by `LLMProviderStore.swift`, which persists Codable records in `UserDefaults`. `OpenRouterAPIClient.swift` contains the async URLSession client for loading OpenRouter models. Visual resources are in `UniLLMs/Assets.xcassets/`, including the app icon, accent color, and app background color sets. Unit tests live in `UniLLMsTests/`; UI test scaffolding lives in `UniLLMsUITests/`. `reference/Telegram-iOS/` is reference material only and should not be edited unless the user specifically asks for changes there.

## Agent-Specific Instructions

Available Xcode validation levels and AI-agent boundaries:

- Compile-only app validation is allowed with `xcodebuild ... -destination 'generic/platform=iOS Simulator' build`. This checks that the app target compiles for Simulator without booting, installing to, or launching a specific simulator.
- Compile-only test validation is allowed with `xcodebuild build-for-testing ... -destination 'generic/platform=iOS Simulator'`. This checks that the app and test bundles compile without executing tests.
- Runtime validation requires explicit user approval. Agents must not run `xcodebuild test`, `xcodebuild test-without-building`, Xcode Run/Test actions, simulator launches, `simctl install`, `simctl launch`, or equivalent commands that execute tests, install the app, or launch the app unless the user explicitly asks for that specific action.
- Archive and distribution actions require explicit user approval. Agents must not run `xcodebuild archive`, export archives, change signing/provisioning, or perform distribution-related actions unless the user explicitly asks for that specific action.

AI agents may run read-only `git` commands for inspection. Do not perform Git operations that modify repository state unless the user explicitly asks for that specific action. 

Respect unrelated local changes. The worktree may contain user edits or generated files; do not revert files you did not change. Keep edits scoped to the requested app target, test target, or documentation files.

## Freshness & Web Research Requirement

Before generating content that depends on Apple SDKs, OpenRouter APIs, OpenAI APIs, third-party libraries, command-line tools, platform behavior, or other fast-moving interfaces, AI agents must use the available web lookup, browser, or official documentation tools to verify the latest API names, signatures, request and response shapes, setup steps, deprecations, and recommended usage. This check must happen before writing implementation plans, code changes, tests, documentation, or user-facing explanations that rely on those details.

Prefer primary sources: Apple Developer Documentation, OpenRouter documentation, OpenAI documentation, official package/library documentation, release notes, and official source repositories. When the answer or implementation relies on a specific external API or behavior, summarize the verified source and date in the response or working notes. Do not rely only on model memory for modern APIs, SDK behavior, authentication details, Info.plist/privacy requirements, entitlement usage, dependency setup, or request/response schemas.

If network access or documentation lookup is unavailable, explicitly state that current web verification could not be performed before making assumptions. In that case, make the smallest well-supported change possible, avoid speculative API usage, and ask the user before proceeding when the missing information could affect correctness, security, or data compatibility.

This requirement does not weaken the repository's execution restrictions. Web research is allowed for freshness, and agents may perform the compile-only validation actions described above, but agents still must not run tests, archive, install, or launch the app unless the user explicitly asks for that specific action.

## Implementation Principles

When work depends on Apple SDKs, OpenRouter APIs, or other fast-moving interfaces, follow the Freshness & Web Research Requirement above before generating content. Do not rely on stale memory for modern APIs. If network access is unavailable, state that limitation and make the smallest well-supported assumption.

Prefer native Apple frameworks and platform conventions over third-party dependencies or custom infrastructure. Use UIKit, Foundation, URLSession, UserDefaults, Core Data, Auto Layout, asset catalogs, and XCTest directly when they solve the problem cleanly. Add dependencies, wrappers, or abstractions only when they remove real complexity or are explicitly requested.

Keep architecture and behavior extremely simple, clean, and direct. Solve the root cause instead of layering workaround code. Avoid patchwork fixes: do not accumulate special cases, duplicate state, compatibility shims, or one-off branches unless there is a documented product or platform reason. When a temporary workaround is unavoidable, keep it isolated, name the reason, and remove obsolete code around it.

## Build, Test, and Development Commands

The following commands describe the available local workflows and the AI-agent boundary for each:

- `open UniLLMs.xcodeproj` opens the project in Xcode for simulator runs and interface editing.
- `xcodebuild -list -project UniLLMs.xcodeproj` lists available targets, configurations, and schemes.
- `xcodebuild -project UniLLMs.xcodeproj -scheme UniLLMs -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .DerivedData build` compiles the app for Simulator without running it. Agents may run this.
- `xcodebuild build-for-testing -project UniLLMs.xcodeproj -scheme UniLLMs -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .DerivedData -only-testing:UniLLMsTests` compiles the app and unit test bundle without running tests. Agents may run this.
- `xcodebuild test -project UniLLMs.xcodeproj -scheme UniLLMs -destination 'platform=iOS Simulator,name=<Device Name>' -derivedDataPath .DerivedData` runs the unit and UI test targets when an appropriate simulator is available. Agents must only run this when explicitly asked.

## Coding Style & Naming Conventions

Use Swift 5 and UIKit conventions. Indent Swift with 4 spaces. Use `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and descriptive asset names such as `AppBackgroundStart`. Keep view-controller code organized into small private configuration methods, private helper methods, and focused private nested types or file-private view classes, matching the current `ViewController.swift` style.

Prefer Auto Layout constraints over frame math for persistent layout. Keep UI constants grouped in private enums when they describe a section of the interface. Use SF Symbols inline where they are configured, and provide accessibility labels for icon-only controls. Preserve UIKit lifecycle boundaries: app/session setup belongs in `AppDelegate` and `SceneDelegate`; screen behavior belongs in view controllers and view subclasses.

For any user-facing copy change, keep localization files in sync in the same edit. This includes adding, changing, or removing screen titles, row titles, section headers/footers, placeholders, button/menu/action titles, alert text, empty states, accessibility labels, and accessibility hints. Add new keys to `UniLLMs/Resources/Localizable.xcstrings` with both `en` and `zh-Hans` values, update existing translations when copy changes, and remove obsolete keys when the UI no longer references that text.

For persistence changes, keep `LLMProviderRecord` and `LLMProviderModel` Codable-compatible and consider migration for stored `UserDefaults` data. For network changes, keep `OpenRouterAPIClient` async/throws, validate URLs and HTTP status codes, and avoid logging secrets or full authorization headers.

## UIKit Setting Controls

Let UIKit own control interaction and animation whenever possible. For `UISwitch`, handle user changes from `.valueChanged`, persist the new value, and do not reload the row or section that contains the active switch. Programmatic `isOn` or `setOn(_:animated:)` updates do not send `.valueChanged`, so store-notification handlers can safely sync visible switches directly with `setOn(..., animated: false)`.

For table-backed settings, update the visible cell or accessory view directly when only displayed values change. Use `reloadRows`, `reloadSections`, or `reloadData` only when row identity, row count, or section structure changes, or when an intentional table replacement animation is part of the UX. Avoid notification-ignore counters for ordinary control updates; make store-change handlers idempotent instead.

For single-choice menu settings, prefer `UIButton` with `menu`, `showsMenuAsPrimaryAction`, `changesSelectionAsPrimaryAction`, and `UIMenu(options: .singleSelection)`. Let the button track the selected menu action and update its title; rebuild the menu only when external state changes or available choices change.

## Testing Guidelines

XCTest targets already exist. Add focused unit tests in `UniLLMsTests/` for model, store, parsing, and non-UI behavior; name new files after the subject under test, for example `LLMProviderStoreTests.swift`. Use clear XCTest names such as `testAddingProviderAssignsUniqueName()` or `test_<behavior>_<expectedResult>()`, and keep test data isolated with dedicated `UserDefaults` suites when persistence is involved.

Use `UniLLMsUITests/` for launch and interaction coverage that genuinely needs the app process. For visible UIKit changes, manually verify common iPhone and iPad sizes, light/dark appearances if supported, Dynamic Type behavior, keyboard interactions, and safe-area layout. Agents may add or edit unit and UI test coverage and may perform compile-only test validation. Agents should not run commands that execute tests, install the app, or launch the app unless explicitly asked.

## Commit & Pull Request Guidelines

Recent history uses Conventional Commit-style messages such as `feat(ui): ...`, `fix(ui): ...`, `chore(xcode): ...`, `style: ...`, and `refactor(ui): ...`. Keep subjects imperative and scoped when useful. Pull requests should include a short summary, test/build results if they were run, linked issue when applicable, and screenshots or screen recordings for visible UI changes.

## Security & Configuration Tips

Do not commit Xcode user data, signing profiles, DerivedData, local simulator logs, API keys, bearer tokens, or personal provider configuration. Keep generated build artifacts in `.DerivedData/` or outside the repository. Review `project.pbxproj` diffs carefully; unrelated signing, bundle identifier, deployment target, or target membership changes should be called out explicitly.
