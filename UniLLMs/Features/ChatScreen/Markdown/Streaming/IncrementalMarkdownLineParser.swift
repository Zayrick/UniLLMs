//
//  IncrementalMarkdownLineParser.swift
//  UniLLMs
//
//  Line-based block parser used by the incremental streaming view. Unlike the
//  legacy `ChatMarkdownStreamSegmenter` which only handed out finished
//  top-level segments as opaque markdown strings, this parser maintains the
//  full block list across appends with stable IDs, exposing both still-open
//  and closed blocks to the renderer so per-block views can mutate in place.
//
//  Created by Zayrick on 2026/5/21.
//

import Foundation

struct IncrementalMarkdownLineParser {
    private struct Line {
        let text: String
        let isComplete: Bool
    }

    private var blocks: [IncrementalMarkdownBlock] = []
    /// Holds the trailing partial line (no newline yet) and, when non-empty,
    /// records which block already absorbed it so the next append can roll the
    /// partial state back before re-ingesting the extended line.
    private var pendingPartialLine: String = ""
    private var pendingPartialOwner: IncrementalMarkdownBlockID?
    private var nextBlockSequence: UInt64 = 0
    private var nextRevision: UInt64 = 0

    /// The current ordered block list, including any still-open block at the end.
    var currentBlocks: [IncrementalMarkdownBlock] {
        blocks
    }

    /// Feeds a markdown chunk into the parser and returns the updated block
    /// list. Stable block IDs let callers diff against their previous render.
    mutating func append(_ chunk: String) -> [IncrementalMarkdownBlock] {
        guard !chunk.isEmpty else {
            return blocks
        }

        rollBackPendingPartial()

        let normalised = Self.normalisedLineEndings(chunk)
        let combined = pendingPartialLine + normalised
        pendingPartialLine = ""
        pendingPartialOwner = nil

        var newLines: [Line] = []
        var cursor = combined.startIndex
        while cursor < combined.endIndex {
            if let newlineRange = combined.range(of: "\n", range: cursor..<combined.endIndex) {
                newLines.append(Line(text: String(combined[cursor..<newlineRange.lowerBound]), isComplete: true))
                cursor = newlineRange.upperBound
            } else {
                let tail = String(combined[cursor..<combined.endIndex])
                newLines.append(Line(text: tail, isComplete: false))
                break
            }
        }

        for line in newLines {
            ingest(line: line)
        }

        return blocks
    }

    /// Marks the stream as finished, closing any still-open block.
    mutating func finish() -> [IncrementalMarkdownBlock] {
        // Any pending partial line was already absorbed into the owning block;
        // no further action needed beyond closing open blocks.
        pendingPartialLine = ""
        pendingPartialOwner = nil
        for index in blocks.indices where !blocks[index].isClosed {
            blocks[index].isClosed = true
            blocks[index].revision = bumpRevision()
        }
        return blocks
    }

    mutating func reset() {
        blocks.removeAll()
        pendingPartialLine = ""
        pendingPartialOwner = nil
        nextBlockSequence = 0
        nextRevision = 0
    }

    // MARK: - Ingestion

    /// Reverses the previous tick's partial-line ingestion so the next chunk
    /// can be processed as if the partial line had not been seen yet.
    private mutating func rollBackPendingPartial() {
        guard !pendingPartialLine.isEmpty,
              let ownerID = pendingPartialOwner,
              let index = blocks.firstIndex(where: { $0.id == ownerID }) else {
            return
        }

        let raw = blocks[index].rawMarkdown
        guard raw.hasSuffix(pendingPartialLine) else {
            // Owner block was already mutated structurally; drop the partial state.
            return
        }
        blocks[index].rawMarkdown = String(raw.dropLast(pendingPartialLine.count))
        blocks[index].revision = bumpRevision()

        // If the rollback emptied the block AND we created it just to hold the
        // partial line, remove it entirely so re-classification can pick a
        // different kind once a complete line arrives.
        if blocks[index].rawMarkdown.isEmpty, !blocks[index].isClosed {
            blocks.remove(at: index)
        }
    }

