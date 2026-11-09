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

    var color: NoteColor { NoteColor(rawValue: frontMatter["color"] ?? "") ?? .yellow }
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

/// Per-Mac window state of a note, kept in Application Support rather than in the file.
struct WindowState: Codable, Equatable, Sendable {
    var frame: CGRect?
    var material: NoteMaterial = .solid
    /// Pinned: the note floats above other windows.
    var pinned = false
    var showOnAllSpaces = false
    var isCollapsed = false
    var isOpen = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame)
        material = try c.decodeIfPresent(NoteMaterial.self, forKey: .material) ?? .solid
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        showOnAllSpaces = try c.decodeIfPresent(Bool.self, forKey: .showOnAllSpaces) ?? false
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        isOpen = try c.decodeIfPresent(Bool.self, forKey: .isOpen) ?? false
    }
}

/// A minimal YAML front matter: flat `key: value` lines between `---` fences. Order and unknown keys
/// (e.g. ones Obsidian adds) are kept as they are.
struct FrontMatter: Equatable, Sendable {
    private(set) var fields: [(key: String, value: String)] = []

    static func == (lhs: FrontMatter, rhs: FrontMatter) -> Bool {
        lhs.fields.map(\.key) == rhs.fields.map(\.key) && lhs.fields.map(\.value) == rhs.fields.map(\.value)
    }

    subscript(key: String) -> String? {
        get { fields.first { $0.key == key }?.value }
        set {
            if let index = fields.firstIndex(where: { $0.key == key }) {
                if let newValue { fields[index].value = newValue } else { fields.remove(at: index) }
            } else if let newValue {
                fields.append((key, newValue))
            }
        }
    }

    var isEmpty: Bool { fields.isEmpty }

    /// Splits a file into its front matter and body. A file without front matter is all body.
    static func split(_ text: String) -> (FrontMatter, String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---",
              let close = lines.indices.dropFirst().first(where: { lines[$0] == "---" })
        else { return (FrontMatter(), text) }
        var matter = FrontMatter()
        for line in lines[1..<close] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            if !key.isEmpty { matter.fields.append((key, value)) }
        }
        return (matter, lines[(close + 1)...].joined(separator: "\n"))
    }

    /// Front matter (if any) followed by the body.
    func rendered(with body: String) -> String {
        guard !fields.isEmpty else { return body }
        let header = fields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return "---\n\(header)\n---\n\(body)"
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
