// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).


import AppKit
import Foundation
import SwiftUI

/// A small highlighter for the code blocks in a reply: keywords, strings,
/// comments, numbers and type names for the languages agents write most,
/// and the added and removed lines of a diff. It reads tokens with regular
/// expressions, not a grammar, so it can be wrong at the edges; it is only
/// ever colour.
public enum NexusAgentSyntaxHighlighter {
    public struct Token: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            case keyword, string, comment, number, type, key, variable, added, removed, meta
        }
        public let kind: Kind
        public let text: String
        /// Where the token is, in UTF-16 units of the code.
        public let range: NSRange
    }

    /// The families of language the highlighter knows.
    enum Family {
        case cLike(keywords: Set<String>, hashComments: Bool)
        case python, shell, json, yaml, diff
    }

    static func family(for language: String?) -> Family? {
        switch language?.lowercased().trimmingCharacters(in: .whitespaces) ?? "" {
        case "swift": return .cLike(keywords: swiftKeywords, hashComments: false)
        case "js", "javascript", "jsx", "ts", "typescript", "tsx", "mjs", "cjs":
            return .cLike(keywords: jsKeywords, hashComments: false)
        case "go", "golang": return .cLike(keywords: goKeywords, hashComments: false)
        case "kotlin", "kt", "kts": return .cLike(keywords: kotlinKeywords, hashComments: false)
        case "rust", "rs": return .cLike(keywords: rustKeywords, hashComments: false)
        case "java", "c", "cpp", "c++", "objc", "objective-c", "cs", "csharp", "h", "hpp", "m":
            return .cLike(keywords: cKeywords, hashComments: false)
        case "python", "py", "python3": return .python
        case "sh", "bash", "zsh", "shell", "console", "shellsession", "fish": return .shell
        case "json", "jsonc", "json5": return .json
        case "yaml", "yml", "toml": return .yaml
        case "diff", "patch", "udiff": return .diff
        default: return nil
        }
    }

    /// The languages whose blocks are commands a person might run.
    public static func isShell(_ language: String?) -> Bool {
        switch language?.lowercased().trimmingCharacters(in: .whitespaces) ?? "" {
        case "sh", "bash", "zsh", "shell", "console", "shellsession": return true
        default: return false
        }
    }

    /// The tokens worth colouring, in order, none overlapping.
    public static func tokens(code: String, language: String?) -> [Token] {
        guard let family = family(for: language) else { return [] }
        let ns = code as NSString
        if case .diff = family { return diffTokens(ns) }
        let (pattern, keywords) = rule(for: family)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        var tokens: [Token] = []
        for match in regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            func group(_ name: String) -> NSRange? {
                let range = match.range(withName: name)
                return range.location == NSNotFound ? nil : range
            }
            if let range = group("comment") {
                tokens.append(Token(kind: .comment, text: ns.substring(with: range), range: range))
            } else if let range = group("key") {
                tokens.append(Token(kind: .key, text: ns.substring(with: range), range: range))
            } else if let range = group("string") {
                tokens.append(Token(kind: .string, text: ns.substring(with: range), range: range))
            } else if let range = group("variable") {
                tokens.append(Token(kind: .variable, text: ns.substring(with: range), range: range))
            } else if let range = group("number") {
                tokens.append(Token(kind: .number, text: ns.substring(with: range), range: range))
            } else if let range = group("ident") {
                let word = ns.substring(with: range)
                if keywords.contains(word) {
                    tokens.append(Token(kind: .keyword, text: word, range: range))
                } else if case .cLike = family, let first = word.unicodeScalars.first,
                    CharacterSet.uppercaseLetters.contains(first), word.count > 1
                {
                    tokens.append(Token(kind: .type, text: word, range: range))
                }
            }
        }
        return tokens
    }

    /// The code, coloured.
    public static func highlight(code: String, language: String?) -> AttributedString {
        let ns = code as NSString
        var result = AttributedString()
        var cursor = 0
        for token in tokens(code: code, language: language) {
            if token.range.location > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
            }
            var piece = AttributedString(token.text)
            piece.foregroundColor = color(for: token.kind)
            if token.kind == .comment { piece.inlinePresentationIntent = .emphasized }
            result += piece
            cursor = token.range.location + token.range.length
        }
        if cursor < ns.length {
            result += AttributedString(ns.substring(from: cursor))
        }
        return result
    }

    // MARK: - Rules

    private static let tripleQuoted = "\"\"\"[\\s\\S]*?\"\"\""
    private static let tripleSingleQuoted = "'''[\\s\\S]*?'''"
    private static let doubleQuoted = #""(?:[^"\\\n]|\\.)*""#
    private static let singleQuoted = #"'(?:[^'\\\n]|\\.)*'"#
    private static let number = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#
    private static let identifier = #"[A-Za-z_$][A-Za-z0-9_$]*"#

    private static func rule(for family: Family) -> (String, Set<String>) {
        switch family {
        case .cLike(let keywords, _):
            let strings = [tripleQuoted, doubleQuoted, singleQuoted, #"`(?:[^`\\]|\\.)*`"#].joined(separator: "|")
            return ("(?<comment>//[^\\n]*|/\\*[\\s\\S]*?\\*/)|(?<string>\(strings))|(?<number>\(number))|(?<ident>\(identifier))", keywords)
        case .python:
            let strings = ["[rRbBfFuU]{0,2}" + tripleQuoted, "[rRbBfFuU]{0,2}" + tripleSingleQuoted,
                           "[rRbBfFuU]{0,2}" + doubleQuoted, "[rRbBfFuU]{0,2}" + singleQuoted].joined(separator: "|")
            return ("(?<comment>#[^\\n]*)|(?<string>\(strings))|(?<number>\(number))|(?<ident>\(identifier))", pythonKeywords)
        case .shell:
            // A `#` starts a comment only at the start of a word.
            return ("(?<comment>(?<![^\\s;|&(])#[^\\n]*)|(?<string>\(doubleQuoted)|\(singleQuoted))|(?<variable>\\$\\{[^}\\n]*\\}|\\$[A-Za-z_][A-Za-z0-9_]*|\\$[0-9@#?*$!-])|(?<number>(?<![\\w.-])\\d+(?![\\w.-]))|(?<ident>(?<![\\w./-])[A-Za-z_][A-Za-z0-9_-]*)", shellKeywords)
        case .json:
            return ("(?<comment>//[^\\n]*)|(?<key>\(doubleQuoted)(?=\\s*:))|(?<string>\(doubleQuoted))|(?<number>-?\(number))|(?<ident>\(identifier))", ["true", "false", "null"])
        case .yaml:
            return ("(?<comment>(?<![^\\s])#[^\\n]*)|(?<key>^[ \\t]*(?:- )?[A-Za-z0-9_.\"'-]+(?=[ \\t]*[:=](?:\\s|$)))|(?<string>\(doubleQuoted)|\(singleQuoted))|(?<number>(?<![\\w.-])-?\\d[\\d_.]*(?![\\w.-]))|(?<ident>(?<![\\w.-])[A-Za-z_][A-Za-z0-9_]*(?![\\w.-]))", ["true", "false", "null", "yes", "no", "on", "off", "True", "False"])
        case .diff:
            return ("", [])
        }
    }

    private static func diffTokens(_ ns: NSString) -> [Token] {
        var tokens: [Token] = []
        var location = 0
        for line in (ns as String).components(separatedBy: "\n") {
            let length = (line as NSString).length
            let range = NSRange(location: location, length: length)
            let kind: Token.Kind?
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
                kind = .meta
            } else if line.hasPrefix("+") {
                kind = .added
            } else if line.hasPrefix("-") {
                kind = .removed
            } else {
                kind = nil
            }
            if let kind, length > 0 { tokens.append(Token(kind: kind, text: line, range: range)) }
            location += length + 1
        }
        return tokens
    }

    // MARK: - Colours

    /// A colour for each kind of token, one shade for a light window and one
    /// for a dark.
    static func color(for kind: Token.Kind) -> Color {
        switch kind {
        case .keyword: return adaptive(light: (0.70, 0.27, 0.16), dark: (0.96, 0.60, 0.47))
        case .string: return adaptive(light: (0.12, 0.47, 0.22), dark: (0.60, 0.82, 0.55))
        case .comment: return adaptive(light: (0.45, 0.48, 0.52), dark: (0.52, 0.56, 0.60))
        case .number: return adaptive(light: (0.10, 0.35, 0.75), dark: (0.55, 0.72, 1.00))
        case .type: return adaptive(light: (0.42, 0.24, 0.66), dark: (0.78, 0.65, 0.96))
        case .key: return adaptive(light: (0.08, 0.40, 0.60), dark: (0.50, 0.78, 0.95))
        case .variable: return adaptive(light: (0.55, 0.36, 0.05), dark: (0.93, 0.78, 0.45))
        case .added: return adaptive(light: (0.10, 0.50, 0.20), dark: (0.50, 0.85, 0.55))
        case .removed: return adaptive(light: (0.75, 0.15, 0.15), dark: (0.98, 0.50, 0.48))
        case .meta: return adaptive(light: (0.35, 0.35, 0.70), dark: (0.66, 0.68, 0.98))
        }
    }

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    // MARK: - Keywords

    static let swiftKeywords: Set<String> = [
        "actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
        "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
        "final", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "lazy",
        "mutating", "nil", "nonisolated", "open", "operator", "override", "private", "protocol", "public",
        "repeat", "rethrows", "return", "self", "Self", "some", "any", "static", "struct", "subscript", "super",
        "switch", "throw", "throws", "true", "try", "typealias", "var", "weak", "where", "while",
    ]
    static let jsKeywords: Set<String> = [
        "abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for",
        "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "keyof", "let",
        "new", "null", "of", "private", "protected", "public", "readonly", "return", "set", "static", "super",
        "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield",
    ]
    static let goKeywords: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "false", "for",
        "func", "go", "goto", "if", "import", "interface", "iota", "map", "nil", "package", "range", "return",
        "select", "struct", "switch", "true", "type", "var",
    ]
    static let kotlinKeywords: Set<String> = [
        "as", "break", "by", "class", "companion", "const", "continue", "data", "do", "else", "enum", "false",
        "for", "fun", "if", "import", "in", "init", "interface", "internal", "is", "lateinit", "null", "object",
        "open", "override", "package", "private", "protected", "public", "return", "sealed", "super", "suspend",
        "this", "throw", "true", "try", "typealias", "val", "var", "when", "while",
    ]
    static let rustKeywords: Set<String> = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false",
        "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
        "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
    ]
    static let cKeywords: Set<String> = [
        "auto", "bool", "break", "case", "catch", "char", "class", "const", "continue", "default", "delete", "do",
        "double", "else", "enum", "extends", "extern", "false", "final", "float", "for", "if", "implements",
        "import", "int", "interface", "long", "namespace", "new", "null", "nullptr", "package", "private",
        "protected", "public", "return", "short", "signed", "sizeof", "static", "struct", "switch", "template",
        "this", "throw", "throws", "true", "try", "typedef", "union", "unsigned", "using", "var", "virtual",
        "void", "volatile", "while",
    ]
    static let pythonKeywords: Set<String> = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
        "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is",
        "lambda", "match", "case", "nonlocal", "not", "or", "pass", "raise", "return", "self", "try", "while",
        "with", "yield",
    ]
    static let shellKeywords: Set<String> = [
        "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function", "if", "in", "local",
        "readonly", "return", "select", "then", "until", "while", "sudo", "cd", "echo", "set", "unset", "source",
    ]
}

