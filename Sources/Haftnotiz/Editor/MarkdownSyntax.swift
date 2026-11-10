import Foundation

/// Finds the Markdown in one line of a note. Pure and line-local: the editor restyles only the
/// paragraphs that changed. Ranges are UTF-16 offsets into the line (`NSString` semantics).
///
/// Supported, on purpose no more: headings, bullets and numbered lists, checkboxes, quotes,
/// horizontal rules, **bold**, *italic*, `code`, ~~strike~~, [links](url) and bare URLs.
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
        /// `---`, `***` or `___` alone on a line, drawn as a line by the editor.
        case rule
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

        // Block prefix: at most one per line. A rule is the whole line, nothing inline in it.
        if rule.firstMatch(in: line, range: whole) != nil {
            return [Span(range: whole, kind: .rule)]
        }
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
    private nonisolated(unsafe) static let rule = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private nonisolated(unsafe) static let quote = regex(#"^[ \t]*(>)"#)
    private nonisolated(unsafe) static let code = regex(#"`[^`\n]+`"#)
    private nonisolated(unsafe) static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private nonisolated(unsafe) static let italic = regex(#"(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?![*\w])|(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])"#)
    private nonisolated(unsafe) static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private nonisolated(unsafe) static let link = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private nonisolated(unsafe) static let bareURL = regex(#"https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"]"#)
}

/// What Return and Tab do on a list line, and ⌥↑ / ⌥↓. Pure, so it is easy to test.
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

}

/// What ⌘B, ⌘I, ⇧⌘S, ⌘E and ⌘K do with the selection. Pure, so it is easy to test.
enum InlineFormatting {
    typealias Edit = (range: NSRange, replacement: String, selection: NSRange)

    /// Wraps the selection in `marker`, or unwraps it when it is already wrapped (markers just
    /// outside the selection or at its own edges). `*` only counts as wrapped in odd runs, so
    /// ⌘I inside `**bold**` adds italics instead of breaking the bold, and the other way round.
    ///
    /// The markers go around the text of each selected line, never around a block prefix
    /// (`- [ ] `, `# `, `> `, list markers), the line break or surrounding spaces, so a
    /// triple-clicked list item stays a list item. Over several lines: if every line is already
    /// wrapped, all are unwrapped, otherwise the lines that are not get wrapped.
    static func toggling(_ marker: String, in text: String, selection: NSRange) -> Edit {
        guard selection.length > 0 else { return togglingSegment(marker, in: text, selection: selection) }
        let segments = contentSegments(in: text, selection: selection)
        if segments.isEmpty { return togglingSegment(marker, in: text, selection: selection) }
        if segments.count == 1 { return togglingSegment(marker, in: text, selection: segments[0]) }

        let edits = segments.map { togglingSegment(marker, in: text, selection: $0) }
        func unwraps(_ e: Edit) -> Bool { (e.replacement as NSString).length < e.range.length }
        let chosen = edits.allSatisfy(unwraps) ? edits : edits.filter { !unwraps($0) }
        let ns = text as NSString
        let span = NSRange(location: chosen[0].range.location,
                           length: chosen[chosen.count - 1].range.upperBound - chosen[0].range.location)
        let result = NSMutableString(string: ns.substring(with: span))
        for e in chosen.reversed() {
            result.replaceCharacters(in: NSRange(location: e.range.location - span.location, length: e.range.length),
                                     with: e.replacement)
        }
        let delta = chosen.dropLast().reduce(0) { $0 + ($1.replacement as NSString).length - $1.range.length }
        let start = chosen[0].selection.location
        let end = chosen[chosen.count - 1].selection.upperBound + delta
        return (span, result as String, NSRange(location: start, length: end - start))
    }

    /// The selected part of each line's text: without block prefix, line break and outer spaces.
    static func contentSegments(in text: String, selection: NSRange) -> [NSRange] {
        let ns = text as NSString
        let block = LineEditing.lineBlock(in: ns, selection: selection)
        var segments: [NSRange] = []
        ns.enumerateSubstrings(in: block, options: [.byLines]) { line, lineRange, _, _ in
            guard let line else { return }
            let contentStart = lineRange.location + LineEditing.blockPrefixLength(line)
            let lower = max(contentStart, selection.location)
            var upper = min(lineRange.upperBound, selection.upperBound)
            var start = lower
            while start < upper, ns.character(at: start) == 0x20 || ns.character(at: start) == 0x09 { start += 1 }
            while upper > start, ns.character(at: upper - 1) == 0x20 || ns.character(at: upper - 1) == 0x09 { upper -= 1 }
            if upper > start { segments.append(NSRange(location: start, length: upper - start)) }
        }
        return segments
    }

    private static func togglingSegment(_ marker: String, in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        let m = (marker as NSString).length
        let unit = (marker as NSString).character(at: 0)
        func canUnwrap(_ run: Int) -> Bool { run >= m && (m != 1 || run % 2 == 1) }
        func run(from start: Int, step: Int, limit: Int) -> Int {
            var i = start, n = 0
            while i != limit, ns.character(at: i) == unit { n += 1; i += step }
            return n
        }

        // Markers around the selection.
        let before = run(from: selection.location - 1, step: -1, limit: -1)
        let after = run(from: selection.upperBound, step: 1, limit: ns.length)
        if canUnwrap(min(before, after)) {
            let outer = NSRange(location: selection.location - m, length: selection.length + 2 * m)
            return (outer, ns.substring(with: selection), NSRange(location: outer.location, length: selection.length))
        }
        // Markers inside the selection, at its edges.
        if selection.length >= 2 * m {
            let lead = run(from: selection.location, step: 1, limit: selection.upperBound)
            let trail = run(from: selection.upperBound - 1, step: -1, limit: selection.location - 1)
            if lead < selection.length, canUnwrap(min(lead, trail)) {
                let inner = ns.substring(with: NSRange(location: selection.location + m, length: selection.length - 2 * m))
                return (selection, inner, NSRange(location: selection.location, length: selection.length - 2 * m))
            }
        }
        let selected = ns.substring(with: selection)
        return (selection, marker + selected + marker, NSRange(location: selection.location + m, length: selection.length))
    }

    private nonisolated(unsafe) static let clearPatterns: [(NSRegularExpression, String)] = [
        (#"`([^`\n]+)`"#, "$1"),
        (#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, "$2"),
        (#"~~(?=\S)(.+?)(?<=\S)~~"#, "$1"),
        (#"==(?=\S)(.+?)(?<=\S)=="#, "$1"),
        (#"(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?![*\w])|(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])"#, "$1$2"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// Removes bold, italic, strikethrough, highlight and code markers from the selection (or the
    /// whole line without one), including markers right around the selection.
    static func clearing(in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        var range = selection.length > 0 ? selection : LineEditing.lineBlock(in: ns, selection: selection)
        let markers = Set("*_~`=".utf16)
        while range.location > 0, range.upperBound < ns.length,
              markers.contains(ns.character(at: range.location - 1)), markers.contains(ns.character(at: range.upperBound)) {
            range = NSRange(location: range.location - 1, length: range.length + 2)
        }
        var result = ns.substring(with: range)
        var changed = true
        while changed {   // nested formatting (`***x***`) needs more than one pass
            changed = false
            for (regex, template) in clearPatterns {
                let all = NSRange(location: 0, length: (result as NSString).length)
                let next = regex.stringByReplacingMatches(in: result, range: all, withTemplate: template)
                if next != result { result = next; changed = true }
            }
        }
        let length = (result as NSString).length
        let newSelection = selection.length > 0
            ? NSRange(location: range.location, length: length)
            : NSRange(location: range.location + length, length: 0)
        return (range, result, newSelection)
    }

    /// `[selection]()` with the caret between the parentheses; a selected URL becomes `[](url)`
    /// with the caret in the brackets.
    static func link(in text: String, selection: NSRange) -> Edit {
        let selected = (text as NSString).substring(with: selection)
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            return (selection, "[](\(selected))", NSRange(location: selection.location + 1, length: 0))
        }
        let caret = selection.location + selection.length + 3
        return (selection, "[\(selected)]()", NSRange(location: caret, length: 0))
    }
}

/// Commands on whole lines: headings (⌘0–⌘6), lists (⇧⌘7, ⇧⌘8, ⇧⌘L), duplicate (⇧⌘D) and
/// delete (⇧⌘K). They act on every line the selection touches. Pure, so it is easy to test.
enum LineEditing {
    typealias Edit = (range: NSRange, replacement: String, selection: NSRange)

    /// The lines touched by `selection`, without the trailing newline; a selection ending right
    /// after a newline does not include the next line.
    static func lineBlock(in ns: NSString, selection: NSRange) -> NSRange {
        var span = selection
        if span.length > 0, ns.character(at: span.upperBound - 1) == 0x0A { span.length -= 1 }
        var block = ns.lineRange(for: span)
        if block.length > 0, ns.character(at: block.upperBound - 1) == 0x0A { block.length -= 1 }
        return block
    }

    /// Replaces the touched lines with `transform(lines)`; the caret or selection keeps its place
    /// in the text (shifted by what changed in front of it).
    static func transforming(_ text: String, selection: NSRange, _ transform: ([String]) -> [String]) -> Edit {
        let ns = text as NSString
        let block = lineBlock(in: ns, selection: selection)
        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let new = transform(lines)
        let replacement = new.joined(separator: "\n")
        let firstDelta = (new[0] as NSString).length - (lines[0] as NSString).length
        let totalDelta = (replacement as NSString).length - block.length
        let start = max(block.location, selection.location + firstDelta)
        let end = max(start, selection.upperBound + totalDelta)
        return (block, replacement, NSRange(location: start, length: end - start))
    }

    // MARK: Headings

    static func headingLevel(_ line: String) -> (level: Int, prefixLength: Int) {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return (0, 0) }
        let rest = line.dropFirst(hashes)
        guard let first = rest.first, first == " " || first == "\t" else { return (0, 0) }
        return (hashes, hashes + rest.prefix { $0 == " " || $0 == "\t" }.count)
    }

    /// ⌘1–⌘6 make the lines headings of that level, pressed again (or ⌘0) plain text.
    static func settingHeading(_ level: Int, lines: [String]) -> [String] {
        let removing = level == 0 || lines.allSatisfy { $0.isEmpty || headingLevel($0).level == level }
        return lines.map { line in
            let body = String(line.dropFirst(headingLevel(line).prefixLength))
            if removing || (line.isEmpty && lines.count > 1) { return body }
            return String(repeating: "#", count: level) + " " + body
        }
    }

    /// How long a line's block prefix is: heading `## `, quote `> `, then indent and list marker
    /// (`- `, `1. `, `- [ ] `).
    static func blockPrefixLength(_ line: String) -> Int {
        let heading = headingLevel(line).prefixLength
        if heading > 0 { return heading }
        var length = 0
        var rest = Substring(line)
        if rest.hasPrefix(">") {
            let quote = rest.hasPrefix("> ") ? 2 : 1
            length += quote
            rest = rest.dropFirst(quote)
        }
        if let item = ListEditing.parse(String(rest)) {
            length += (item.indent + item.marker as NSString).length
        }
        return length
    }

    /// ⌘0: plain text, without heading, list marker or quote (indentation stays).
    static func settingPlain(lines: [String]) -> [String] {
        lines.map { line in
            var body = String(line.dropFirst(headingLevel(line).prefixLength))
            if body.hasPrefix(">") { body = body.hasPrefix("> ") ? String(body.dropFirst(2)) : String(body.dropFirst()) }
            if let item = ListEditing.parse(body) { body = item.indent + item.body }
            return body
        }
    }

    // MARK: Lists

    enum ListKind { case bullet, numbered, checkbox }

    static func kind(of item: ListEditing.ListLine) -> ListKind {
        if item.isCheckbox { return .checkbox }
        return item.marker.first?.isNumber == true ? .numbered : .bullet
    }

    /// ⇧⌘8 / ⇧⌘7 / ⇧⌘L: turns the lines into that kind of list, numbered from 1; if they already
    /// all are, back into plain text (a checkbox keeps its bullet, as before). Blank lines in a
    /// longer selection stay blank.
    static func settingList(_ target: ListKind, lines: [String]) -> [String] {
        let content = lines.count > 1 ? lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } : lines
        let removing = !content.isEmpty && content.allSatisfy { ListEditing.parse($0).map(kind) == target }
        var number = 0
        return lines.map { line in
            if lines.count > 1, line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            let line = String(line.dropFirst(headingLevel(line).prefixLength))   // a heading becomes the item's text
            let item = ListEditing.parse(line)
            let indent = item?.indent ?? String(line.prefix { $0 == " " || $0 == "\t" })
            let body = item?.body ?? String(line.dropFirst(indent.count))
            if removing { return target == .checkbox ? indent + "- " + body : indent + body }
            number += 1
            switch target {
            case .bullet: return indent + "- " + body
            case .numbered: return indent + "\(number). " + body
            case .checkbox: return indent + (item?.isCheckbox == true ? item!.marker : "- [ ] ") + body
            }
        }
    }

    // MARK: Quote

    /// Quotes the lines with `> `, or unquotes them when they all are.
    static func settingQuote(lines: [String]) -> [String] {
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let removing = !content.isEmpty && content.allSatisfy { $0.hasPrefix(">") }
        return lines.map { line in
            if removing { return line.hasPrefix("> ") ? String(line.dropFirst(2)) : String(line.drop { $0 == ">" }) }
            if lines.count > 1, line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            return "> " + line
        }
    }

    // MARK: Duplicate and delete

    /// ⇧⌘D: copies the lines below themselves and moves the selection onto the copy.
    static func duplicating(in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        let block = lineBlock(in: ns, selection: selection)
        let inserted = "\n" + ns.substring(with: block)
        let shift = (inserted as NSString).length
        return (NSRange(location: block.upperBound, length: 0), inserted,
                NSRange(location: selection.location + shift, length: selection.length))
    }

    /// ⇧⌘K: removes the lines; the caret goes to the start of the line that follows (or, for the
    /// last line, the end of the one before).
    static func deleting(in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        let block = lineBlock(in: ns, selection: selection)
        if block.upperBound < ns.length {
            let range = NSRange(location: block.location, length: block.length + 1)
            return (range, "", NSRange(location: block.location, length: 0))
        }
        let start = max(0, block.location - 1)
        let range = NSRange(location: start, length: block.upperBound - start)
        return (range, "", NSRange(location: start, length: 0))
    }
}