    private mutating func ingest(line: Line) {
        if let lastIndex = blocks.indices.last, !blocks[lastIndex].isClosed {
            if extendOpenBlock(at: lastIndex, with: line) {
                return
            }
            blocks[lastIndex].isClosed = true
            blocks[lastIndex].revision = bumpRevision()
        }

        startNewBlock(with: line)
    }

    /// Tries to extend the currently-open block. Returns true if the line was
    /// absorbed; false if the open block should be closed and a new one started.
    private mutating func extendOpenBlock(at index: Int, with line: Line) -> Bool {
        switch blocks[index].kind {
        case let .fencedCode(fence, _):
            appendLine(line, to: index)
            if line.isComplete, Self.isFencedCodeClose(line.text, openingFence: fence) {
                blocks[index].isClosed = true
            }
            return true

        case let .displayMath(opener):
            appendLine(line, to: index)
            if Self.isDisplayMathClose(blocks[index].rawMarkdown, opener: opener) {
                blocks[index].isClosed = true
                clearPendingPartialIfOwned(by: blocks[index].id)
            }
            return true

        case .htmlDetails:
            appendLine(line, to: index)
            if Self.htmlDetailsBalanced(in: blocks[index].rawMarkdown) {
                blocks[index].isClosed = true
                clearPendingPartialIfOwned(by: blocks[index].id)
            }
            return true

        case .htmlOther:
            if line.isComplete, Self.isBlankLine(line.text) {
                blocks[index].isClosed = true
                blocks[index].revision = bumpRevision()
                return false
            }
            appendLine(line, to: index)
            if Self.htmlOtherBalanced(in: blocks[index].rawMarkdown) {
                blocks[index].isClosed = true
                clearPendingPartialIfOwned(by: blocks[index].id)
            }
            return true

        case .table:
            if line.isComplete, Self.isBlankLine(line.text) {
                blocks[index].isClosed = true
                blocks[index].revision = bumpRevision()
                return false
            }
            if line.isComplete, !Self.isPotentialTableRow(line.text) {
                return false
            }
            appendLine(line, to: index)
            return true

        case .textual:
            if line.isComplete, Self.isBlankLine(line.text) {
                blocks[index].isClosed = true
                blocks[index].revision = bumpRevision()
                return false
            }
            if line.isComplete, Self.isInterruptingBlockStart(line.text) {
                return false
            }
            appendLine(line, to: index)
            promoteToTableIfPossible(at: index)
            return true

        case .image, .thematicBreak:
            return false
        }
    }

    private mutating func promoteToTableIfPossible(at index: Int) {
        let rawLines = blocks[index].rawMarkdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        // Need at least the header line (complete) and the delimiter (complete).
        // Split keeps a trailing empty element when the source ends with "\n".
        let completeLines = rawLines.dropLast(rawLines.last?.isEmpty == true ? 1 : 0)
        guard completeLines.count >= 2,
              Self.detectTableStart(lines: Array(completeLines.prefix(2))) else {
            return
        }
        blocks[index].kind = .table
        blocks[index].revision = bumpRevision()
    }

    private mutating func startNewBlock(with line: Line) {
        if line.isComplete, Self.isBlankLine(line.text) {
            // Discard inter-block blank lines.
            return
        }

        let kind = Self.classifyOpening(line: line.text)
        let id = nextBlockID()
        let raw: String
        if line.isComplete {
            raw = line.text + "\n"
        } else {
            raw = line.text
            pendingPartialLine = line.text
            pendingPartialOwner = id
        }
        let block = IncrementalMarkdownBlock(
            id: id,
            kind: kind,
            rawMarkdown: raw,
            isClosed: false,
            revision: bumpRevision()
        )
        blocks.append(block)

        switch kind {
        case .thematicBreak, .image:
            blocks[blocks.count - 1].isClosed = true
            clearPendingPartialIfOwned(by: id)
        case let .displayMath(opener):
            if Self.isDisplayMathClose(raw, opener: opener) {
                blocks[blocks.count - 1].isClosed = true
                clearPendingPartialIfOwned(by: id)
            }
        case .htmlDetails:
            if Self.htmlDetailsBalanced(in: raw) {
                blocks[blocks.count - 1].isClosed = true
                clearPendingPartialIfOwned(by: id)
            }
        case .htmlOther:
            if Self.htmlOtherBalanced(in: raw) {
                blocks[blocks.count - 1].isClosed = true
                clearPendingPartialIfOwned(by: id)
            }
        default:
            break
        }
    }

