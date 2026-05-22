//
//  ChatMarkdownHTMLSupport.swift
//  UniLLMs
//
//  Lightweight GFM raw HTML tokenization helpers for native Markdown rendering.
//  Created by Codex on 2026/5/14.
//

import Foundation

struct ChatMarkdownHTMLTag {
    let rawHTML: String
    let name: String
    let isClosing: Bool
    let isSelfClosing: Bool
    let attributes: [String: String]

    func attribute(_ name: String) -> String? {
        attributes[name.lowercased()]
    }
}

struct ChatMarkdownDetailsOpening {
    let summary: String
    let isOpen: Bool
    let bodyMarkdown: String
    let remainingDepth: Int
}

struct ChatMarkdownHTMLDetailsTagBalance {
    let openingCount: Int
    let closingCount: Int
}

struct ChatMarkdownHTMLDetailsClosingScan {
    let markdown: String
    let remainingDepth: Int
    let didClose: Bool
}

enum ChatMarkdownHTMLToken {
    case text(String)
    case tag(ChatMarkdownHTMLTag)
    case comment(String)
    case cdata(String)
    case declaration(String)
    case processingInstruction(String)
}

enum ChatMarkdownHTMLSupport {
    static let disallowedRawHTMLTagNames: Set<String> = [
        "title",
        "textarea",
        "style",
        "xmp",
        "iframe",
        "noembed",
        "noframes",
        "script",
        "plaintext"
    ]

    static let voidTagNames: Set<String> = [
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "param",
        "source",
        "track",
        "wbr"
    ]

    static let blockTagNames: Set<String> = [
        "address",
        "article",
        "aside",
        "base",
        "basefont",
        "blockquote",
        "body",
        "caption",
        "center",
        "col",
        "colgroup",
        "dd",
        "details",
        "dialog",
        "dir",
        "div",
        "dl",
        "dt",
        "fieldset",
        "figcaption",
        "figure",
        "footer",
        "form",
        "frame",
        "frameset",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "head",
        "header",
        "hr",
        "html",
        "iframe",
        "legend",
        "li",
        "link",
        "main",
        "menu",
        "menuitem",
        "meta",
        "nav",
        "noframes",
        "ol",
        "optgroup",
        "option",
        "p",
        "param",
        "pre",
        "search",
        "section",
        "source",
        "summary",
        "table",
        "tbody",
        "td",
        "tfoot",
        "th",
        "thead",
        "title",
        "tr",
        "track",
        "ul"
    ]

    private static let transparentStandaloneImageTagNames: Set<String> = [
        "a",
        "div",
        "figure",
        "p",
        "picture",
        "source",
        "span"
    ]

    static func tokens(in html: String) -> [ChatMarkdownHTMLToken] {
        var tokens: [ChatMarkdownHTMLToken] = []
        var index = html.startIndex

        while index < html.endIndex {
            guard html[index] == "<" else {
                let nextTag = html[index...].firstIndex(of: "<") ?? html.endIndex
                tokens.append(.text(String(html[index..<nextTag])))
                index = nextTag
                continue
            }

            if html[index...].hasPrefix("<!--") {
                let end = html[index...].range(of: "-->")?.upperBound ?? html.endIndex
                tokens.append(.comment(String(html[index..<end])))
                index = end
                continue
            }

            if html[index...].hasPrefix("<![CDATA[") {
                let contentStart = html.index(index, offsetBy: 9)
                if let range = html[contentStart...].range(of: "]]>") {
                    tokens.append(.cdata(String(html[contentStart..<range.lowerBound])))
                    index = range.upperBound
                } else {
                    tokens.append(.cdata(String(html[contentStart...])))
                    index = html.endIndex
                }
                continue
            }

            if html[index...].hasPrefix("<?") {
                let end = html[index...].range(of: "?>")?.upperBound ?? html.endIndex
                tokens.append(.processingInstruction(String(html[index..<end])))
                index = end
                continue
            }

            if html[index...].hasPrefix("<!") {
                guard let tagEnd = findTagEnd(in: html, from: index) else {
                    tokens.append(.text(String(html[index])))
                    index = html.index(after: index)
                    continue
                }
                let raw = String(html[index...tagEnd])
                tokens.append(.declaration(raw))
                index = html.index(after: tagEnd)
                continue
            }

            guard let tagEnd = findTagEnd(in: html, from: index) else {
                tokens.append(.text(String(html[index])))
                index = html.index(after: index)
                continue
            }

            let raw = String(html[index...tagEnd])
            if let tag = parseTag(raw) {
                tokens.append(.tag(tag))
            } else {
                tokens.append(.text(raw))
            }
            index = html.index(after: tagEnd)
        }

        return tokens
    }

