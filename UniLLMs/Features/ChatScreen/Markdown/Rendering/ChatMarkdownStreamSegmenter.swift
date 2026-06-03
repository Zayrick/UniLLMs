//
//  ChatMarkdownStreamSegmenter.swift
//  UniLLMs
//
//  Incremental presentation-block segmentation for streamed chat content.
//  Created by Zayrick on 2026/5/13.
//

import Foundation

struct ChatMarkdownStreamUpdate {
    let completedSegments: [String]
    let currentSegment: String?
}

struct ChatMarkdownStreamSegmenter {
    private enum LazyBlockQuoteState {
        case paragraph
        case unavailable
    }

    private enum HTMLBlockEndCondition {
        case rawHTML
        case terminator(String)
        case blankLine
    }

    private struct Line {
        let text: String
        let isComplete: Bool
    }

    private struct SegmentEnd {
        let segmentLineCount: Int
        let consumedLineCount: Int
    }

    private var buffer = ""
    private var pendingCarriageReturn = false

    mutating func append(_ markdown: String) -> ChatMarkdownStreamUpdate {
        guard !markdown.isEmpty else {
            return ChatMarkdownStreamUpdate(
                completedSegments: [],
                currentSegment: currentSegment
            )
        }

        buffer += normalizedLineEndings(markdown)
        return consumeCompletedSegments(finishing: false)
    }

    mutating func finish() -> ChatMarkdownStreamUpdate {
        if pendingCarriageReturn {
            buffer += "\n"
            pendingCarriageReturn = false
        }
        return consumeCompletedSegments(finishing: true)
    }

    mutating func reset() {
        buffer = ""
        pendingCarriageReturn = false
    }

    private var currentSegment: String? {
        Self.renderableSegment(buffer)
    }

