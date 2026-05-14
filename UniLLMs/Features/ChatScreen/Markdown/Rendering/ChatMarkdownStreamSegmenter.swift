//
//  ChatMarkdownStreamSegmenter.swift
//  UniLLMs
//
//  Incremental top-level Markdown block segmentation for streamed chat content.
//  Created by Zayrick on 2026/5/13.
//

import Foundation

struct ChatMarkdownStreamUpdate {
    let completedSegments: [String]
    let currentSegment: String?
}

struct ChatMarkdownStreamSegmenter {
    private struct Line {
        let text: String
        let isComplete: Bool
    }

    private struct SegmentEnd {
        let segmentLineCount: Int
        let consumedLineCount: Int
    }

    private var buffer = ""

    mutating func append(_ markdown: String) -> ChatMarkdownStreamUpdate {
        guard !markdown.isEmpty else {
            return ChatMarkdownStreamUpdate(
                completedSegments: [],
                currentSegment: currentSegment
            )
        }

        buffer += Self.normalizedLineEndings(markdown)
        return consumeCompletedSegments(finishing: false)
    }

    mutating func finish() -> ChatMarkdownStreamUpdate {
        consumeCompletedSegments(finishing: true)
    }

    mutating func reset() {
        buffer = ""
    }

    private var currentSegment: String? {
        Self.renderableSegment(buffer)
    }

    private mutating func consumeCompletedSegments(finishing: Bool) -> ChatMarkdownStreamUpdate {
        var lines = Self.lines(in: buffer)
        var completedSegments: [String] = []

        while true {
            Self.consumeLeadingBlankLines(from: &lines)
            guard !lines.isEmpty else {
                break
            }

            guard let segmentEnd = Self.completedSegmentEnd(in: lines, finishing: finishing) else {
                break
            }

            let segment = Self.markdown(from: Array(lines.prefix(segmentEnd.segmentLineCount)))
            if let renderableSegment = Self.renderableSegment(segment) {
                completedSegments.append(renderableSegment)
            }
            lines.removeFirst(min(segmentEnd.consumedLineCount, lines.count))
        }

        buffer = Self.markdown(from: lines)
        if finishing, let renderableSegment = Self.renderableSegment(buffer) {
            completedSegments.append(renderableSegment)
            buffer = ""
        }

        return ChatMarkdownStreamUpdate(
            completedSegments: completedSegments,
            currentSegment: currentSegment
        )
    }

    private static func completedSegmentEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        guard let firstLine = lines.first else {
            return nil
        }

        if isFencedCodeOpening(firstLine.text) {
            return fencedCodeEnd(in: lines, finishing: finishing)
        }
        if isDisplayMathOpening(firstLine.text) {
            return displayMathEnd(in: lines, finishing: finishing)
        }
        if isBlockQuoteLine(firstLine.text) {
            return blockQuoteEnd(in: lines, finishing: finishing)
        }
        if startsHTMLDetailsBlock(firstLine.text) {
            return htmlDetailsEnd(in: lines, finishing: finishing)
        }
        if isTableStart(in: lines) {
            return tableEnd(in: lines, finishing: finishing)
        }
        if firstLine.isComplete,
           isSingleLineBlock(firstLine.text) {
            return SegmentEnd(segmentLineCount: 1, consumedLineCount: 1)
        }

