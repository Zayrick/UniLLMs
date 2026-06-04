# UniLLMs

<p align="center">
  <img src="UniLLMs/Assets.xcassets/AppIcon.appiconset/Tinted.png" width="128" height="128" alt="UniLLMs app icon">
</p>

UniLLMs is a native iOS LLM chat client for configuring multiple model providers and managing conversations, system prompts, memories, tools, MCP servers, and attachments in one app.

## Features

- Configure OpenRouter, OpenAI, Anthropic, Gemini, Pollinations, and OpenAI-compatible providers.
- Manage models, system prompts, long-term memories, and tool settings.
- Render Markdown, code blocks, tables, math, images, and attachment previews.
- Configure MCP servers to connect external tools to the chat runtime.
- Access permission status, project information, contact details, source repository, and privacy policy from Settings.

## Privacy

UniLLMs does not operate an analytics service and does not collect personal information, usage telemetry, advertising identifiers, crash reports, or diagnostic logs from your device.

Conversations, provider configurations, API keys, model metadata, memories, system prompts, tool settings, MCP server settings, and app preferences are stored locally. When you send a message, the app sends the conversation content and context required to complete the request to the provider you configured. If you enable MCP servers, custom API bases, or third-party tools, related requests are also sent to the endpoints you configured. Review those services' terms, logging behavior, retention policies, and privacy policies before using them.

## Development

Open the Xcode project:

```sh
open UniLLMs.xcodeproj
```

List available schemes:

```sh
xcodebuild -list -project UniLLMs.xcodeproj
```

Compile the iOS Simulator app target without launching the app:

```sh
xcodebuild -project UniLLMs.xcodeproj \
  -scheme UniLLMs \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .DerivedData \
  build
```

Compile the test bundle without running tests:

```sh
xcodebuild build-for-testing \
  -project UniLLMs.xcodeproj \
  -scheme UniLLMs \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .DerivedData \
  -only-testing:UniLLMsTests
```

## Dependencies

Dependencies are managed with Swift Package Manager. Locked versions are recorded in `UniLLMs.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

- `swift-markdown`
- `swift-cmark`
- `Yams`

## License

UniLLMs is licensed under the GNU Affero General Public License v3.0. The SPDX identifier is `AGPL-3.0`. See [LICENSE](LICENSE) for the full license text.

Copyright (C) 2026 Zayrick.

This software is distributed under AGPLv3 without any express or implied warranty. See `LICENSE` for the full terms.

## Contact

- Email: tvefxt@gmail.com
- Source: https://github.com/Zayrick/UniLLMs