    private mutating func normalizedLineEndings(_ markdown: String) -> String {
        var text = markdown
        var normalized = ""

        if pendingCarriageReturn {
            if text.first == "\n" {
                text.removeFirst()
            }
            normalized += "\n"
            pendingCarriageReturn = false
        }

        if text.last == "\r" {
            pendingCarriageReturn = true
            text.removeLast()
        }

        normalized += Self.normalizedLineEndings(text)
        return normalized
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
        // The native details renderer spans cmark HTML blocks and Markdown body
        // children, so streaming keeps the whole details block together.
        if startsNativeDetailsBlock(firstLine.text) {
            return nativeDetailsEnd(in: lines, finishing: finishing)
        }
        if let htmlBlockEndCondition = htmlBlockEndCondition(
            for: firstLine.text,
            allowsType7: true
        ) {
            return htmlBlockEnd(
                in: lines,
                finishing: finishing,
                endCondition: htmlBlockEndCondition
            )
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
        guard let openingFence = openingFenceInfo(in: lines[0].text) else {
            return nil
        }

        for index in lines.indices.dropFirst() {
            guard lines[index].isComplete,
                  let closingFence = closingFenceInfo(in: lines[index].text),
                  closingFence.marker == openingFence.marker,
                  closingFence.count >= openingFence.count else {
                continue
            }

            return SegmentEnd(segmentLineCount: index + 1, consumedLineCount: index + 1)
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func displayMathEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        guard let closingDelimiter = displayMathClosingDelimiter(forOpeningLine: lines[0].text) else {
            return nil
        }

        for index in lines.indices {
            let line = lines[index]
            guard line.isComplete || finishing else {
                return nil
            }
            guard isDisplayMathClosingLine(line.text, delimiter: closingDelimiter) else {
                continue
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
        var openQuotedFence: (marker: Character, count: Int)?
        var lazyState = nextLazyBlockQuoteState(
            afterQuotedLine: lines[0].text,
            current: .paragraph,
            openFence: &openQuotedFence
        )

        for index in lines.indices.dropFirst() {
            let line = lines[index]
            guard line.isComplete else {
                return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
            }

            if isBlank(line.text) {
                return SegmentEnd(segmentLineCount: index, consumedLineCount: index + 1)
            }
            if isBlockQuoteLine(line.text) {
                lazyState = nextLazyBlockQuoteState(
                    afterQuotedLine: line.text,
                    current: lazyState,
                    openFence: &openQuotedFence
                )
                continue
            }
            if openQuotedFence != nil {
                return SegmentEnd(segmentLineCount: index, consumedLineCount: index)
            }
            if isLazyBlockQuoteContinuation(line.text, state: lazyState) {
                lazyState = nextLazyBlockQuoteState(afterLazyLine: line.text, current: lazyState)
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
            guard line.isComplete else {
                return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
            }

            if isBlank(line.text) {
                return SegmentEnd(segmentLineCount: index, consumedLineCount: index + 1)
            }
            if isTableBreakingBlockStart(line.text) {
                return SegmentEnd(segmentLineCount: index, consumedLineCount: index)
            }
            index += 1
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func nativeDetailsEnd(in lines: [Line], finishing: Bool) -> SegmentEnd? {
        var depth = 0
        var didStart = false
        var openFence: (marker: Character, count: Int)?

        for index in lines.indices {
            let line = lines[index]
            guard line.isComplete else {
                return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
            }

            if let fence = openFence {
                if let closingFence = closingFenceInfo(in: line.text),
                   closingFence.marker == fence.marker,
                   closingFence.count >= fence.count {
                    openFence = nil
                }
                continue
            }
            if let openingFence = openingFenceInfo(in: line.text) {
                openFence = openingFence
                continue
            }

            let balance = ChatMarkdownHTMLSupport.detailsTagBalance(inHTML: line.text)
            depth += balance.openingCount
            depth = max(0, depth - balance.closingCount)
            didStart = didStart || balance.openingCount > 0

            guard didStart, depth == 0 else {
                continue
            }

            return segmentEndIncludingFollowingBlankLine(
                lineIndex: index,
                in: lines
            )
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func htmlBlockEnd(
        in lines: [Line],
        finishing: Bool,
        endCondition: HTMLBlockEndCondition
    ) -> SegmentEnd? {
        guard lines[0].isComplete || finishing else {
            return nil
        }

        switch endCondition {
        case .rawHTML:
            for index in lines.indices {
                guard lines[index].isComplete || finishing else {
                    return nil
                }
                if containsRawHTMLBlockTerminator(lines[index].text) {
                    return segmentEndIncludingFollowingBlankLine(
                        lineIndex: index,
                        in: lines
                    )
                }
            }

        case let .terminator(terminator):
            for index in lines.indices {
                guard lines[index].isComplete || finishing else {
                    return nil
                }
                if lines[index].text.contains(terminator) {
                    return segmentEndIncludingFollowingBlankLine(
                        lineIndex: index,
                        in: lines
                    )
                }
            }

        case .blankLine:
            for index in lines.indices.dropFirst() {
                guard lines[index].isComplete || finishing else {
                    return nil
                }
                if isBlank(lines[index].text) {
                    return SegmentEnd(segmentLineCount: index, consumedLineCount: index + 1)
                }
            }
        }

        return finishing ? SegmentEnd(segmentLineCount: lines.count, consumedLineCount: lines.count) : nil
    }

    private static func segmentEndIncludingFollowingBlankLine(
        lineIndex: Int,
        in lines: [Line]
    ) -> SegmentEnd {
        let consumedLineCount: Int
        if lineIndex + 1 < lines.count,
           lines[lineIndex + 1].isComplete,
           isBlank(lines[lineIndex + 1].text) {
            consumedLineCount = lineIndex + 2
        } else {
            consumedLineCount = lineIndex + 1
        }

        return SegmentEnd(segmentLineCount: lineIndex + 1, consumedLineCount: consumedLineCount)
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
               isSetextHeadingUnderline(line.text) {
                return SegmentEnd(segmentLineCount: index + 1, consumedLineCount: index + 1)
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
            isDisplayMathOpening(line.text, allowsIndentedOpening: false) ||
            isBlockQuoteLine(line.text) ||
            startsHTMLBlock(line.text) ||
            isListStart(line.text, canInterruptParagraph: true) ||
            isSingleLineBlock(line.text) {
            return true
        }

        guard index + 1 < lines.count else {
            return false
        }

        return isTableStart(in: Array(lines[index...]))
    }

    private static func isSingleLineBlock(_ line: String) -> Bool {
        isATXHeading(line) || isThematicBreak(line)
    }

    private static func isTableStart(in lines: [Line]) -> Bool {
        guard lines.count >= 2,
              lines[0].isComplete,
              lines[1].isComplete,
              hasUnescapedPipe(lines[0].text) else {
            return false
        }

        let headerCells = tableCells(in: lines[0].text)
        let delimiterCells = tableCells(in: lines[1].text)
        return !headerCells.isEmpty &&
            headerCells.count == delimiterCells.count &&
            isTableDelimiterCells(delimiterCells)
    }

    private static func isTableDelimiterCells(_ cells: [String]) -> Bool {
        guard cells.count >= 1 else {
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
        var cells: [String] = []
        var current = ""
        var index = line.startIndex
        var openBacktickRunLength = 0

        while index < line.endIndex {
            let character = line[index]
            if character == "`" {
                let runLength = backtickRunLength(in: line, from: index)
                current.append(contentsOf: String(repeating: "`", count: runLength))
                index = line.index(index, offsetBy: runLength)
                if openBacktickRunLength == runLength {
                    openBacktickRunLength = 0
                } else if openBacktickRunLength == 0 {
                    openBacktickRunLength = runLength
                }
                continue
            }
            if character == "\\" {
                let nextIndex = line.index(after: index)
                if nextIndex < line.endIndex, line[nextIndex] == "|" {
                    current.append("|")
                    index = line.index(after: nextIndex)
                    continue
                }
            }
            if character == "|", openBacktickRunLength == 0 {
                cells.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }

        cells.append(current.trimmingCharacters(in: .whitespacesAndNewlines))

        if cells.first == "" {
            cells.removeFirst()
        }
        if cells.last == "" {
            cells.removeLast()
        }

        return cells
    }

    private static func hasUnescapedPipe(_ line: String) -> Bool {
        var index = line.startIndex
        var openBacktickRunLength = 0
        while index < line.endIndex {
            let character = line[index]
            if character == "`" {
                let runLength = backtickRunLength(in: line, from: index)
                index = line.index(index, offsetBy: runLength)
                if openBacktickRunLength == runLength {
                    openBacktickRunLength = 0
                } else if openBacktickRunLength == 0 {
                    openBacktickRunLength = runLength
                }
                continue
            }
            if character == "\\" {
                index = line.index(after: index)
                if index < line.endIndex {
                    index = line.index(after: index)
                }
                continue
            }
            if character == "|", openBacktickRunLength == 0 {
                return true
            }
            index = line.index(after: index)
        }
        return false
    }

    private static func backtickRunLength(in line: String, from index: String.Index) -> Int {
        var length = 0
        var currentIndex = index
        while currentIndex < line.endIndex, line[currentIndex] == "`" {
            length += 1
            currentIndex = line.index(after: currentIndex)
        }
        return length
    }

    private static func isATXHeading(_ line: String) -> Bool {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return false
        }
        let trimmedLine = indentedLine.trimmingCharacters(in: .whitespaces)
        let hashes = trimmedLine.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else {
            return false
        }

        let afterHashes = trimmedLine.dropFirst(hashes)
        return afterHashes.isEmpty || afterHashes.first?.isWhitespace == true
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return false
        }
        let trimmedLine = indentedLine.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmedLine.first,
              marker == "-" || marker == "*" || marker == "_" else {
            return false
        }

        let compactLine = trimmedLine.filter { !$0.isWhitespace }
        return compactLine.count >= 3 && compactLine.allSatisfy { $0 == marker }
    }

    private static func isSetextHeadingUnderline(_ line: String) -> Bool {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return false
        }
        let trimmedLine = indentedLine.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmedLine.first,
              marker == "-" || marker == "=" else {
            return false
        }

        if marker == "-", trimmedLine.count == 1 {
            return false
        }

        return !trimmedLine.isEmpty && trimmedLine.allSatisfy { $0 == marker }
    }

    private static func isBlockQuoteLine(_ line: String) -> Bool {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return false
        }
        return indentedLine.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private static func blockQuoteContentLine(_ line: String) -> String? {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return nil
        }
        let trimmedPrefix = indentedLine.trimmingCharacters(in: .whitespaces)
        guard trimmedPrefix.first == ">" else {
            return nil
        }

        var content = trimmedPrefix.dropFirst()
        if content.first == " " || content.first == "\t" {
            content = content.dropFirst()
        }
        return String(content)
    }

    private static func startsNativeDetailsBlock(_ line: String) -> Bool {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return false
        }
        return ChatMarkdownHTMLSupport.startsWithOpeningDetailsTag(indentedLine)
    }

    private static func startsHTMLBlock(_ line: String) -> Bool {
        htmlBlockEndCondition(for: line, allowsType7: false) != nil
    }

    private static func htmlBlockEndCondition(
        for line: String,
        allowsType7: Bool
    ) -> HTMLBlockEndCondition? {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return nil
        }

        if startsRawHTMLBlock(indentedLine) {
            return .rawHTML
        }
        if indentedLine.hasPrefix("<!--") {
            return .terminator("-->")
        }
        if indentedLine.hasPrefix("<?") {
            return .terminator("?>")
        }
        if indentedLine.hasPrefix("<![CDATA[") {
            return .terminator("]]>")
        }
        if isHTMLDeclarationStart(indentedLine) {
            return .terminator(">")
        }
        if startsHTMLBlockTagLine(indentedLine) {
            return .blankLine
        }
        if allowsType7, isCompleteStandaloneHTMLTagLine(indentedLine) {
            return .blankLine
        }

        return nil
    }

    private static func startsRawHTMLBlock(_ line: String) -> Bool {
        let lowercasedLine = line.lowercased()
        return ["script", "pre", "style"].contains { tagName in
            htmlLine(lowercasedLine, beginsWithOpeningTagNamed: tagName)
        }
    }

    private static func containsRawHTMLBlockTerminator(_ line: String) -> Bool {
        let lowercasedLine = line.lowercased()
        return lowercasedLine.contains("</script>") ||
            lowercasedLine.contains("</pre>") ||
            lowercasedLine.contains("</style>")
    }

    private static func htmlLine(
        _ lowercasedLine: String,
        beginsWithOpeningTagNamed tagName: String
    ) -> Bool {
        let prefix = "<\(tagName)"
        guard lowercasedLine.hasPrefix(prefix),
              let boundaryIndex = lowercasedLine.index(
                  lowercasedLine.startIndex,
                  offsetBy: prefix.count,
                  limitedBy: lowercasedLine.endIndex
              ) else {
            return false
        }

        return boundaryIndex == lowercasedLine.endIndex ||
            lowercasedLine[boundaryIndex].isWhitespace ||
            lowercasedLine[boundaryIndex] == ">"
    }

    private static func startsHTMLBlockTagLine(_ line: String) -> Bool {
        guard line.first == "<" else {
            return false
        }

        var index = line.index(after: line.startIndex)
        if index < line.endIndex, line[index] == "/" {
            index = line.index(after: index)
        }

        let nameStart = index
        while index < line.endIndex,
              isHTMLTagNameCharacter(line[index]) {
            index = line.index(after: index)
        }

        guard nameStart < index,
              ChatMarkdownHTMLSupport.blockTagNames.contains(
                  String(line[nameStart..<index]).lowercased()
              ) else {
            return false
        }

        guard index < line.endIndex else {
            return true
        }

        let boundary = line[index]
        if boundary == "/" {
            let nextIndex = line.index(after: index)
            return nextIndex < line.endIndex && line[nextIndex] == ">"
        }
        return boundary.isWhitespace || boundary == ">"
    }

    private static func isCompleteStandaloneHTMLTagLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let tag = standaloneRawHTMLTag(in: trimmedLine) else {
            return false
        }

        return tag.isClosing ||
            !["script", "pre", "style"].contains(tag.name)
    }

    private static func standaloneRawHTMLTag(
        in line: String
    ) -> (name: String, isClosing: Bool)? {
        guard line.hasPrefix("<"), line.hasSuffix(">") else {
            return nil
        }

        var index = line.index(after: line.startIndex)
        let isClosing = index < line.endIndex && line[index] == "/"
        if isClosing {
            index = line.index(after: index)
        }

        guard let name = rawHTMLTagName(in: line, index: &index) else {
            return nil
        }

        if isClosing {
            skipHTMLWhitespace(in: line, index: &index)
            guard index < line.endIndex, line[index] == ">" else {
                return nil
            }
            return line.index(after: index) == line.endIndex ? (name, true) : nil
        }

        while index < line.endIndex {
            let hadWhitespace = skipHTMLWhitespace(in: line, index: &index)
            guard index < line.endIndex else {
                return nil
            }

            if line[index] == ">" {
                return line.index(after: index) == line.endIndex ? (name, false) : nil
            }
            if line[index] == "/" {
                let nextIndex = line.index(after: index)
                guard nextIndex < line.endIndex, line[nextIndex] == ">" else {
                    return nil
                }
                return line.index(after: nextIndex) == line.endIndex ? (name, false) : nil
            }
            guard hadWhitespace,
                  consumeRawHTMLAttribute(in: line, index: &index) else {
                return nil
            }
        }

        return nil
    }

    private static func rawHTMLTagName(in line: String, index: inout String.Index) -> String? {
        guard index < line.endIndex,
              isASCIIAlpha(line[index]) else {
            return nil
        }

        let nameStart = index
        index = line.index(after: index)
        while index < line.endIndex,
              isASCIIAlphanumeric(line[index]) || line[index] == "-" {
            index = line.index(after: index)
        }
        return String(line[nameStart..<index]).lowercased()
    }

    private static func consumeRawHTMLAttribute(
        in line: String,
        index: inout String.Index
    ) -> Bool {
        guard index < line.endIndex,
              isRawHTMLAttributeNameStart(line[index]) else {
            return false
        }

        index = line.index(after: index)
        while index < line.endIndex,
              isRawHTMLAttributeNameCharacter(line[index]) {
            index = line.index(after: index)
        }

        skipHTMLWhitespace(in: line, index: &index)
        guard index < line.endIndex, line[index] == "=" else {
            return true
        }

        index = line.index(after: index)
        skipHTMLWhitespace(in: line, index: &index)
        return consumeRawHTMLAttributeValue(in: line, index: &index)
    }

    private static func consumeRawHTMLAttributeValue(
        in line: String,
        index: inout String.Index
    ) -> Bool {
        guard index < line.endIndex else {
            return false
        }

        if line[index] == "\"" || line[index] == "'" {
            let quote = line[index]
            index = line.index(after: index)
            while index < line.endIndex, line[index] != quote {
                index = line.index(after: index)
            }
            guard index < line.endIndex else {
                return false
            }
            index = line.index(after: index)
            return true
        }

        let valueStart = index
        while index < line.endIndex,
              isRawHTMLUnquotedAttributeValueCharacter(line[index]) {
            index = line.index(after: index)
        }
        return valueStart < index
    }

    @discardableResult
    private static func skipHTMLWhitespace(
        in line: String,
        index: inout String.Index
    ) -> Bool {
        let start = index
        while index < line.endIndex, isHTMLWhitespace(line[index]) {
            index = line.index(after: index)
        }
        return index != start
    }

    private static func isRawHTMLAttributeNameStart(_ character: Character) -> Bool {
        isASCIIAlpha(character) || character == "_" || character == ":"
    }

    private static func isRawHTMLAttributeNameCharacter(_ character: Character) -> Bool {
        isASCIIAlphanumeric(character) ||
            character == "_" ||
            character == "." ||
            character == ":" ||
            character == "-"
    }

    private static func isRawHTMLUnquotedAttributeValueCharacter(_ character: Character) -> Bool {
        guard !isHTMLWhitespace(character) else {
            return false
        }
        return character != "\"" &&
            character != "'" &&
            character != "=" &&
            character != "<" &&
            character != ">" &&
            character != "`"
    }

    private static func isHTMLWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x20, 0x0A, 0x09, 0x0D, 0x0C:
                return true
            default:
                return false
            }
        }
    }

    private static func isASCIIAlpha(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }
        return (48...57).contains(scalar.value) ||
            (65...90).contains(scalar.value) ||
            (97...122).contains(scalar.value)
    }

    private static func isFencedCodeOpening(_ line: String) -> Bool {
        openingFenceInfo(in: line) != nil
    }

    private static func isDisplayMathOpening(
        _ line: String,
        allowsIndentedOpening: Bool = true
    ) -> Bool {
        if !allowsIndentedOpening, startsWithWhitespace(line) {
            return false
        }
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return false
        }
        let trimmedLine = indentedLine.trimmingCharacters(in: .whitespaces)
        return trimmedLine == "$$" ||
            trimmedLine == "\\[" ||
            (trimmedLine.hasPrefix("$$") && trimmedLine.count > 2) ||
            (trimmedLine.hasPrefix("\\[") && trimmedLine.count > 2)
    }

