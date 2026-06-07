# CDN to Local Vendor Migration

This document explains how `StreamingContentRenderer.html` was changed so that non-LaTeX JavaScript and CSS dependencies load from local app resources instead of remote CDN URLs.

## Scope

The migration localizes only the Markdown, HTML sanitizing, DOM patching, and syntax highlighting dependencies used by the streaming renderer:

- `marked@18.0.5`
- `dompurify@3.3.3`
- `morphdom@2.7.8`
- `@highlightjs/cdn-assets@11.11.1`

MathJax and all LaTeX rendering resources were intentionally left remote. The MathJax configuration, script URL, font loading behavior, and LaTeX rendering logic were not changed.

## What Changed

Before the migration, `StreamingContentRenderer.html` loaded these dependencies from `cdn.jsdelivr.net`:

- Highlight.js CSS themes:
  - `https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/styles/github.min.css`
  - `https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/styles/github-dark.min.css`
- ESM JavaScript imports:
  - `https://cdn.jsdelivr.net/npm/marked@18.0.5/+esm`
  - `https://cdn.jsdelivr.net/npm/dompurify@3.3.3/+esm`
  - `https://cdn.jsdelivr.net/npm/morphdom@2.7.8/+esm`
  - `https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/+esm`

After the migration, the renderer loads local files from:

```text
StreamingContentRendererVendor.bundle/
```

The original CDN URLs remain in HTML comments next to the local replacements so that the source of each vendored file is still visible.

## Local File Layout

The local vendor files live under `StreamingContentRendererVendor.bundle`:

```text
StreamingContentRendererVendor.bundle/
  README.md
  marked/
    LICENSE
    marked.umd.js
    marked.umd.js.map
    package.json
  dompurify/
    LICENSE
    package.json
    purify.min.js
    purify.min.js.map
  morphdom/
    LICENSE
    morphdom-umd.min.js
    package.json
  highlight.js/
    LICENSE
    highlight.min.js
    package.json
    styles/
      github-dark.min.css
      github.min.css
```

The `.bundle` suffix is intentional. Xcode copies `.bundle` directories as preserved resource bundles, which avoids flattening files such as `LICENSE`, `package.json`, and `README.md` into the same app bundle directory.

## Loading Model

The previous implementation used an inline ES module script with remote imports. The local implementation loads browser-ready UMD/global builds in dependency order:

```html
<script src="StreamingContentRendererVendor.bundle/marked/marked.umd.js"></script>
<script src="StreamingContentRendererVendor.bundle/dompurify/purify.min.js"></script>
<script src="StreamingContentRendererVendor.bundle/morphdom/morphdom-umd.min.js"></script>
<script src="StreamingContentRendererVendor.bundle/highlight.js/highlight.min.js"></script>
```

Those global objects are then assigned to the names expected by `StreamingContentRenderer.js`:

```js
window.streamingRendererMarked = window.marked;
window.streamingRendererDOMPurify = window.DOMPurify;
window.streamingRendererMorphdom = window.morphdom;
window.streamingRendererHLJS = window.hljs;
window.dispatchEvent(new Event("streamingRendererMarkedReady"));
```

This preserves the existing renderer integration while removing the non-LaTeX CDN runtime dependency.

## How the Vendor Files Were Produced

The packages were downloaded from npm as tarballs:

```bash
mkdir -p /tmp/unillms-vendor
npm pack marked@18.0.5 dompurify@3.3.3 morphdom@2.7.8 @highlightjs/cdn-assets@11.11.1 --pack-destination /tmp/unillms-vendor
```

Each tarball was extracted to a separate temporary directory. Only browser runtime files plus license and package metadata were copied into `StreamingContentRendererVendor.bundle`.

## Verification

The migration was checked with these validations:

```bash
perl -0pe 's/<!--.*?-->//sg' UniLLMs/Resources/StreamingContentRenderer/StreamingContentRenderer.html | rg 'cdn.jsdelivr.net/npm/(marked|dompurify|morphdom|highlight.js|@highlightjs)'
```

Expected result: no output. MathJax CDN URLs are allowed to remain.

```bash
find UniLLMs/Resources/StreamingContentRenderer/StreamingContentRendererVendor.bundle -maxdepth 3 -type f | sort
```

Expected result: the local files listed in this document.

The app target was also validated with a compile-only Simulator build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project UniLLMs.xcodeproj -scheme UniLLMs -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .DerivedData build
```

The build succeeded, and Xcode copied `StreamingContentRendererVendor.bundle` into the app product as a preserved bundle resource.
