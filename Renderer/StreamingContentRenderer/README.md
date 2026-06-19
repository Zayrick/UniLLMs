# Streaming Content Renderer

React/Vite source for the assistant response renderer loaded by `StreamingContentView`.

## Workflow

Install dependencies through npm:

```bash
npm install
```

Build the app-bundled renderer:

```bash
npm run build
```

The build writes directly to:

```text
../../UniLLMs/Resources/StreamingContentRenderer/
```

`index.html` is the Vite HTML entry and the primary file loaded by Swift.

## Bundle Layout

Vite emits `index.html` and bundled JS/CSS into `StreamingContentRendererAssets.bundle`.

Math rendering uses KaTeX through normal npm imports. KaTeX CSS and fonts are resolved by Vite as build assets, so there is no renderer-specific static math runtime directory.

The `.bundle` suffix is intentional. Xcode preserves `.bundle` directories when copying app resources; ordinary resource folders can be flattened, which would break relative paths from the HTML file.

The production HTML is adjusted by `vite.config.ts` to load the bundled renderer as a deferred classic script. `StreamingContentView` loads this file through `WKWebView.loadFileURL`, and module scripts do not run reliably from `file://` URLs.

## Runtime Contract

The renderer must expose:

```ts
window.streamingRenderer.configure(configuration)
window.streamingRenderer.setTimeline(items, options)
window.streamingRenderer.requestHeightUpdate()
```

Height updates are posted to:

```ts
window.webkit.messageHandlers.heightUpdate.postMessage(height)
```

Keep this bridge compatible with `StreamingContentView.swift`.
