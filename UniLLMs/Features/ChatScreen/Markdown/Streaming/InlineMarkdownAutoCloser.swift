//
//  InlineMarkdownAutoCloser.swift
//  UniLLMs
//
//  Predictive completion for the trailing edge of streamed markdown. While a
//  block is open the renderer asks the auto-closer for a "safe to render"
//  version of its raw markdown so that dangling inline markers do not flip
//  styling on every new character. The closer only adds synthetic closers at
//  the very tail; the source itself is never mutated.
//
//  Strategy:
//  - Walk the input once with a tiny state machine that ignores escaped chars
//    and verbatim segments (inline code spans `…` and inline math `$…$`).
//  - For unclosed emphasis markers (**, __, *, _, ~~), append a mirroring
//    closer so the parser produces stable styled output.
//  - For an unclosed inline link `[text](url`, close with `)`.
//  - For an unclosed inline code span, close with the same backtick run.
//  - Inline math (`$…$`) is intentionally NOT auto-closed because the user
//    wants raw LaTeX text shown until the closer arrives, at which point the
//    renderer naturally swaps to the math image attachment.
//
//  Created by Zayrick on 2026/5/21.
//

import Foundation

enum InlineMarkdownAutoCloser {
    static func autoClosed(_ source: String) -> String {
        guard !source.isEmpty else { return source }
        let suffix = computeClosingSuffix(for: source)
        return suffix.isEmpty ? source : source + suffix
    }

    /// Computes only the trailing suffix that should be appended for previewing.
    /// Exposed so callers can mark the synthetic region (e.g. for diffing).
    static func computeClosingSuffix(for source: String) -> String {
        var closers: [String] = []
        var index = source.startIndex
        // Inline code state: backtick run length currently active (0 = not in code).
        var codeFenceRun = 0
        // Inline math state ($…$, single dollar only).
        var inInlineMath = false
        // Pending link state after `]( ` — capture parenthesis depth and whether opener exists.
        var linkParenDepth = 0
        var insideLinkURL = false

        while index < source.endIndex {
            let ch = source[index]

            if ch == "\\", let nextIndex = source.index(index, offsetBy: 1, limitedBy: source.endIndex), nextIndex < source.endIndex {
                index = source.index(after: nextIndex)
                continue
            }

            if codeFenceRun > 0 {
                if ch == "`" {
                    let run = consecutiveBackticks(in: source, from: index)
                    if run == codeFenceRun {
                        codeFenceRun = 0
                        index = source.index(index, offsetBy: run)
                        continue
                    }
                    index = source.index(index, offsetBy: run)
                    continue
                }
                index = source.index(after: index)
                continue
            }

            if inInlineMath {
                if ch == "$" {
                    inInlineMath = false
                }
                index = source.index(after: index)
                continue
            }

            if insideLinkURL {
                if ch == "(" {
                    linkParenDepth += 1
                } else if ch == ")" {
                    linkParenDepth -= 1
                    if linkParenDepth == 0 {
                        insideLinkURL = false
                    }
                } else if ch == "\n" {
                    // Newline in URL aborts the link in CommonMark; rewind state.
                    insideLinkURL = false
                    linkParenDepth = 0
                }
                index = source.index(after: index)
                continue
            }

            if ch == "`" {
                let run = consecutiveBackticks(in: source, from: index)
                codeFenceRun = run
                index = source.index(index, offsetBy: run)
                continue
            }

            if ch == "$" {
                // Treat $ as inline math opener only when followed by non-space and
                // there is no immediate digit/whitespace ambiguity. The proper
                // closer detection is the same as CommonMark-extension behaviour.
                if isInlineMathDollar(at: index, in: source) {
                    inInlineMath = true
                }
                index = source.index(after: index)
                continue
            }

            if ch == "]" {
                // Look for "](" following — that begins a link target.
                let afterBracket = source.index(after: index)
                if afterBracket < source.endIndex, source[afterBracket] == "(" {
                    insideLinkURL = true
                    linkParenDepth = 1
                    index = source.index(after: afterBracket)
                    continue
                }
                index = source.index(after: index)
                continue
            }

            index = source.index(after: index)
        }

        if insideLinkURL {
            closers.append(String(repeating: ")", count: max(1, linkParenDepth)))
        }
        if codeFenceRun > 0 {
            closers.append(String(repeating: "`", count: codeFenceRun))
        }
        // Inline math is left open intentionally (see file header).

        // After verbatim spans are closed we can scan the resulting "plain"
        // source for unbalanced emphasis markers. Doing this in a second pass
        // keeps the verbatim handling above straightforward.
        let plain = source + closers.joined()
        let emphasisClosers = emphasisClosingSuffix(for: plain)
        return closers.joined() + emphasisClosers
    }

