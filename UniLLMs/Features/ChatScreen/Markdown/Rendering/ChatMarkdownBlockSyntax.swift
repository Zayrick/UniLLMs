//
//  ChatMarkdownBlockSyntax.swift
//  UniLLMs
//
//  Shared CommonMark block syntax helpers used before swift-markdown parsing.
//  Created by Codex on 2026/5/22.
//

import Foundation

enum ChatMarkdownBlockSyntax {
    static func lineAfterOptionalBlockIndent(_ line: String) -> String? {
        var column = 0
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == " " {
                column += 1
            } else if character == "\t" {
                column += 4 - (column % 4)
            } else {
                break
            }

            guard column < 4 else {
                return nil
            }
            index = line.index(after: index)
        }

        return String(line[index...])
    }

    static func openingFenceInfo(in line: String) -> (marker: Character, count: Int)? {
        fenceInfo(in: line, allowsInfoString: true)
    }

    static func closingFenceInfo(in line: String) -> (marker: Character, count: Int)? {
        fenceInfo(in: line, allowsInfoString: false)
    }

    private static func fenceInfo(
        in line: String,
        allowsInfoString: Bool
    ) -> (marker: Character, count: Int)? {
        guard let indentedLine = lineAfterOptionalBlockIndent(line),
              let marker = indentedLine.first,
              marker == "`" || marker == "~" else {
            return nil
        }

        let count = indentedLine.prefix { $0 == marker }.count
        guard count >= 3 else {
            return nil
        }

        let rest = indentedLine.dropFirst(count)
        if allowsInfoString {
            if marker == "`", rest.contains("`") {
                return nil
            }
        } else if !rest.allSatisfy(\.isWhitespace) {
            return nil
        }

        return (marker, count)
    }
}
