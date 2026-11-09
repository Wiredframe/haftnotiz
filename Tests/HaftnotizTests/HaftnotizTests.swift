import AppKit
import SwiftUI
import Foundation
import Testing
@testable import Haftnotiz

@Suite("Markdown syntax")
struct MarkdownSyntaxTests {
    private func kinds(_ line: String) -> [MarkdownSyntax.Kind] { MarkdownSyntax.spans(in: line).map(\.kind) }

    private func text(_ line: String, _ kind: MarkdownSyntax.Kind) -> [String] {
        MarkdownSyntax.spans(in: line).filter { $0.kind == kind }.map { (line as NSString).substring(with: $0.range) }
    }

    @Test("headings carry their level and a dimmed marker")
    func headings() {
        #expect(kinds("## Markt") == [.heading(2), .marker])
        #expect(text("## Markt", .marker) == ["## "])
        #expect(kinds("#hashtag").isEmpty)
    }

    @Test("checkboxes cover the dash and box; ticked lines are struck through")
    func checkboxes() {
        #expect(text("- [ ] Milch", .checkbox(done: false)) == ["- [ ]"])
        #expect(text("  - [x] Milch", .checkbox(done: true)) == ["- [x]"])
        #expect(text("- [x] Milch", .done) == [" Milch"])
        #expect(kinds("- [] Milch") == [.bullet])
    }

    @Test("bullets and numbers are recognised, a dash without space is not")
    func bullets() {
        #expect(text("- eins", .bullet) == ["-"])
        #expect(text("12. zwölf", .bullet) == ["12."])
        #expect(kinds("-minus").isEmpty)
    }

    @Test("inline styles, with markers")
    func inline() {
        #expect(text("ein **fetter** Satz", .bold) == ["**fetter**"])
        #expect(text("ein *schräger* Satz", .italic) == ["*schräger*"])
        #expect(text("**fett**", .italic).isEmpty)
        #expect(text("ein `code` Stück", .code) == ["`code`"])
        #expect(text("~~weg~~", .strike) == ["~~weg~~"])
        #expect(text("ein **fetter** Satz", .marker) == ["**", "**"])
    }

    @Test("nothing is styled inside code")
    func codeWins() {
        #expect(text("`a **b** c`", .bold).isEmpty)
    }

    @Test("links and bare URLs")
    func links() {
        #expect(MarkdownSyntax.spans(in: "[Seite](https://example.com)").contains {
            $0.kind == .link("https://example.com") && $0.range == NSRange(location: 1, length: 5)
        })
        #expect(text("siehe https://example.com/a.", .link("https://example.com/a")) == ["https://example.com/a"])
    }
}

@Suite("List editing")
struct ListEditingTests {
    @Test("Return continues bullets, numbers and checkboxes")
    func continues() {
        #expect(ListEditing.returnAction(after: "- eins") == .continueWith("- "))
        #expect(ListEditing.returnAction(after: "  * eins") == .continueWith("  * "))
        #expect(ListEditing.returnAction(after: "9. neun") == .continueWith("10. "))
        #expect(ListEditing.returnAction(after: "- [x] erledigt") == .continueWith("- [ ] "))
        #expect(ListEditing.returnAction(after: "Text") == .plain)
    }

    @Test("Return on an empty item ends the list")
    func ends() {
        #expect(ListEditing.returnAction(after: "- ") == .endList(prefixLength: 2))
        #expect(ListEditing.returnAction(after: "    - [ ] ") == .endList(prefixLength: 10))
    }

    @Test("⇧⌘L toggles a checkbox")
    func toggle() {
        #expect(ListEditing.togglingCheckbox("Milch") == "- [ ] Milch")
        #expect(ListEditing.togglingCheckbox("  - Milch") == "  - [ ] Milch")
        #expect(ListEditing.togglingCheckbox("- [x] Milch") == "- Milch")
    }
}