    // MARK: - Emphasis balancing

    private static func emphasisClosingSuffix(for source: String) -> String {
        // Stack of open emphasis runs we have seen, e.g. "**", "*", "_", "~~".
        var stack: [String] = []
        var index = source.startIndex
        var codeFenceRun = 0
        var inInlineMath = false
        var insideLinkURL = false
        var linkParenDepth = 0

        while index < source.endIndex {
            let ch = source[index]

            if ch == "\\", let nextIndex = source.index(index, offsetBy: 1, limitedBy: source.endIndex), nextIndex < source.endIndex {
                index = source.index(after: nextIndex)
                continue
            }

            if codeFenceRun > 0 {
                if ch == "`" {
                    let run = consecutiveBackticks(in: source, from: index)
                    if run == codeFenceRun { codeFenceRun = 0 }
                    index = source.index(index, offsetBy: run)
                    continue
                }
                index = source.index(after: index)
                continue
            }
            if inInlineMath {
                if ch == "$" { inInlineMath = false }
                index = source.index(after: index)
                continue
            }
            if insideLinkURL {
                if ch == "(" { linkParenDepth += 1 }
                else if ch == ")" {
                    linkParenDepth -= 1
                    if linkParenDepth == 0 { insideLinkURL = false }
                } else if ch == "\n" {
                    insideLinkURL = false
                    linkParenDepth = 0
                }
                index = source.index(after: index)
                continue
            }

            if ch == "`" {
                let run = consecutiveBackticks(in: source, from: index)
                codeFenceRun = run
                index = source.index(index, offsetBy: run)
                continue
            }
            if ch == "$", isInlineMathDollar(at: index, in: source) {
                inInlineMath = true
                index = source.index(after: index)
                continue
            }
            if ch == "]", source.index(after: index) < source.endIndex, source[source.index(after: index)] == "(" {
                insideLinkURL = true
                linkParenDepth = 1
                index = source.index(source.index(after: index), offsetBy: 1)
                continue
            }

            if ch == "*" || ch == "_" {
                let run = consecutiveChars(in: source, from: index, character: ch)
                let token = String(repeating: ch, count: min(run, 2))
                if let top = stack.last, top == token {
                    stack.removeLast()
                } else if run >= 2, stack.last == String(ch) {
                    // We have an opener "*" but encountered "**" — treat as
                    // closing the single-char opener and opening a fresh "**".
                    stack.removeLast()
                    stack.append("**")
                } else {
                    stack.append(token)
                }
                index = source.index(index, offsetBy: run)
                continue
            }

            if ch == "~" {
                let run = consecutiveChars(in: source, from: index, character: ch)
                if run >= 2 {
                    let token = "~~"
                    if stack.last == token { stack.removeLast() } else { stack.append(token) }
                    index = source.index(index, offsetBy: run)
                    continue
                }
                index = source.index(after: index)
                continue
            }

            index = source.index(after: index)
        }

        // Build closing string in LIFO order.
        return stack.reversed().joined()
    }

    // MARK: - Helpers

    private static func consecutiveBackticks(in source: String, from index: String.Index) -> Int {
        consecutiveChars(in: source, from: index, character: "`")
    }

    private static func consecutiveChars(in source: String, from index: String.Index, character: Character) -> Int {
        var count = 0
        var cursor = index
        while cursor < source.endIndex, source[cursor] == character {
            count += 1
            cursor = source.index(after: cursor)
        }
        return count
    }

    private static func isInlineMathDollar(at index: String.Index, in source: String) -> Bool {
        // Reject `$$` (display math owned by the block layer).
        let next = source.index(after: index)
        if next < source.endIndex, source[next] == "$" { return false }
        // Require non-space after the opener (CommonMark math extension rule).
        if next < source.endIndex {
            let after = source[next]
            return !after.isWhitespace
        }
        return false
    }
}
