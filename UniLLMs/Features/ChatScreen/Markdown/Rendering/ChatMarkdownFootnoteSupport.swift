//
//  ChatMarkdownFootnoteSupport.swift
//  UniLLMs
//
//  Footnote preprocessing and presentation helpers for chat Markdown.
//

import Foundation

struct ChatMarkdownFootnoteDefinition: Equatable {
    let label: String
    let content: String
}

struct ChatMarkdownFootnotePresentation: Equatable {
    let label: String
    let displayText: String
    let content: String

    var accessibilityText: String {
        String(
            format: String(localized: "markdown.footnote.reference_accessibility_format"),
            displayText
        )
    }
}

struct ChatMarkdownFootnoteDocument {
    let markdown: String
    let footnotes: [String: ChatMarkdownFootnoteDefinition]
}

enum ChatMarkdownFootnoteLabel {
    static func normalized(_ label: String) -> String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

enum ChatMarkdownFootnoteLink {
    static let scheme = "unillms-footnote"

    static func url(label: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "reference"
        components.queryItems = [
            URLQueryItem(name: "label", value: label)
        ]
        return components.url ?? URL(string: "\(scheme)://reference")!
    }

    static func isFootnoteURL(_ url: URL) -> Bool {
        url.scheme == scheme
    }
}

enum ChatMarkdownFootnotePreprocessor {
    private struct Fence {
        let marker: Character
        let count: Int
    }

    private struct OpeningDefinition {
        let label: String
        let content: String
    }

    static func process(_ markdown: String) -> ChatMarkdownFootnoteDocument {
        guard !markdown.isEmpty else {
            return ChatMarkdownFootnoteDocument(markdown: markdown, footnotes: [:])
        }

        let lines = markdown.components(separatedBy: "\n")
        var outputLines: [String] = []
        var footnotes: [String: ChatMarkdownFootnoteDefinition] = [:]
        var fence: Fence?
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if let activeFence = fence {
                outputLines.append(line)
                if isClosingFence(line, for: activeFence) {
                    fence = nil
                }
                index += 1
                continue
            }

            if let openingFence = openingFence(in: line) {
                outputLines.append(line)
                fence = openingFence
                index += 1
                continue
            }

            if let definition = openingDefinition(in: line) {
                let parsedDefinition = parseDefinition(
                    opening: definition,
                    lines: lines,
                    nextIndex: index + 1
                )
                let normalizedLabel = ChatMarkdownFootnoteLabel.normalized(definition.label)
                if !normalizedLabel.isEmpty, footnotes[normalizedLabel] == nil {
                    footnotes[normalizedLabel] = ChatMarkdownFootnoteDefinition(
                        label: definition.label.trimmingCharacters(in: .whitespacesAndNewlines),
                        content: parsedDefinition.content
                    )
                }
                index = parsedDefinition.nextIndex
                continue
            }

            outputLines.append(line)
            index += 1
        }

        return ChatMarkdownFootnoteDocument(
            markdown: outputLines.joined(separator: "\n"),
            footnotes: footnotes
        )
    }

    private static func parseDefinition(
        opening: OpeningDefinition,
        lines: [String],
        nextIndex: Int
    ) -> (content: String, nextIndex: Int) {
        var contentLines = [opening.content]
        var index = nextIndex

        while index < lines.count {
            let line = lines[index]
            if isContinuationLine(line) {
                contentLines.append(removingContinuationIndent(from: line))
                index += 1
                continue
            }

            if isBlank(line),
               index + 1 < lines.count,
               isContinuationLine(lines[index + 1]) {
                contentLines.append("")
                index += 1
                continue
            }

            break
        }

        return (
            content: contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            nextIndex: index
        )
    }

    private static func openingDefinition(in line: String) -> OpeningDefinition? {
        let scalars = Array(line.unicodeScalars)
        var index = 0
        var leadingSpaces = 0

        while index < scalars.count, scalars[index] == " ", leadingSpaces < 4 {
            leadingSpaces += 1
            index += 1
        }
        guard leadingSpaces <= 3,
              index + 3 < scalars.count,
              scalars[index] == "[",
              scalars[index + 1] == "^" else {
            return nil
        }

        let labelStart = index + 2
        var labelEnd = labelStart
        while labelEnd < scalars.count, scalars[labelEnd] != "]" {
            labelEnd += 1
        }
        guard labelEnd < scalars.count,
              labelEnd > labelStart,
              labelEnd + 1 < scalars.count,
              scalars[labelEnd + 1] == ":" else {
            return nil
        }

        let label = String(String.UnicodeScalarView(scalars[labelStart..<labelEnd]))
        let contentStart = min(labelEnd + 2, scalars.count)
        let contentScalars = scalars[contentStart..<scalars.count]
        let content = String(String.UnicodeScalarView(contentScalars))
            .trimmingCharacters(in: .whitespaces)
        return OpeningDefinition(label: label, content: content)
    }

    private static func isContinuationLine(_ line: String) -> Bool {
        continuationIndentLength(in: line) != nil
    }

    private static func removingContinuationIndent(from line: String) -> String {
        guard let indentLength = continuationIndentLength(in: line) else {
            return line
        }

        let index = line.index(line.startIndex, offsetBy: indentLength)
        return String(line[index...])
    }

    private static func continuationIndentLength(in line: String) -> Int? {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
                if count == 4 {
                    return count
                }
                continue
            }
            if character == "\t" {
                return count + 1
            }
            return nil
        }
        return nil
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func openingFence(in line: String) -> Fence? {
        let trimmed = line.dropFirst(min(leadingSpaceCount(in: line), 3))
        guard let marker = trimmed.first,
              marker == "`" || marker == "~" else {
            return nil
        }

        let count = trimmed.prefix { $0 == marker }.count
        guard count >= 3 else {
            return nil
        }
        return Fence(marker: marker, count: count)
    }

    private static func isClosingFence(_ line: String, for fence: Fence) -> Bool {
        let trimmed = line.dropFirst(min(leadingSpaceCount(in: line), 3))
        guard trimmed.first == fence.marker else {
            return false
        }
        return trimmed.prefix { $0 == fence.marker }.count >= fence.count
    }

    private static func leadingSpaceCount(in line: String) -> Int {
        var count = 0
        for character in line {
            guard character == " " else {
                return count
            }
            count += 1
        }
        return count
    }
}