@Suite("Front matter")
struct FrontMatterTests {
    @Test("split and render round-trip, unknown keys kept")
    func roundTrip() {
        let file = "---\ncreated: 2026-11-09T12:51:03+01:00\ncolor: blue\ntags: einkauf\n---\n# Markt\n- [ ] Käse"
        let (matter, body) = FrontMatter.split(file)
        #expect(matter["color"] == "blue")
        #expect(matter["tags"] == "einkauf")
        #expect(body == "# Markt\n- [ ] Käse")
        #expect(matter.rendered(with: body) == file)
    }

    @Test("a file without front matter is all body")
    func none() {
        let (matter, body) = FrontMatter.split("Hallo\n---\nWelt")
        #expect(matter.isEmpty)
        #expect(body == "Hallo\n---\nWelt")
    }

    @Test("created dates round-trip")
    func dates() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let parsed = try #require(FrontMatter.date(from: FrontMatter.string(from: date)))
        #expect(abs(parsed.timeIntervalSince(date)) < 1)
    }

    @Test("the title skips markers and empty lines")
    func title() {
        #expect(Note.title(of: "\n# **Einkauf** für Samstag\nrest") == "Einkauf für Samstag")
        #expect(Note.title(of: "- [ ] Milch") == "Milch")
        #expect(Note.title(of: "  \n") == "")
    }
}

@MainActor
@Suite("Note store")
struct NoteStoreTests {
    private func makeStore() throws -> (NoteStore, URL) {
        let base = FileManager.default.temporaryDirectory.appending(path: "haftnotiz-\(UUID().uuidString)")
        let store = NoteStore(folder: base.appending(path: "Notizen"), stateURL: base.appending(path: "fenster.json"),
                              writeDelay: .zero)
        return (store, base)
    }

    private func frame() -> CGRect { CGRect(x: 10, y: 10, width: 200, height: 200) }

    @Test("a note reaches the disk with front matter, and a fresh store reads it back")
    func persists() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let note = store.createNote(color: .green, frame: frame())
        store.setBody(note.id, "# Hallo\n- [ ] Welt")
        store.updateWindow(note.id) { $0.pinned = true }
        store.flush()

        let text = try String(contentsOf: store.folder.appending(path: note.id), encoding: .utf8)
        #expect(text.hasPrefix("---\ncreated: "))
        #expect(text.contains("color: green"))
        #expect(text.hasSuffix("---\n# Hallo\n- [ ] Welt"))

        let reread = NoteStore(folder: store.folder, stateURL: base.appending(path: "fenster.json"))
        let loaded = try #require(reread.note(note.id))
        #expect(loaded.body == "# Hallo\n- [ ] Welt")
        #expect(loaded.color == .green)
        #expect(loaded.created != nil)
        #expect(loaded.window.pinned)
        #expect(loaded.window.frame == frame())
    }

    @Test("an empty note never touches the disk and vanishes on close")
    func emptyNote() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let note = store.createNote(color: .yellow, frame: frame())
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: store.folder.appending(path: note.id).path))
        store.close(note.id)
        #expect(store.notes.isEmpty)
    }

    @Test("closing keeps a note with text, marked closed")
    func closeKeeps() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let note = store.createNote(color: .yellow, frame: frame(), body: "Text")
        store.close(note.id)
        #expect(store.note(note.id)?.window.isOpen == false)
    }

    @Test("files added, edited and removed outside the app are picked up")
    func outsideChanges() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let url = store.folder.appending(path: "Von außen.md")
        try "Erste Fassung".write(to: url, atomically: true, encoding: .utf8)
        store.refreshFromDisk()
        #expect(store.note("Von außen.md")?.body == "Erste Fassung")

        try "Zweite Fassung".write(to: url, atomically: true, encoding: .utf8)
        store.refreshFromDisk()
        #expect(store.note("Von außen.md")?.body == "Zweite Fassung")

        var removed: [String] = []
        store.onNoteRemoved = { removed.append($0) }
        try FileManager.default.removeItem(at: url)
        store.refreshFromDisk()
        #expect(store.note("Von außen.md") == nil)
        #expect(removed == ["Von außen.md"])
    }

    @Test("new notes get unique, stable file names")
    func uniqueNames() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let a = store.createNote(color: .yellow, frame: frame())
        let b = store.createNote(color: .yellow, frame: frame())
        #expect(a.id != b.id)
        #expect(a.id.hasPrefix("Notiz ") && a.id.hasSuffix(".md"))
    }
}