/// Running a shell snippet from a reply in Terminal.
public enum NexusAgentShellSnippet {
    /// The commands a block holds. A console transcript, where commands
    /// follow a `$ ` or `% ` prompt among the lines they printed, is its
    /// prompted lines without the prompt; any other block is run as written.
    public static func runnableScript(from code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        let prompts = ["$ ", "% "]
        let prompted = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let prompt = prompts.first(where: { trimmed.hasPrefix($0) }) else { return nil }
            return String(trimmed.dropFirst(prompt.count))
        }
        return prompted.isEmpty ? code : prompted.joined(separator: "\n")
    }

    /// The `.command` file Terminal runs: a login shell, so the person's
    /// PATH is set, in `directory` when there is one. The file deletes
    /// itself as it starts.
    public static func commandFile(script: String, directory: String?) -> String {
        var text = "#!/bin/zsh -l\nrm -f -- \"$0\"\n"
        if let directory, !directory.isEmpty {
            text += "cd -- '\(directory.replacingOccurrences(of: "'", with: "'\\''"))' || exit 1\n"
        }
        text += "clear\n"
        text += script
        if !script.hasSuffix("\n") { text += "\n" }
        return text
    }

    /// Writes the snippet to a private `.command` file in the temporary
    /// folder and opens it, which runs it in Terminal.
    @MainActor
    @discardableResult
    public static func runInTerminal(_ code: String, directory: String?) -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-agent-snippet-\(UUID().uuidString).command")
        let contents = commandFile(script: runnableScript(from: code), directory: directory)
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: Data(contents.utf8),
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        ) else { return false }
        return NSWorkspace.shared.open(url)
    }
}

/// The two clicks of Run, as Clear All's (`NexusAgentClearAllGuard`): the
/// first turns the button into a question, a second within `window`
/// seconds runs the snippet.
public enum NexusAgentRunSnippetGuard {
    public static let window: TimeInterval = 3

    public static func isArmed(firstClick: Date?, now: Date) -> Bool {
        guard let firstClick else { return false }
        let waited = now.timeIntervalSince(firstClick)
        return waited >= 0 && waited < window
    }

    /// True when a click at `now` runs; otherwise it is a first click.
    public static func clickRuns(firstClick: Date?, now: Date) -> Bool {
        isArmed(firstClick: firstClick, now: now)
    }
}