    private static func displayMathClosingDelimiter(forOpeningLine line: String) -> String? {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return nil
        }
        let trimmedLine = indentedLine.trimmingCharacters(in: .whitespaces)
        return trimmedLine.hasPrefix("\\[") ? "\\]" : "$$"
    }

    private static func isDisplayMathClosingLine(_ line: String, delimiter: String) -> Bool {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return false
        }
        return indentedLine.trimmingCharacters(in: .whitespaces).hasSuffix(delimiter)
    }

    private static func isListStart(
        _ line: String,
        canInterruptParagraph: Bool = false
    ) -> Bool {
        guard let indentedLine = lineAfterOptionalBlockIndent(line) else {
            return false
        }
        let trimmedLine = indentedLine.trimmingCharacters(in: .whitespaces)
        guard !trimmedLine.isEmpty else {
            return false
        }

        if let first = trimmedLine.first,
           first == "-" || first == "+" || first == "*" {
            let nextIndex = trimmedLine.index(after: trimmedLine.startIndex)
            guard nextIndex == trimmedLine.endIndex || trimmedLine[nextIndex].isWhitespace else {
                return false
            }
            guard canInterruptParagraph else {
                return true
            }
            guard nextIndex < trimmedLine.endIndex else {
                return false
            }
            return !String(trimmedLine[nextIndex...]).trimmingCharacters(in: .whitespaces).isEmpty
        }

        var index = trimmedLine.startIndex
        var digitCount = 0
        while index < trimmedLine.endIndex,
              trimmedLine[index].isNumber,
              digitCount < 9 {
            digitCount += 1
            index = trimmedLine.index(after: index)
        }
        guard digitCount > 0,
              index < trimmedLine.endIndex,
              trimmedLine[index] == "." || trimmedLine[index] == ")" else {
            return false
        }
        let markerEnd = trimmedLine.index(after: index)
        guard markerEnd == trimmedLine.endIndex || trimmedLine[markerEnd].isWhitespace else {
            return false
        }
        guard canInterruptParagraph else {
            return true
        }
        guard markerEnd < trimmedLine.endIndex else {
            return false
        }
        return String(trimmedLine[..<index]) == "1" &&
            !String(trimmedLine[markerEnd...]).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isLazyBlockQuoteContinuation(
        _ line: String,
        state: LazyBlockQuoteState
    ) -> Bool {
        switch state {
        case .paragraph:
            return !isInterruptingLazyBlockQuoteContinuation(line)
        case .unavailable:
            return false
        }
    }

    private static func isInterruptingLazyBlockQuoteContinuation(_ line: String) -> Bool {
        isFencedCodeOpening(line) ||
            isDisplayMathOpening(line, allowsIndentedOpening: false) ||
            isBlockQuoteLine(line) ||
            startsHTMLBlock(line) ||
            isListStart(line) ||
            isSingleLineBlock(line) ||
            isSetextHeadingUnderline(line)
    }

    private static func lineAllowsLazyBlockQuoteContinuationAfterMarker(_ line: String) -> Bool {
        guard !isBlank(line) else {
            return false
        }

        if isFencedCodeOpening(line) ||
            isDisplayMathOpening(line, allowsIndentedOpening: false) ||
            isBlockQuoteLine(line) ||
            htmlBlockEndCondition(for: line, allowsType7: true) != nil ||
            isSingleLineBlock(line) ||
            isSetextHeadingUnderline(line) ||
            isIndentedCodeLine(line) {
            return false
        }

        return true
    }

    private static func nextLazyBlockQuoteState(
        afterQuotedLine line: String,
        current: LazyBlockQuoteState,
        openFence: inout (marker: Character, count: Int)?
    ) -> LazyBlockQuoteState {
        guard let contentLine = blockQuoteContentLine(line) else {
            return current
        }

        if let fence = openFence {
            if let closingFence = closingFenceInfo(in: contentLine),
               closingFence.marker == fence.marker,
               closingFence.count >= fence.count {
                openFence = nil
            }
            return .unavailable
        }

        if let openingFence = openingFenceInfoAllowingListMarker(in: contentLine) {
            openFence = openingFence
            return .unavailable
        }

        return lineAllowsLazyBlockQuoteContinuationAfterMarker(contentLine)
            ? .paragraph
            : .unavailable
    }

    private static func nextLazyBlockQuoteState(
        afterLazyLine line: String,
        current: LazyBlockQuoteState
    ) -> LazyBlockQuoteState {
        switch current {
        case .paragraph:
            return .paragraph
        case .unavailable:
            return lineAllowsLazyBlockQuoteContinuationAfterMarker(line) ? .paragraph : .unavailable
        }
    }

    private static func isTableBreakingBlockStart(_ line: String) -> Bool {
        isFencedCodeOpening(line) ||
            isDisplayMathOpening(line, allowsIndentedOpening: false) ||
            isBlockQuoteLine(line) ||
            htmlBlockEndCondition(for: line, allowsType7: true) != nil ||
            isIndentedCodeLine(line) ||
            isListStart(line) ||
            isATXHeading(line) ||
            isThematicBreak(line)
    }

    private static func openingFenceInfo(in line: String) -> (marker: Character, count: Int)? {
        ChatMarkdownBlockSyntax.openingFenceInfo(in: line)
    }

    private static func openingFenceInfoAllowingListMarker(in line: String) -> (marker: Character, count: Int)? {
        if let openingFence = openingFenceInfo(in: line) {
            return openingFence
        }

        guard let listContentLine = ChatMarkdownBlockSyntax.lineAfterListMarker(line) else {
            return nil
        }
        return openingFenceInfo(in: listContentLine)
    }

    private static func closingFenceInfo(in line: String) -> (marker: Character, count: Int)? {
        ChatMarkdownBlockSyntax.closingFenceInfo(in: line)
    }

    private static func lineAfterOptionalBlockIndent(_ line: String) -> String? {
        ChatMarkdownBlockSyntax.lineAfterOptionalBlockIndent(line)
    }

    private static func isIndentedCodeLine(_ line: String) -> Bool {
        lineAfterOptionalBlockIndent(line) == nil
    }

    private static func startsWithWhitespace(_ line: String) -> Bool {
        guard let first = line.first else {
            return false
        }
        return first == " " || first == "\t"
    }

    private static func isHTMLDeclarationStart(_ line: String) -> Bool {
        guard line.hasPrefix("<!"),
              let markerIndex = line.index(line.startIndex, offsetBy: 2, limitedBy: line.endIndex),
              markerIndex < line.endIndex else {
            return false
        }
        guard let scalar = line[markerIndex].unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value)
    }

    private static func isHTMLTagNameCharacter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }

        return (48...57).contains(scalar.value) ||
            (65...90).contains(scalar.value) ||
            (97...122).contains(scalar.value)
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
