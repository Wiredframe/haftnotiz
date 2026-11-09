import AppKit

/// The note's writing surface: a plain-text `NSTextView` with list helpers and clickable checkboxes.
///
/// - Return continues a list (`- `, `- [ ] `, `1. `); Return on an empty item ends it.
/// - Tab / ⇧Tab indent and outdent a list item.
/// - ⌥↑ / ⌥↓ move the current line (or all selected lines) up or down.
/// - ⌘B / ⌘I wrap the selection in `**` / `*`; ⇧⌘L turns the line into a checkbox and back.
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
        switch (mods, event.charactersIgnoringModifiers?.lowercased()) {
        case ([.command], "b"):
            wrapSelection(in: "**")
            return true
        case ([.command], "i"):
            wrapSelection(in: "*")
            return true
        case ([.command, .shift], "l"):
            toggleChecklist()
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

    private func wrapSelection(in marker: String) {
        let selection = selectedRange()
        let selected = (string as NSString).substring(with: selection)
        let length = (marker as NSString).length
        replace(selection, with: marker + selected + marker,
                selecting: NSRange(location: selection.location + length, length: selection.length))
    }

    private func toggleChecklist() {
        let range = currentLineRange
        let raw = (string as NSString).substring(with: range)
        let newline = raw.hasSuffix("\n") ? "\n" : ""
        let line = String(raw.dropLast(newline.count))
        let toggled = ListEditing.togglingCheckbox(line)
        let lineLength = (toggled as NSString).length
        replace(range, with: toggled + newline, selecting: NSRange(location: range.location + lineLength, length: 0))
    }

    /// An undoable replacement that goes through the normal change notifications.
    private func replace(_ range: NSRange, with text: String, selecting selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(selection)
    }
}