    private mutating func appendLine(_ line: Line, to index: Int) {
        if line.isComplete {
            blocks[index].rawMarkdown += line.text + "\n"
        } else {
            blocks[index].rawMarkdown += line.text
            pendingPartialLine = line.text
            pendingPartialOwner = blocks[index].id
        }
        blocks[index].revision = bumpRevision()
    }

    private mutating func clearPendingPartialIfOwned(by id: IncrementalMarkdownBlockID) {
        guard pendingPartialOwner == id else {
            return
        }
        pendingPartialLine = ""
        pendingPartialOwner = nil
    }

    private mutating func nextBlockID() -> IncrementalMarkdownBlockID {
        defer { nextBlockSequence += 1 }
        return IncrementalMarkdownBlockID(value: nextBlockSequence)
    }

    private mutating func bumpRevision() -> UInt64 {
        defer { nextRevision += 1 }
        return nextRevision
    }

    // MARK: - Classification helpers

    private static func classifyOpening(line: String) -> IncrementalMarkdownBlockKind {
        if let fence = fenceMarker(in: line) {
            let language = fenceLanguage(in: line, fence: fence)
            return .fencedCode(fence: fence, language: language)
        }
        if let opener = displayMathOpener(in: line) {
            return .displayMath(opener: opener)
        }
        if startsHTMLDetails(line) {
            return .htmlDetails
        }
        if startsHTMLBlock(line) {
            return .htmlOther
        }
        if isStandaloneImageLine(line) {
            return .image
        }
        if isThematicBreak(line) {
            return .thematicBreak
        }
        return .textual
    }

    private static func isInterruptingBlockStart(_ line: String) -> Bool {
        if fenceMarker(in: line) != nil { return true }
        if displayMathOpener(in: line) != nil { return true }
        if startsHTMLDetails(line) { return true }
        if startsHTMLBlock(line) { return true }
        if isStandaloneImageLine(line) { return true }
        if isThematicBreak(line) { return true }
        if isATXHeading(line) { return true }
        return false
    }

    private static func fenceMarker(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else {
            return nil
        }
        let count = trimmed.prefix { $0 == first }.count
        return count >= 3 ? String(repeating: first, count: count) : nil
    }

    private static func fenceLanguage(in line: String, fence: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(fence) else { return nil }
        let after = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
        return after.isEmpty ? nil : after
    }

    static func isFencedCodeClose(_ line: String, openingFence: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = openingFence.first else { return false }
        let count = trimmed.prefix { $0 == marker }.count
        guard count >= openingFence.count else { return false }
        // The closer must consist purely of the fence character.
        return trimmed.allSatisfy { $0 == marker }
    }

    private static func displayMathOpener(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$$") { return "$$" }
        if trimmed.hasPrefix("\\[") { return "\\[" }
        return nil
    }

    private static func isDisplayMathClose(_ markdown: String, opener: String) -> Bool {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= opener.count * 2 else { return false }
        switch opener {
        case "$$":
            return trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$")
        case "\\[":
            return trimmed.hasPrefix("\\[") && trimmed.hasSuffix("\\]")
        default:
            return false
        }
    }

    private static func startsHTMLDetails(_ line: String) -> Bool {
        ChatMarkdownHTMLSupport.startsWithOpeningDetailsTag(line)
    }

