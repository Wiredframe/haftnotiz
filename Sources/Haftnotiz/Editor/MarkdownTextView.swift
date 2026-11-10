import AppKit

/// The note's writing surface: a plain-text `NSTextView` with list helpers and clickable checkboxes.
///
/// - Return continues a list (`- `, `- [ ] `, `1. `); Return on an empty item ends it.
/// - Tab / ⇧Tab indent and outdent a list item.
/// - ⌥↑ / ⌥↓ move the current line (or all selected lines) up or down.
/// - ⌘B / ⌘I / ⇧⌘S / ⌘E wrap the selection in `**` / `*` / `~~` / backticks, or unwrap it;
///   ⌘K makes a link.
/// - On every selected line: ⌘1–⌘6 heading, ⌘0 plain text (no heading, list or quote), ⇧⌘8 / ⇧⌘7 / ⇧⌘L bullet, numbered
///   or checkbox list and back, ⇧⌘D duplicate, ⇧⌘K delete.
/// - The context menu offers all of this (with the shortcuts, for those who forget them), plus
///   clearing formatting, quotes and a horizontal rule.
/// - The standard editing shortcuts are handled here too, so they work without an Edit menu.
/// - A click on a checkbox circle ticks it (undoable), without moving the caret.
final class MarkdownTextView: NSTextView {
    /// Take the keyboard (caret at the end) once the view is in a window, for a new note.
    var focusOnAppear = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnAppear, let window else { return }
        focusOnAppear = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window.makeFirstResponder(self)
            self.setSelectedRange(NSRange(location: (self.string as NSString).length, length: 0))
        }
    }

    // MARK: - Checkboxes

    /// Notes are non-activating panels: let the first click on an inactive note reach a checkbox.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let range = checkboxRange(at: convert(event.locationInWindow, from: nil)) {
            toggleCheckbox(range)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let storage = textStorage, let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        storage.enumerateAttribute(.haftCheckbox, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            var rect = layoutManager.boundingRect(
                forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: textContainer
            )
            rect.size.width = min(rect.width, 18)
            addCursorRect(rect.offsetBy(dx: origin.x, dy: origin.y), cursor: .pointingHand)
        }
    }

    private func checkboxRange(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, let layoutManager, let textContainer, storage.length > 0 else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: p, in: textContainer)
        let char = layoutManager.characterIndexForGlyph(at: glyph)
        guard char < storage.length else { return nil }
        var range = NSRange()
        guard storage.attribute(.haftCheckbox, at: char, effectiveRange: &range) != nil else { return nil }
        var rect = layoutManager.boundingRect(
            forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: textContainer
        )
        rect.size.width = min(rect.width, 18)
        return rect.insetBy(dx: -3, dy: 0).contains(p) ? range : nil
    }

    /// Flips the character between the brackets of `- [ ]` / `- [x]`.
    private func toggleCheckbox(_ range: NSRange) {
        let inner = NSRange(location: range.upperBound - 2, length: 1)
        let current = (string as NSString).substring(with: inner)
        replace(inner, with: current == " " ? "x" : " ", selecting: selectedRange())
    }

    // MARK: - Lists

    private var currentLineRange: NSRange {
        (string as NSString).lineRange(for: NSRange(location: selectedRange().location, length: 0))
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        let lineRange = currentLineRange
        let lineStart = lineRange.location
        let ns = string as NSString
        // An empty item ends the list wherever the caret sits in it (e.g. before the trailing space).
        let wholeLine = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        if selection.length == 0, let item = ListEditing.parse(wholeLine.hasSuffix("]") ? wholeLine + " " : wholeLine),
           item.body.trimmingCharacters(in: .whitespaces).isEmpty {
            let length = (wholeLine as NSString).length
            replace(NSRange(location: lineStart, length: length), with: "", selecting: NSRange(location: lineStart, length: 0))
            return
        }
        let beforeCaret = ns.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        switch ListEditing.returnAction(after: beforeCaret) {
        case .plain:
            super.insertNewline(sender)
        case let .continueWith(prefix):
            insertText("\n" + prefix, replacementRange: selection)
        case let .endList(prefixLength):
            replace(NSRange(location: lineStart, length: prefixLength), with: "",
                    selecting: NSRange(location: lineStart, length: 0))
        }
    }

    override func insertTab(_ sender: Any?) {
        if isOnListItem { shiftLine(by: 1) } else { insertText("    ", replacementRange: selectedRange()) }
    }

    override func insertBacktab(_ sender: Any?) {
        if isOnListItem { shiftLine(by: -1) }
    }

    private var isOnListItem: Bool {
        let line = (string as NSString).substring(with: currentLineRange).trimmingCharacters(in: .newlines)
        return ListEditing.parse(line) != nil
    }

    private func shiftLine(by direction: Int) {
        let selection = selectedRange()
        let start = currentLineRange.location
        if direction > 0 {
            replace(NSRange(location: start, length: 0), with: "    ",
                    selecting: NSRange(location: selection.location + 4, length: selection.length))
        } else {
            let line = (string as NSString).substring(with: currentLineRange)
            let removable = line.hasPrefix("\t") ? 1 : min(4, line.prefix { $0 == " " }.count)
            guard removable > 0 else { return }
            replace(NSRange(location: start, length: removable), with: "",
                    selecting: NSRange(location: max(start, selection.location - removable), length: selection.length))
        }
    }

    // MARK: - Moving lines

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if mods == .option, event.keyCode == 126 || event.keyCode == 125 {
            moveLines(up: event.keyCode == 126)
            return
        }
        super.keyDown(with: event)
    }

    private func moveLines(up: Bool) {
        guard let move = ListEditing.movingLines(in: string, selection: selectedRange(), up: up) else {
            NSSound.beep()
            return
        }
        replace(move.range, with: move.replacement, selecting: move.selection)
        scrollRangeToVisible(move.selection)
    }

    // MARK: - Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        // Digits by key position: with ⇧ the character depends on the layout (⇧7 is "/" in German).
        let digitKeys: [UInt16: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8]
        if let digit = digitKeys[event.keyCode] {
            switch (mods, digit) {
            case ([.command], 0):
                transformLines { LineEditing.settingPlain(lines: $0) }
                return true
            case ([.command], 1...6):
                transformLines { LineEditing.settingHeading(digit, lines: $0) }
                return true
            case ([.command, .shift], 7):
                transformLines { LineEditing.settingList(.numbered, lines: $0) }
                return true
            case ([.command, .shift], 8):
                transformLines { LineEditing.settingList(.bullet, lines: $0) }
                return true
            default:
                break
            }
        }
        switch (mods, event.charactersIgnoringModifiers?.lowercased()) {
        case ([.command], "b"):
            toggleWrap("**")
            return true
        case ([.command], "i"):
            toggleWrap("*")
            return true
        case ([.command, .shift], "s"):
            toggleWrap("~~")
            return true
        case ([.command], "e"):
            toggleWrap("`")
            return true
        case ([.command], "k"):
            apply(InlineFormatting.link(in: string, selection: selectedRange()))
            return true
        case ([.command, .shift], "l"):
            transformLines { LineEditing.settingList(.checkbox, lines: $0) }
            return true
        case ([.command, .shift], "d"):
            apply(LineEditing.duplicating(in: string, selection: selectedRange()))
            return true
        case ([.command, .shift], "k"):
            apply(LineEditing.deleting(in: string, selection: selectedRange()))
            return true
        case ([.command], "x"):
            cut(nil)
            return true
        case ([.command], "c"):
            copy(nil)
            return true
        case ([.command], "v"):
            pasteAsPlainText(nil)
            return true
        case ([.command], "a"):
            selectAll(nil)
            return true
        case ([.command], "z"):
            undoManager?.undo()
            return true
        case ([.command, .shift], "z"):
            undoManager?.redo()
            return true
        case ([.command], "f"):
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            performTextFinderAction(item)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func toggleWrap(_ marker: String) {
        apply(InlineFormatting.toggling(marker, in: string, selection: selectedRange()))
    }

    private func transformLines(_ transform: ([String]) -> [String]) {
        apply(LineEditing.transforming(string, selection: selectedRange(), transform))
    }

    private func apply(_ edit: (range: NSRange, replacement: String, selection: NSRange)) {
        replace(edit.range, with: edit.replacement, selecting: edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        // A copy: the text view may hand out the same menu every time, which must not grow.
        let menu = (super.menu(for: event)?.copy() as? NSMenu) ?? NSMenu()
        // Notes are plain Markdown: the system's Font submenu would do nothing.
        for item in menu.items where item.submenu?.items.contains(where: {
            $0.action == #selector(NSFontManager.orderFrontFontPanel(_:))
        }) == true {
            menu.removeItem(item)
        }
        let ours = markdownMenuItems()
        for (index, item) in (ours + [.separator()]).enumerated() { menu.insertItem(item, at: index) }
        return menu
    }

    private func markdownMenuItems() -> [NSMenuItem] {
        let ns = string as NSString
        let line = ns.substring(with: LineEditing.lineBlock(in: ns, selection: selectedRange())).components(separatedBy: "\n")[0]
        let level = LineEditing.headingLevel(line).level
        let list = ListEditing.parse(line).map(LineEditing.kind)
        let quoted = line.hasPrefix(">")
        let cmd: NSEvent.ModifierFlags = .command, shiftCmd: NSEvent.ModifierFlags = [.command, .shift]

        let format = submenu("Format", [
            item("Fett", "b", cmd) { $0.toggleWrap("**") },
            item("Kursiv", "i", cmd) { $0.toggleWrap("*") },
            item("Durchgestrichen", "s", shiftCmd) { $0.toggleWrap("~~") },
            item("Code", "e", cmd) { $0.toggleWrap("`") },
            .separator(),
            item("Formatierung entfernen") { $0.apply(InlineFormatting.clearing(in: $0.string, selection: $0.selectedRange())) },
        ])
        var headings = (1...6).map { n in
            item("Überschrift \(n)", "\(n)", cmd, on: level == n) { view in
                view.transformLines { LineEditing.settingHeading(n, lines: $0) }
            }
        }
        headings.append(item("Text", "0", cmd, on: level == 0 && list == nil && !quoted) { view in
            view.transformLines { LineEditing.settingPlain(lines: $0) }
        })
        let paragraph = submenu("Absatz", [
            item("Aufzählung", "8", shiftCmd, on: list == .bullet) { view in
                view.transformLines { LineEditing.settingList(.bullet, lines: $0) }
            },
            item("Nummerierte Liste", "7", shiftCmd, on: list == .numbered) { view in
                view.transformLines { LineEditing.settingList(.numbered, lines: $0) }
            },
            item("Checkliste", "l", shiftCmd, on: list == .checkbox) { view in
                view.transformLines { LineEditing.settingList(.checkbox, lines: $0) }
            },
            .separator(),
        ] + headings + [
            .separator(),
            item("Zitat", on: quoted) { view in view.transformLines { LineEditing.settingQuote(lines: $0) } },
        ])
        let insert = submenu("Einfügen", [
            item("Trennlinie") { $0.apply(LineEditing.insertingRule(in: $0.string, selection: $0.selectedRange())) },
        ])
        let lines = submenu("Zeile", [
            item("Nach oben", String(UnicodeScalar(NSUpArrowFunctionKey)!), .option) { $0.moveLines(up: true) },
            item("Nach unten", String(UnicodeScalar(NSDownArrowFunctionKey)!), .option) { $0.moveLines(up: false) },
            .separator(),
            item("Duplizieren", "d", shiftCmd) { $0.apply(LineEditing.duplicating(in: $0.string, selection: $0.selectedRange())) },
            item("Löschen", "k", shiftCmd) { $0.apply(LineEditing.deleting(in: $0.string, selection: $0.selectedRange())) },
        ])
        return [
            item("Link hinzufügen", "k", cmd) { $0.apply(InlineFormatting.link(in: $0.string, selection: $0.selectedRange())) },
            .separator(),
            format, paragraph, insert, lines,
        ]
    }

    /// A menu item running `action` on this view. The key equivalent is only shown: a context
    /// menu is not asked for shortcuts, `performKeyEquivalent` handles them.
    private func item(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [], on: Bool = false,
                      _ action: @escaping (MarkdownTextView) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.state = on ? .on : .off
        item.representedObject = MenuAction(action)
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    @objc private func runMenuAction(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.run(self)
    }

    /// An undoable replacement that goes through the normal change notifications.
    private func replace(_ range: NSRange, with text: String, selecting selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(selection)
    }
}

private final class MenuAction: NSObject {
    let run: (MarkdownTextView) -> Void
    init(_ run: @escaping (MarkdownTextView) -> Void) { self.run = run }
}