    static func parseTag(_ rawHTML: String) -> ChatMarkdownHTMLTag? {
        guard rawHTML.hasPrefix("<"), rawHTML.hasSuffix(">") else {
            return nil
        }

        var content = rawHTML.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return nil
        }

        let isClosing = content.first == "/"
        if isClosing {
            content = content.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var isSelfClosing = false
        if content.last == "/" {
            isSelfClosing = true
            content = content.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let first = content.first,
              first.isASCIIAlpha else {
            return nil
        }

        let nameEnd = content.firstIndex { character in
            character.isHTMLWhitespace || character == "/" || character == ">"
        } ?? content.endIndex
        let name = String(content[..<nameEnd]).lowercased()
        guard !name.isEmpty else {
            return nil
        }

        let attributesSource = String(content[nameEnd...])
        return ChatMarkdownHTMLTag(
            rawHTML: rawHTML,
            name: name,
            isClosing: isClosing,
            isSelfClosing: isSelfClosing || voidTagNames.contains(name),
            attributes: isClosing ? [:] : parseAttributes(attributesSource)
        )
    }

    static func imageBlock(fromHTML html: String) -> ChatMarkdownImageBlock? {
        var image: ChatMarkdownImageBlock?
        var hasVisibleText = false
        var filteredRawHTMLTagStack: [String] = []

        for token in tokens(in: html) {
            if !filteredRawHTMLTagStack.isEmpty {
                if case let .tag(tag) = token,
                   tag.isClosing,
                   tag.name == filteredRawHTMLTagStack.last {
                    filteredRawHTMLTagStack.removeLast()
                }
                hasVisibleText = true
                continue
            }

            switch token {
            case let .text(text), let .cdata(text):
                if !decodeEntities(in: text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hasVisibleText = true
                }
            case .comment, .declaration, .processingInstruction:
                continue
            case let .tag(tag):
                guard !tag.isClosing else {
                    continue
                }

                if disallowedRawHTMLTagNames.contains(tag.name) {
                    hasVisibleText = true
                    if !tag.isSelfClosing {
                        filteredRawHTMLTagStack.append(tag.name)
                    }
                    continue
                }

                switch tag.name {
                case let name where transparentStandaloneImageTagNames.contains(name):
                    continue
                case "br", "wbr":
                    continue
                case "img":
                    if image == nil, let imageBlock = imageBlock(from: tag) {
                        image = imageBlock
                    }
                default:
                    hasVisibleText = true
                }
            }
        }

        guard !hasVisibleText else {
            return nil
        }
        return image
    }

    static func imageBlock(from tag: ChatMarkdownHTMLTag) -> ChatMarkdownImageBlock? {
        guard tag.name == "img",
              let source = tag.attribute("src")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return nil
        }

        let altText = tag.attribute("alt")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ChatMarkdownImageBlock(source: source, altText: altText)
    }