    private static func startsHTMLBlock(_ line: String) -> Bool {
        for token in ChatMarkdownHTMLSupport.tokens(in: line) {
            switch token {
            case let .text(text), let .cdata(text):
                if !ChatMarkdownHTMLSupport.decodeEntities(in: text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                    return false
                }
            case .comment, .declaration, .processingInstruction:
                return true
            case let .tag(tag):
                guard !tag.isClosing else {
                    return false
                }
                return ChatMarkdownHTMLSupport.blockTagNames.contains(tag.name)
                    || ChatMarkdownHTMLSupport.disallowedRawHTMLTagNames.contains(tag.name)
            }
        }

        return false
    }

    private static func htmlDetailsBalanced(in markdown: String) -> Bool {
        var depth = 0
        var seenOpening = false
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let balance = ChatMarkdownHTMLSupport.detailsTagBalance(inHTML: String(rawLine))
            depth += balance.openingCount
            depth = max(0, depth - balance.closingCount)
            seenOpening = seenOpening || balance.openingCount > 0
        }
        return seenOpening && depth == 0
    }

    private static func htmlOtherBalanced(in markdown: String) -> Bool {
        var firstTagName: String?
        var depth = 0
        var sawRawHTMLBoundary = false

        for token in ChatMarkdownHTMLSupport.tokens(in: markdown) {
            switch token {
            case .comment, .declaration, .processingInstruction:
                sawRawHTMLBoundary = true
            case let .tag(tag):
                guard ChatMarkdownHTMLSupport.blockTagNames.contains(tag.name)
                        || ChatMarkdownHTMLSupport.disallowedRawHTMLTagNames.contains(tag.name) else {
                    continue
                }

                if firstTagName == nil {
                    guard !tag.isClosing else {
                        return true
                    }
                    firstTagName = tag.name
                    sawRawHTMLBoundary = true
                    if tag.isSelfClosing {
                        return true
                    }
                    depth = 1
                    continue
                }

                guard tag.name == firstTagName else {
                    continue
                }
                if tag.isClosing {
                    depth = max(0, depth - 1)
                    if depth == 0 {
                        return true
                    }
                } else if !tag.isSelfClosing {
                    depth += 1
                }
            case .text, .cdata:
                continue
            }
        }

        return sawRawHTMLBoundary && firstTagName == nil
    }

    private static func isStandaloneImageLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("![") && trimmed.contains("](") && trimmed.hasSuffix(")")
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "-" || marker == "*" || marker == "_" else {
            return false
        }
        let compact = trimmed.filter { !$0.isWhitespace }
        return compact.count >= 3 && compact.allSatisfy { $0 == marker }
    }

    private static func isATXHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return false }
        let after = trimmed.dropFirst(hashes)
        return after.isEmpty || after.first?.isWhitespace == true
    }

    /// Detects the start of a pipe-style table once a header line and a
    /// delimiter line are both available. Called from the renderer when a
    /// textual block has accumulated at least two lines.
    static func detectTableStart(lines: [String]) -> Bool {
        guard lines.count >= 2 else { return false }
        return isPotentialTableRow(lines[0]) && isTableDelimiter(lines[1])
    }

    static func isPotentialTableRow(_ line: String) -> Bool {
        line.contains("|") && !isBlankLine(line)
    }

    static func isTableDelimiter(_ line: String) -> Bool {
        let cells = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .drop(while: { $0.isEmpty })
        var trimmed = Array(cells)
        if trimmed.last == "" { trimmed.removeLast() }
        guard trimmed.count >= 2 else { return false }
        return trimmed.allSatisfy { cell in
            guard !cell.isEmpty else { return false }
            var content = cell
            if content.first == ":" { content.removeFirst() }
            if content.last == ":" { content.removeLast() }
            return !content.isEmpty && content.allSatisfy { $0 == "-" }
        }
    }

    private static func isBlankLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func normalisedLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
