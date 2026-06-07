# StreamingContentRenderer Vendor Bundle

This bundle vendors non-LaTeX browser dependencies used by `StreamingContentRenderer.html`.

MathJax and LaTeX rendering resources are not vendored. MathJax, its font package, and LaTeX rendering behavior continue to load exactly as configured in `StreamingContentRenderer.html`.

## Vendored Packages

| Package | Version | Local files | Original CDN/npm source |
| --- | --- | --- | --- |
| `marked` | `18.0.5` | `marked/marked.umd.js`, `marked/marked.umd.js.map`, `marked/LICENSE`, `marked/package.json` | npm: `https://www.npmjs.com/package/marked/v/18.0.5`; CDN: `https://cdn.jsdelivr.net/npm/marked@18.0.5/+esm` |
| `dompurify` | `3.3.3` | `dompurify/purify.min.js`, `dompurify/purify.min.js.map`, `dompurify/LICENSE`, `dompurify/package.json` | npm: `https://www.npmjs.com/package/dompurify/v/3.3.3`; CDN: `https://cdn.jsdelivr.net/npm/dompurify@3.3.3/+esm` |
| `morphdom` | `2.7.8` | `morphdom/morphdom-umd.min.js`, `morphdom/LICENSE`, `morphdom/package.json` | npm: `https://www.npmjs.com/package/morphdom/v/2.7.8`; CDN: `https://cdn.jsdelivr.net/npm/morphdom@2.7.8/+esm` |
| `@highlightjs/cdn-assets` | `11.11.1` | `highlight.js/highlight.min.js`, `highlight.js/styles/github.min.css`, `highlight.js/styles/github-dark.min.css`, `highlight.js/LICENSE`, `highlight.js/package.json` | npm: `https://www.npmjs.com/package/@highlightjs/cdn-assets/v/11.11.1`; CDN: `https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/+esm`, `https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/styles/github.min.css`, `https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/styles/github-dark.min.css` |