    static func detailsOpening(fromHTML html: String) -> ChatMarkdownDetailsOpening? {
        var foundDetails = false
        var isOpen = false
        var isCollectingSummary = false
        var didFinishSummary = false
        var detailsDepth = 0
        var didCloseDetails = false
        var summary = ""
        var bodyMarkdown = ""
        var filteredRawHTMLTagStack: [String] = []

        detailsTokenLoop: for token in tokens(in: html) {
            if !filteredRawHTMLTagStack.isEmpty {
                if isCollectingSummary {
                    summary += markdownSourceText(for: token)
                } else if foundDetails, didFinishSummary {
                    bodyMarkdown += markdownSourceText(for: token)
                }
                if case let .tag(tag) = token,
                   tag.isClosing,
                   tag.name == filteredRawHTMLTagStack.last {
                    filteredRawHTMLTagStack.removeLast()
                }
                continue
            }

            switch token {
            case let .text(text), let .cdata(text):
                if isCollectingSummary {
                    summary += decodeEntities(in: text)
                } else if foundDetails, didFinishSummary {
                    bodyMarkdown += text
                } else if foundDetails {
                    if !decodeEntities(in: text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        didFinishSummary = true
                        bodyMarkdown += text
                    }
                }
            case .comment, .declaration, .processingInstruction:
                if foundDetails, didFinishSummary {
                    bodyMarkdown += markdownSourceText(for: token)
                }
            case let .tag(tag):
                if disallowedRawHTMLTagNames.contains(tag.name) {
                    if isCollectingSummary {
                        summary += tag.rawHTML
                    } else if foundDetails, didFinishSummary {
                        bodyMarkdown += tag.rawHTML
                    }
                    if !tag.isClosing, !tag.isSelfClosing {
                        filteredRawHTMLTagStack.append(tag.name)
                    }
                    continue
                }

                if tag.name == "details" {
                    if tag.isClosing {
                        if detailsDepth > 1 {
                            detailsDepth -= 1
                            if didFinishSummary {
                                bodyMarkdown += tag.rawHTML
                            }
                            continue
                        }
                        didCloseDetails = true
                        break detailsTokenLoop
                    }
                    if !foundDetails {
                        guard !tag.isSelfClosing else {
                            return nil
                        }
                        foundDetails = true
                        isOpen = tag.attributes.keys.contains("open")
                        detailsDepth = 1
                    } else if didFinishSummary {
                        detailsDepth += 1
                        bodyMarkdown += tag.rawHTML
                    }
                    continue
                }

                guard foundDetails else {
                    continue
                }

                if tag.name == "summary" {
                    if tag.isClosing || tag.isSelfClosing {
                        isCollectingSummary = false
                        didFinishSummary = true
                    } else {
                        isCollectingSummary = true
                    }
                    continue
                }

                if foundDetails, didFinishSummary {
                    bodyMarkdown += tag.rawHTML
                    continue
                }

                guard isCollectingSummary else {
                    didFinishSummary = true
                    bodyMarkdown += tag.rawHTML
                    continue
                }
                if tag.name == "br" {
                    summary += "\n"
                } else if tag.name == "img",
                          let imageBlock = imageBlock(from: tag) {
                    summary += imageBlock.altText.isEmpty ? imageBlock.source : imageBlock.altText
                }
            }
        }

        guard foundDetails else {
            return nil
        }

        let normalizedSummary = collapsedWhitespace(summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatMarkdownDetailsOpening(
            summary: normalizedSummary.isEmpty ? "Details" : normalizedSummary,
            isOpen: isOpen,
            bodyMarkdown: bodyMarkdown,
            remainingDepth: didCloseDetails ? 0 : detailsDepth
        )
    }

    static func markdownBeforeMatchingDetailsClosing(
        inHTML html: String,
        initialDepth: Int
    ) -> ChatMarkdownHTMLDetailsClosingScan {
        var markdown = ""
        var depth = max(0, initialDepth)
        var filteredRawHTMLTagStack: [String] = []

        for token in tokens(in: html) {
            if !filteredRawHTMLTagStack.isEmpty {
                markdown += markdownSourceText(for: token)
                if case let .tag(tag) = token,
                   tag.isClosing,
                   tag.name == filteredRawHTMLTagStack.last {
                    filteredRawHTMLTagStack.removeLast()
                }
                continue
            }

            switch token {
            case let .tag(tag):
                if tag.name == "details" {
                    if tag.isClosing {
                        if depth <= 1 {
                            return ChatMarkdownHTMLDetailsClosingScan(
                                markdown: markdown,
                                remainingDepth: 0,
                                didClose: true
                            )
                        }
                        depth -= 1
                        markdown += tag.rawHTML
                        continue
                    }

                    if !tag.isSelfClosing {
                        depth += 1
                    }
                }
                markdown += tag.rawHTML
                if disallowedRawHTMLTagNames.contains(tag.name),
                   !tag.isClosing,
                   !tag.isSelfClosing {
                    filteredRawHTMLTagStack.append(tag.name)
                }
            default:
                markdown += markdownSourceText(for: token)
            }
        }

        return ChatMarkdownHTMLDetailsClosingScan(
            markdown: markdown,
            remainingDepth: depth,
            didClose: false
        )
    }

    static func detailsTagBalance(inHTML html: String) -> ChatMarkdownHTMLDetailsTagBalance {
        var openingCount = 0
        var closingCount = 0
        var filteredRawHTMLTagStack: [String] = []

        for token in tokens(in: html) {
            if !filteredRawHTMLTagStack.isEmpty {
                if case let .tag(tag) = token,
                   tag.isClosing,
                   tag.name == filteredRawHTMLTagStack.last {
                    filteredRawHTMLTagStack.removeLast()
                }
                continue
            }

            guard case let .tag(tag) = token,
                  tag.name == "details" || disallowedRawHTMLTagNames.contains(tag.name) else {
                continue
            }

            if disallowedRawHTMLTagNames.contains(tag.name) {
                if !tag.isClosing, !tag.isSelfClosing {
                    filteredRawHTMLTagStack.append(tag.name)
                }
                continue
            }

            if tag.isClosing {
                closingCount += 1
            } else if !tag.isSelfClosing {
                openingCount += 1
            }
        }

        return ChatMarkdownHTMLDetailsTagBalance(
            openingCount: openingCount,
            closingCount: closingCount
        )
    }

    static func startsWithOpeningDetailsTag(_ html: String) -> Bool {
        for token in tokens(in: html) {
            switch token {
            case let .text(text), let .cdata(text):
                if !decodeEntities(in: text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return false
                }
            case .comment, .declaration, .processingInstruction:
                continue
            case let .tag(tag):
                return tag.name == "details" && !tag.isClosing && !tag.isSelfClosing
            }
        }

        return false
    }

    static func decodeEntities(in text: String) -> String {
        guard text.contains("&") else {
            return text
        }

        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "&",
                  let semicolon = text[index...].firstIndex(of: ";") else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let entityStart = text.index(after: index)
            let entity = String(text[entityStart..<semicolon])
            if let decoded = decodedEntity(entity) {
                result.append(decoded)
                index = text.index(after: semicolon)
            } else {
                result.append(contentsOf: text[index...semicolon])
                index = text.index(after: semicolon)
            }
        }

        return result
    }

