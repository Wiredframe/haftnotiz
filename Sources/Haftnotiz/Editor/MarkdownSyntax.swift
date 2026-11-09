import Foundation

/// Finds the Markdown in one line of a note. Pure and line-local: the editor restyles only the
/// paragraphs that changed. Ranges are UTF-16 offsets into the line (`NSString` semantics).
///
/// Supported, on purpose no more: headings, bullets and numbered lists, checkboxes, quotes,
/// **bold**, *italic*, `code`, ~~strike~~, [links](url) and bare URLs.
enum MarkdownSyntax {
    enum Kind: Equatable {
        case heading(Int)
        /// Syntax characters shown dimmed (`#`, `**`, backticks, link brackets …).
        case marker
        case bullet
        /// `- [ ]` / `- [x]`, drawn as a circle by the editor.
        case checkbox(done: Bool)
        /// The text of a ticked checkbox line.
        case done
        case quote
        case bold
        case italic
        case code
        case strike
        case link(String)
    }

    struct Span: Equatable {
        let range: NSRange
        let kind: Kind
    }

    static func spans(in line: String) -> [Span] {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var spans: [Span] = []

        // Block prefix: at most one per line.
        if let m = heading.firstMatch(in: line, range: whole) {
            spans.append(Span(range: whole, kind: .heading(m.range(at: 1).length)))
            spans.append(Span(range: m.range, kind: .marker))
        } else if let m = checkbox.firstMatch(in: line, range: whole) {
            let done = ns.substring(with: m.range(at: 3)) != " "
            spans.append(Span(range: m.range(at: 2), kind: .checkbox(done: done)))
            if done {
                let start = m.range.upperBound
                spans.append(Span(range: NSRange(location: start, length: ns.length - start), kind: .done))
            }
        } else if let m = bullet.firstMatch(in: line, range: whole) {
            spans.append(Span(range: m.range(at: 2), kind: .bullet))
        } else if let m = quote.firstMatch(in: line, range: whole) {
            spans.append(Span(range: whole, kind: .quote))
            spans.append(Span(range: m.range(at: 1), kind: .marker))
        }

        // Inline. Code first; other syntax inside a code span is left alone.
        var codeRanges: [NSRange] = []
        for m in code.matches(in: line, range: whole) {
            codeRanges.append(m.range)
            spans.append(Span(range: m.range, kind: .code))
            spans.append(Span(range: NSRange(location: m.range.location, length: 1), kind: .marker))
            spans.append(Span(range: NSRange(location: m.range.upperBound - 1, length: 1), kind: .marker))
        }
        func outsideCode(_ r: NSRange) -> Bool { !codeRanges.contains { NSIntersectionRange($0, r).length > 0 } }

        for (regex, kind, markerLength) in [(bold, Kind.bold, 2), (italic, .italic, 1), (strike, .strike, 2)] {
            for m in regex.matches(in: line, range: whole) where outsideCode(m.range) {
                spans.append(Span(range: m.range, kind: kind))
                spans.append(Span(range: NSRange(location: m.range.location, length: markerLength), kind: .marker))
                spans.append(Span(range: NSRange(location: m.range.upperBound - markerLength, length: markerLength), kind: .marker))
            }
        }
        var linkRanges: [NSRange] = []
        for m in link.matches(in: line, range: whole) where outsideCode(m.range) {
            linkRanges.append(m.range)
            let url = ns.substring(with: m.range(at: 2))
            spans.append(Span(range: m.range(at: 1), kind: .link(url)))
            spans.append(Span(range: NSRange(location: m.range.location, length: 1), kind: .marker))
            let tail = m.range(at: 1).upperBound
            spans.append(Span(range: NSRange(location: tail, length: m.range.upperBound - tail), kind: .marker))
        }
        for m in bareURL.matches(in: line, range: whole)
        where outsideCode(m.range) && !linkRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            spans.append(Span(range: m.range, kind: .link(ns.substring(with: m.range))))
        }
        return spans
    }

    // MARK: - Patterns

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    private nonisolated(unsafe) static let heading = regex(#"^(#{1,6})[ \t]+"#)
    private nonisolated(unsafe) static let checkbox = regex(#"^([ \t]*)([-*+] \[([ xX])\])(?=[ \t]|$)"#)
    private nonisolated(unsafe) static let bullet = regex(#"^([ \t]*)([-*+]|\d+[.)])(?=[ \t])"#)
    private nonisolated(unsafe) static let quote = regex(#"^[ \t]*(>)"#)
    private nonisolated(unsafe) static let code = regex(#"`[^`\n]+`"#)
    private nonisolated(unsafe) static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private nonisolated(unsafe) static let italic = regex(#"(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?![*\w])|(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])"#)
    private nonisolated(unsafe) static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private nonisolated(unsafe) static let link = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private nonisolated(unsafe) static let bareURL = regex(#"https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"]"#)
}

/// What Return, Tab and ⇧⌘L do on a list line. Pure, so it is easy to test.
enum ListEditing {
    struct ListLine: Equatable {
        let indent: String
        /// `- `, `- [ ] `, `1. ` … including the trailing space.
        let marker: String
        let body: String
        var isCheckbox: Bool { marker.contains("[") }
    }

    enum ReturnAction: Equatable {
        /// Not a list line: a plain newline.
        case plain
        /// Start the next item with this prefix (indent + marker).
        case continueWith(String)
        /// The item is empty: remove its prefix (this many characters) and leave the list.
        case endList(prefixLength: Int)
    }

    private nonisolated(unsafe) static let listLine =
        try! NSRegularExpression(pattern: #"^([ \t]*)([-*+] \[[ xX]\] |[-*+] |(\d+)([.)]) )(.*)$"#)

    static func parse(_ line: String) -> ListLine? {
        let ns = line as NSString
        guard let m = listLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ListLine(indent: ns.substring(with: m.range(at: 1)), marker: ns.substring(with: m.range(at: 2)),
                        body: ns.substring(with: m.range(at: 5)))
    }

    /// Return at the end of `line` (the text before the caret on that line).
    static func returnAction(after line: String) -> ReturnAction {
        guard let item = parse(line) else { return .plain }
        if item.body.trimmingCharacters(in: .whitespaces).isEmpty {
            return .endList(prefixLength: (item.indent + item.marker as NSString).length)
        }
        return .continueWith(item.indent + nextMarker(after: item.marker))
    }

    private static func nextMarker(after marker: String) -> String {
        if marker.contains("[") { return String(marker.prefix(1)) + " [ ] " }
        let digits = marker.prefix { $0.isNumber }
        if let number = Int(digits) {
            return "\(number + 1)" + String(marker.dropFirst(digits.count))
        }
        return marker
    }

    /// ⌥↑ / ⌥↓: moves the whole lines touched by `selection` past the neighbouring line. Returns the
    /// range to replace, its replacement and the selection afterwards (same text selected), or nil at
    /// the start / end of the text.
    static func movingLines(in text: String, selection: NSRange, up: Bool)
        -> (range: NSRange, replacement: String, selection: NSRange)? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        // A selection ending right after a newline does not include the next line.
        var span = selection
        if span.length > 0, ns.character(at: span.upperBound - 1) == 0x0A { span.length -= 1 }
        let block = ns.lineRange(for: span)
        guard block.length > 0 else { return nil }
        let blockText = ns.substring(with: block)

        let range: NSRange
        let replacement: String
        let blockStart: Int   // where the block begins inside the replacement
        if up {
            guard block.location > 0 else { return nil }
            let previous = ns.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let previousText = ns.substring(with: previous)
            range = NSRange(location: previous.location, length: previous.length + block.length)
            replacement = blockText.hasSuffix("\n") ? blockText + previousText : blockText + "\n" + previousText.dropLast()
            blockStart = 0
        } else {
            guard block.upperBound < ns.length else { return nil }
            let next = ns.lineRange(for: NSRange(location: block.upperBound, length: 0))
            let nextText = ns.substring(with: next)
            range = NSRange(location: block.location, length: block.length + next.length)
            if nextText.hasSuffix("\n") {
                replacement = nextText + blockText
                blockStart = next.length
            } else {
                replacement = nextText + "\n" + blockText.dropLast()
                blockStart = next.length + 1
            }
        }
        let shift = range.location + blockStart - block.location
        return (range, replacement, NSRange(location: selection.location + shift, length: selection.length))
    }

    /// ⇧⌘L: a checkbox line loses its box (keeping a bullet), anything else becomes a checkbox.
    static func togglingCheckbox(_ line: String) -> String {
        if let item = parse(line) {
            if item.isCheckbox { return item.indent + "- " + item.body }
            return item.indent + "- [ ] " + item.body
        }
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        return indent + "- [ ] " + line.dropFirst(indent.count)
    }
}