@Suite("Moving lines")
struct MovingLinesTests {
    private func move(_ text: String, _ selection: NSRange, up: Bool) -> (String, NSRange)? {
        guard let m = ListEditing.movingLines(in: text, selection: selection, up: up) else { return nil }
        return ((text as NSString).replacingCharacters(in: m.range, with: m.replacement), m.selection)
    }

    @Test("a line moves up and down, the caret travels with it")
    func single() throws {
        let text = "eins\nzwei\ndrei"
        let up = try #require(move(text, NSRange(location: 6, length: 0), up: true))   // caret in "zwei"
        #expect(up.0 == "zwei\neins\ndrei")
        #expect(up.1 == NSRange(location: 1, length: 0))
        let down = try #require(move(text, NSRange(location: 6, length: 0), up: false))
        #expect(down.0 == "eins\ndrei\nzwei")
        #expect(down.1 == NSRange(location: 11, length: 0))
    }

    @Test("the last line without a newline moves cleanly")
    func lastLine() throws {
        let up = try #require(move("eins\nzwei", NSRange(location: 7, length: 0), up: true))
        #expect(up.0 == "zwei\neins")
        let down = try #require(move("eins\nzwei", NSRange(location: 1, length: 0), up: false))
        #expect(down.0 == "zwei\neins")
        #expect(down.1 == NSRange(location: 6, length: 0))
    }

    @Test("selected lines move as a block; a selection ending at a line start excludes that line")
    func block() throws {
        let text = "a\nb\nc\nd\n"
        let moved = try #require(move(text, NSRange(location: 2, length: 4), up: false))   // "b\nc\n"
        #expect(moved.0 == "a\nd\nb\nc\n")
        #expect(moved.1 == NSRange(location: 4, length: 4))
    }

    @Test("nothing moves past the edges")
    func edges() {
        #expect(move("eins\nzwei", NSRange(location: 0, length: 0), up: true) == nil)
        #expect(move("eins\nzwei", NSRange(location: 6, length: 0), up: false) == nil)
        #expect(move("", NSRange(location: 0, length: 0), up: true) == nil)
    }
}

@Suite("Front matter keeps foreign lines")
struct FrontMatterPreservationTests {
    @Test("YAML lists and comments survive a colour change untouched")
    func keepsLists() {
        let file = "---\ncreated: 2026-11-09T12:51:03+01:00\ntags:\n  - einkauf\n  - samstag\n# Kommentar\ncolor: pink\n---\nText"
        var (matter, body) = FrontMatter.split(file)
        #expect(matter["tags"] == "")
        matter["color"] = "green"
        #expect(matter.rendered(with: body) == file.replacingOccurrences(of: "color: pink", with: "color: green"))
        matter["mood"] = "gut"
        body += "!"
        #expect(matter.rendered(with: body).hasSuffix("color: green\nmood: gut\n---\nText!"))
    }

    @Test("quoted values are read without quotes")
    func quotes() {
        let (matter, _) = FrontMatter.split("---\ncolor: \"blue\"\n---\n")
        #expect(matter["color"] == "blue")
    }
}