    static func collapsedWhitespace(_ text: String) -> String {
        var result = ""
        var previousWasWhitespace = false

        for character in text {
            if character.isHTMLWhitespace {
                if !previousWasWhitespace {
                    result.append(" ")
                }
                previousWasWhitespace = true
            } else {
                result.append(character)
                previousWasWhitespace = false
            }
        }

        return result
    }

    private static func findTagEnd(in html: String, from start: String.Index) -> String.Index? {
        var index = html.index(after: start)
        var quote: Character?

        while index < html.endIndex {
            let character = html[index]
            if let currentQuote = quote {
                if character == currentQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }

            index = html.index(after: index)
        }

        return nil
    }

    private static func markdownSourceText(for token: ChatMarkdownHTMLToken) -> String {
        switch token {
        case let .text(text), let .cdata(text):
            return text
        case let .tag(tag):
            return tag.rawHTML
        case let .comment(raw), let .declaration(raw), let .processingInstruction(raw):
            return raw
        }
    }

    private static func parseAttributes(_ source: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = source.startIndex

        while index < source.endIndex {
            skipHTMLWhitespace(in: source, index: &index)
            guard index < source.endIndex, source[index] != "/" else {
                break
            }

            let nameStart = index
            while index < source.endIndex,
                  !source[index].isHTMLWhitespace,
                  source[index] != "=",
                  source[index] != "/" {
                index = source.index(after: index)
            }

            guard nameStart < index else {
                index = source.index(after: index)
                continue
            }

            let name = String(source[nameStart..<index]).lowercased()
            skipHTMLWhitespace(in: source, index: &index)

            var value = ""
            if index < source.endIndex, source[index] == "=" {
                index = source.index(after: index)
                skipHTMLWhitespace(in: source, index: &index)
                value = parseAttributeValue(source, index: &index)
            }

            attributes[name] = decodeEntities(in: value)
        }

        return attributes
    }

