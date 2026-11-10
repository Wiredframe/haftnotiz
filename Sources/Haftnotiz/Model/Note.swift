import CoreGraphics
import Foundation

/// One note: a Markdown file in the notes folder. The file starts with a small, hidden YAML front
/// matter (`created`, `color`) that travels with the file; the editor only ever sees `body`.
struct Note: Identifiable, Equatable, Sendable {
    /// The file name, e.g. `Notiz 2026-11-09 125103.md`. Stable: the app never renames files.
    let id: String
    var body: String
    var frontMatter: FrontMatter
    /// Window state that belongs to this Mac, not to the file (see `WindowState`).
    var window: WindowState
    var modified: Date

    var color: NoteColor { NoteColor(stored: frontMatter["color"] ?? "") ?? .yellow }
    var created: Date? { frontMatter["created"].flatMap(FrontMatter.date(from:)) }

    /// The file's full contents: front matter plus body.
    var fileText: String { frontMatter.rendered(with: body) }

    /// The first non-empty line with its Markdown markers removed, for menus and the search palette.
    var title: String { Note.title(of: body) }

    static func title(of text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            var s = String(line).trimmingCharacters(in: .whitespaces)
            s = s.replacing(/^(#{1,6}\s+|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+|>\s*)/, with: "")
            s = s.replacing(/[*_~`]/, with: "")
            s = s.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { return s }
        }
        return ""
    }
}

/// Per-Mac window state of a note, kept in Application Support rather than in the file. Unknown keys
/// (like the former `material`) are ignored.
struct WindowState: Codable, Equatable, Sendable {
    var frame: CGRect?
    /// Pinned: the note floats above other windows.
    var pinned = false
    var showOnAllSpaces = false
    var isCollapsed = false
    var isOpen = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        showOnAllSpaces = try c.decodeIfPresent(Bool.self, forKey: .showOnAllSpaces) ?? false
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        isOpen = try c.decodeIfPresent(Bool.self, forKey: .isOpen) ?? false
    }
}

/// A minimal YAML front matter between `---` fences. Every line is kept verbatim (lists, comments,
/// whatever Obsidian or the user put there); only simple top-level `key: value` lines are read and
/// written by the app.
struct FrontMatter: Equatable, Sendable {
    private(set) var lines: [String] = []

    var isEmpty: Bool { lines.isEmpty }

    private func index(of key: String) -> Int? {
        lines.firstIndex { line in
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { return false }
            return line[..<colon].trimmingCharacters(in: .whitespaces) == key
        }
    }

    subscript(key: String) -> String? {
        get {
            guard let i = index(of: key), let colon = lines[i].firstIndex(of: ":") else { return nil }
            var value = lines[i][lines[i].index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.first == value.last, value.first == "\"" || value.first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        set {
            let i = index(of: key)
            switch (i, newValue) {
            case let (i?, value?): lines[i] = "\(key): \(value)"
            case let (i?, nil): lines.remove(at: i)
            case let (nil, value?): lines.append("\(key): \(value)")
            case (nil, nil): break
            }
        }
    }

    /// Splits a file into its front matter and body. A file without front matter is all body.
    static func split(_ text: String) -> (FrontMatter, String) {
        let all = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        guard all.first == "---",
              let close = all.indices.dropFirst().first(where: { all[$0] == "---" })
        else { return (FrontMatter(), text) }
        return (FrontMatter(lines: all[1..<close].map(String.init)), all[(close + 1)...].joined(separator: "\n"))
    }

    /// Front matter (if any) followed by the body.
    func rendered(with body: String) -> String {
        guard !lines.isEmpty else { return body }
        return "---\n" + lines.joined(separator: "\n") + "\n---\n" + body
    }

    // MARK: - Dates

    static func string(from date: Date) -> String {
        var format = Date.ISO8601FormatStyle(timeZone: .current)
        format = format.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false)
            .timeSeparator(.colon).timeZone(separator: .colon)
        return date.formatted(format)
    }

    static func date(from string: String) -> Date? {
        (try? Date.ISO8601FormatStyle(timeZone: .current).parse(string))
            ?? (try? Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash).parse(string))
    }
}
