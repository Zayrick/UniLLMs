//
//  IncrementalMarkdownBlock.swift
//  UniLLMs
//
//  Block model used by the incremental streaming pipeline. Each block in the
//  current stream owns a stable identity, a structural kind that reflects how
//  it should be rendered while still open, and the raw markdown source that
//  produced it. Identity lets the presentation layer reuse the existing block
//  view across ticks and apply per-region incremental updates instead of
//  rebuilding the whole stack.
//
//  Created by Zayrick on 2026/5/21.
//

import Foundation

/// Stable, monotonically increasing identifier for a streamed block. Identity
/// is allocated by the line parser; the presentation layer keys its view cache
/// by this value so a single block view can absorb many incremental updates.
struct IncrementalMarkdownBlockID: Hashable {
    let value: UInt64
}

/// Coarse structural classification of an open or closed streamed block. The
/// presentation layer maps each kind to a concrete UIView subclass, so kind
/// transitions (e.g. `paragraph` → `table`) trigger a view replacement while
/// kind-stable growth only patches the existing view.
enum IncrementalMarkdownBlockKind: Equatable {
    /// Plain paragraph / heading / list / block quote / inline-only markdown.
    /// Open blocks use the streaming tokenizer; closed blocks use the full
    /// renderer and patch into the reusable `ChatMarkdownTextView`.
    case textual

    /// Fenced code block. While open, the body is appended into a live
    /// `ChatMarkdownCodeBlockView` regardless of close state.
    case fencedCode(fence: String, language: String?)

    /// Standalone display math block (`$$...$$` or `\[...\]`). While open we
    /// render a plain-text preview; once closed we swap to `ChatMarkdownMathBlockView`.
    case displayMath(opener: String)

    /// Pipe-style table. The header and delimiter rows are detected together
    /// so the table view is created immediately and subsequent rows append.
    case table

    /// Raw HTML `<details>...</details>` block; rendered as text after close.
    case htmlDetails

    /// Standalone HTML block other than `<details>`. HTML tables are promoted
    /// to the table presentation form by the view layer.
    case htmlOther

    /// Standalone image line (`![alt](src)`).
    case image

    /// A horizontal rule.
    case thematicBreak
}

/// One block in the current stream. The block is "open" while more incoming
/// lines may extend it; "closed" once a structural boundary has been observed
/// or the stream finished.
struct IncrementalMarkdownBlock {
    let id: IncrementalMarkdownBlockID
    var kind: IncrementalMarkdownBlockKind
    var rawMarkdown: String
    var isClosed: Bool
    /// Monotonic revision number. Bumped whenever `rawMarkdown` changes so the
    /// presentation layer can short-circuit when nothing meaningful changed.
    var revision: UInt64
}