    private static func parseAttributeValue(_ source: String, index: inout String.Index) -> String {
        guard index < source.endIndex else {
            return ""
        }

        if source[index] == "\"" || source[index] == "'" {
            let quote = source[index]
            index = source.index(after: index)
            let valueStart = index
            while index < source.endIndex, source[index] != quote {
                index = source.index(after: index)
            }
            let value = String(source[valueStart..<index])
            if index < source.endIndex {
                index = source.index(after: index)
            }
            return value
        }

        let valueStart = index
        while index < source.endIndex,
              !source[index].isHTMLWhitespace,
              source[index] != "/" {
            index = source.index(after: index)
        }
        return String(source[valueStart..<index])
    }

    private static func skipHTMLWhitespace(in source: String, index: inout String.Index) {
        while index < source.endIndex, source[index].isHTMLWhitespace {
            index = source.index(after: index)
        }
    }

    private static func decodedEntity(_ entity: String) -> String? {
        switch entity {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos":
            return "'"
        case "nbsp":
            return "\u{00A0}"
        default:
            return decodedNumericEntity(entity) ?? commonNamedHTMLEntities[entity]
        }
    }

    private static func decodedNumericEntity(_ entity: String) -> String? {
        let scalarValue: UInt32?
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            scalarValue = UInt32(entity.dropFirst(2), radix: 16)
        } else if entity.hasPrefix("#") {
            scalarValue = UInt32(entity.dropFirst(), radix: 10)
        } else {
            scalarValue = nil
        }

        guard let scalarValue,
              let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }

        return String(Character(scalar))
    }

    // Keep this deliberately small: numeric references plus these common names cover
    // chat output without pulling an HTML importer into the streaming render path.
    private static let commonNamedHTMLEntities: [String: String] = [
        "bull": "\u{2022}",
        "copy": "\u{00A9}",
        "euro": "\u{20AC}",
        "hellip": "\u{2026}",
        "laquo": "\u{00AB}",
        "ldquo": "\u{201C}",
        "lsaquo": "\u{2039}",
        "lsquo": "\u{2018}",
        "mdash": "\u{2014}",
        "ndash": "\u{2013}",
        "raquo": "\u{00BB}",
        "rdquo": "\u{201D}",
        "reg": "\u{00AE}",
        "rsaquo": "\u{203A}",
        "rsquo": "\u{2019}",
        "trade": "\u{2122}",
        "yen": "\u{00A5}"
    ]
}

private extension Character {
    var isASCIIAlpha: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }

        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    var isHTMLWhitespace: Bool {
        unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x20, 0x0A, 0x09, 0x0D, 0x0C:
                return true
            default:
                return false
            }
        }
    }
}