@MainActor
@Suite("Folder watching")
struct FolderWatchTests {
    @Test("an in-place rewrite (like Obsidian's) reaches the store without any manual refresh")
    func inPlaceWrite() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "haftnotiz-watch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = NoteStore(folder: base.appending(path: "Notizen"), stateURL: base.appending(path: "fenster.json"))
        let url = store.folder.appending(path: "Obsidian.md")
        try "eins".write(to: url, atomically: true, encoding: .utf8)
        store.refreshFromDisk()
        store.startWatching()
        defer { store.stopWatching() }

        let handle = try FileHandle(forWritingTo: url)   // overwrite in place, same inode
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("zwei".utf8))
        try handle.close()

        for _ in 0..<40 where store.note("Obsidian.md")?.body != "zwei" {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(store.note("Obsidian.md")?.body == "zwei")
    }
}

@MainActor
@Suite("Editor keys")
struct EditorKeyTests {
    private func makeView(_ text: String) -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        view.string = text
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return view
    }

    @Test("Return continues a checklist, Return on the empty item ends it")
    func returnInList() {
        let view = makeView("- [ ] Milch")
        view.insertNewline(nil)
        #expect(view.string == "- [ ] Milch\n- [ ] ")
        view.insertNewline(nil)
        #expect(view.string == "- [ ] Milch\n")
    }

    @Test("Return on an empty item ends the list even with the caret before the trailing space")
    func returnBeforeSpace() {
        let view = makeView("- [x] Milch\n- [ ] ")
        view.setSelectedRange(NSRange(location: 17, length: 0))   // between "]" and " "
        view.insertNewline(nil)
        #expect(view.string == "- [x] Milch\n")
    }

    @Test("a lone dash is not an empty item: Return keeps it")
    func loneDash() {
        let view = makeView("-")
        view.insertNewline(nil)
        #expect(view.string == "-\n")
    }

    @Test("the same through real key events")
    func returnKeyEvents() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let view = makeView("- [ ] Milch")
        window.contentView = view
        window.makeFirstResponder(view)
        func pressReturn() throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                      windowNumber: window.windowNumber, context: nil, characters: "\r",
                                                      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            view.keyDown(with: event)
        }
        try pressReturn()
        #expect(view.string == "- [ ] Milch\n- [ ] ")
        try pressReturn()
        #expect(view.string == "- [ ] Milch\n")
    }
}

@Suite("Hanging indent")
struct HangingIndentTests {
    @Test("wrapped list lines start where the item's text starts")
    func indents() throws {
        let box = try #require(MarkdownStyler.hangingIndent(for: "- [ ] Milch"))
        let bullet = try #require(MarkdownStyler.hangingIndent(for: "- Milch"))
        let nested = try #require(MarkdownStyler.hangingIndent(for: "    - [ ] Milch"))
        #expect(box > MarkdownStyler.checkboxWidth)
        #expect(bullet > 0 && bullet < box)
        #expect(nested > box)
        #expect(MarkdownStyler.hangingIndent(for: "Text") == nil)
    }
}

@MainActor
@Suite("Window resizing")
struct WindowResizeTests {
    @Test("shrinking a note far below its minimum and back lays out without an exception")
    func shrink() {
        let editor = NoteEditor(text: "- [ ] eine ziemlich lange Zeile, die umbrechen muss\n# Titel\nText", theme: NoteTheme(color: .yellow)) { _ in }
        let panel = NotePanel(noteID: "x", frame: CGRect(x: 200, y: 200, width: 400, height: 400), window: WindowState(),
                              content: AnyView(editor))
        panel.minSize = NSSize(width: 200, height: 200)
        panel.aspectRatio = NSSize(width: 1, height: 1)
        panel.orderFront(nil)
        for side in Array(stride(from: 400.0, through: 40.0, by: -15.0)) + Array(stride(from: 40.0, through: 420.0, by: 20.0)) {
            panel.setFrame(NSRect(x: 200, y: 200, width: side, height: side), display: true)
            panel.layoutIfNeeded()
            panel.displayIfNeeded()
        }
        panel.close()
        #expect(panel.frame.width == 420)
    }
}