        return paragraphEnd(in: lines, finishing: finishing)
    }

    private static func fencedCodeEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        guard let openingFence = fenceInfo(in: lines[0].text) else {
            return nil
        }

        for index in lines.indices.dropFirst() {
            guard lines[index].isComplete,
                  let closingFence = fenceInfo(in: lines[index].text),
                  closingFence.marker == openingFence.marker,
                  closingFence.count >= openingFence.count else {
                continue
            }

            return SegmentEnd(segmentLineCount: index + 1, consumedLineCount: index + 1)
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func displayMathEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        for index in lines.indices {
            let line = lines[index]
            guard line.isComplete || finishing else {
                return nil
            }

            let candidate = markdown(from: Array(lines.prefix(index + 1)))
            guard ChatMarkdownMathDelimiterScanner.standaloneDisplayMath(in: candidate) != nil else {
                continue
            }

            let consumedLineCount: Int
            if index + 1 < lines.count,
               lines[index + 1].isComplete,
               isBlank(lines[index + 1].text) {
                consumedLineCount = index + 2
            } else {
                consumedLineCount = index + 1
            }
            return SegmentEnd(segmentLineCount: index + 1, consumedLineCount: consumedLineCount)
        }

        return nil
    }

    private static func blockQuoteEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        for index in lines.indices.dropFirst() {
            let line = lines[index]
            if isBlockQuoteLine(line.text) || isBlank(line.text) {
                continue
            }

            return SegmentEnd(segmentLineCount: index, consumedLineCount: index)
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func tableEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        guard lines.count >= 2,
              lines[0].isComplete,
              lines[1].isComplete else {
            return nil
        }

        var index = 2
        while index < lines.count {
            let line = lines[index]
            if isBlank(line.text) {
                return SegmentEnd(segmentLineCount: index, consumedLineCount: index + 1)
            }
            if isPotentialTableRow(line.text) {
                index += 1
                continue
            }

            return SegmentEnd(segmentLineCount: index, consumedLineCount: index)
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func htmlDetailsEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        var depth = 0
        var didStart = false

        for index in lines.indices {
            let line = lines[index]
            guard line.isComplete else {
                return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
            }

            let balance = ChatMarkdownHTMLSupport.detailsTagBalance(inHTML: line.text)
            depth += balance.openingCount
            depth = max(0, depth - balance.closingCount)
            didStart = didStart || balance.openingCount > 0

            guard didStart, depth == 0 else {
                continue
            }

            let consumedLineCount: Int
            if index + 1 < lines.count,
               lines[index + 1].isComplete,
               isBlank(lines[index + 1].text) {
                consumedLineCount = index + 2
            } else {
                consumedLineCount = index + 1
            }
            return SegmentEnd(segmentLineCount: index + 1, consumedLineCount: consumedLineCount)
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func paragraphEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        for index in lines.indices {
            let line = lines[index]
            guard line.isComplete else {
                return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
            }

            if index > 0,
               isBlank(line.text) {
                return SegmentEnd(segmentLineCount: index, consumedLineCount: index + 1)
            }

            if index > 0,
               isInterruptingBlockStart(at: index, in: lines) {
                return SegmentEnd(segmentLineCount: index, consumedLineCount: index)
            }
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func isInterruptingBlockStart(at index: Int, in lines: [Line]) -> Bool {
        let line = lines[index]
        if isFencedCodeOpening(line.text) ||
            isDisplayMathOpening(line.text) ||
            isBlockQuoteLine(line.text) ||
            isSingleLineBlock(line.text) {
            return true
        }

        guard index + 1 < lines.count else {
            return false
        }

        return isTableStart(in: Array(lines[index...]))
    }

    private static func isSingleLineBlock(_ line: String) -> Bool {
        isATXHeading(line) || isThematicBreak(line) || isStandaloneImageLine(line)
    }

    private static func isTableStart(in lines: [Line]) -> Bool {
        guard lines.count >= 2,
              lines[0].isComplete,
              lines[1].isComplete,
              isPotentialTableRow(lines[0].text),
              isTableDelimiter(lines[1].text) else {
            return false
        }

        return true
    }

    private static func isPotentialTableRow(_ line: String) -> Bool {
        line.contains("|") && !isBlank(line)
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let cells = tableCells(in: line)
        guard cells.count >= 2 else {
            return false
        }

        return cells.allSatisfy { cell in
            guard !cell.isEmpty else {
                return false
            }

            var content = cell
            if content.first == ":" {
                content.removeFirst()
            }
            if content.last == ":" {
                content.removeLast()
            }

            return !content.isEmpty && content.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(in line: String) -> [String] {
        var cells = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if cells.first == "" {
            cells.removeFirst()
        }
        if cells.last == "" {
            cells.removeLast()
        }

        return cells
    }

    private static func isATXHeading(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmedLine.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else {
            return false
        }

        let afterHashes = trimmedLine.dropFirst(hashes)
        return afterHashes.isEmpty || afterHashes.first?.isWhitespace == true
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmedLine.first,
              marker == "-" || marker == "*" || marker == "_" else {
            return false
        }

        let compactLine = trimmedLine.filter { !$0.isWhitespace }
        return compactLine.count >= 3 && compactLine.allSatisfy { $0 == marker }
    }

    private static func isStandaloneImageLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        return trimmedLine.hasPrefix("![") &&
            trimmedLine.contains("](") &&
            trimmedLine.hasSuffix(")")
    }

    private static func isBlockQuoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private static func startsHTMLDetailsBlock(_ line: String) -> Bool {
        ChatMarkdownHTMLSupport.startsWithOpeningDetailsTag(line)
    }

    private static func isFencedCodeOpening(_ line: String) -> Bool {
        fenceInfo(in: line) != nil
    }

    private static func isDisplayMathOpening(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        return trimmedLine == "$$" ||
            trimmedLine == "\\[" ||
            (trimmedLine.hasPrefix("$$") && trimmedLine.count > 2) ||
            (trimmedLine.hasPrefix("\\[") && trimmedLine.count > 2)
    }

    private static func fenceInfo(in line: String) -> (marker: Character, count: Int)? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmedLine.first,
              marker == "`" || marker == "~" else {
            return nil
        }

        let count = trimmedLine.prefix { $0 == marker }.count
        return count >= 3 ? (marker, count) : nil
    }

    private static func consumeLeadingBlankLines(from lines: inout [Line]) {
        while let firstLine = lines.first,
              firstLine.isComplete,
              isBlank(firstLine.text) {
            lines.removeFirst()
        }
    }

    private static func renderableSegment(_ markdown: String) -> String? {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : markdown
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func lines(in markdown: String) -> [Line] {
        guard !markdown.isEmpty else {
            return []
        }

        var lines: [Line] = []
        var startIndex = markdown.startIndex
        while startIndex < markdown.endIndex {
            if let newlineRange = markdown[startIndex...].range(of: "\n") {
                lines.append(
                    Line(
                        text: String(markdown[startIndex..<newlineRange.lowerBound]),
                        isComplete: true
                    )
                )
                startIndex = newlineRange.upperBound
            } else {
                lines.append(Line(text: String(markdown[startIndex...]), isComplete: false))
                startIndex = markdown.endIndex
            }
        }

        return lines
    }

    private static func markdown(from lines: [Line]) -> String {
        var markdown = ""
        for line in lines {
            markdown += line.text
            if line.isComplete {
                markdown += "\n"
            }
        }
        return markdown
    }

    private static func normalizedLineEndings(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
