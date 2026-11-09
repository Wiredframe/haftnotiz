import AppKit
import SwiftUI

/// What a note's view can ask of its window.
struct NoteActions {
    let close: () -> Void
    let newNote: () -> Void
    let toggleCollapsed: () -> Void
    let togglePinned: () -> Void
    let toggleAllSpaces: () -> Void
    let delete: () -> Void
}

/// Owns the open `NotePanel`s, one per note, and keeps their frames in the store. The placement logic
/// (multiple displays, roll-up keeping the top edge) is taken over from Tic (MIT, Kasun Vithanage).
@MainActor
final class NoteWindowManager: NSObject, NSWindowDelegate {
    static let collapsedHeight: CGFloat = 38

    private let store: NoteStore
    private var panels: [String: NotePanel] = [:]
    /// Height a note had before it was rolled up.
    private var expandedHeights: [String: CGFloat] = [:]
    /// The frame the user last chose for each open note. Only user drags and resizes change it, so a
    /// note parked because its display went away returns to its spot when the display comes back.
    private var savedFrames: [String: CGRect] = [:]
    private var placing = false
    private var suppressSavesUntil = Date.distantPast
    /// The note created last, whose editor should take the keyboard when it appears.
    private var focusNoteID: String?

    init(store: NoteStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        store.onNoteRemoved = { [weak self] id in self?.panels[id]?.close() }
    }

    var openCount: Int { panels.count }

    func shouldFocus(_ id: String) -> Bool {
        guard focusNoteID == id else { return false }
        focusNoteID = nil
        return true
    }

    // MARK: - Opening

    /// Opens every note that was on screen at last quit.
    func restoreAll() {
        for note in store.notes where note.window.isOpen { open(note.id, makeKey: false) }
    }

    /// Closes all windows without marking the notes closed (folder switch).
    func closeAllWindows() {
        for panel in panels.values { panel.close() }
    }

    @discardableResult
    func open(_ id: String, makeKey: Bool = true) -> NotePanel? {
        if let existing = panels[id] {
            existing.makeKeyAndOrderFront(nil)
            return existing
        }
        guard let note = store.note(id) else { return nil }
        let frame = note.window.frame ?? defaultFrame(offset: panels.count)
        store.updateWindow(id) {
            $0.isOpen = true
            if $0.frame == nil { $0.frame = frame }
        }
        let actions = NoteActions(
            close: { [weak self] in self?.close(id) },
            newNote: { [weak self] in self?.newNote() },
            toggleCollapsed: { [weak self] in self?.toggleCollapsed(id) },
            togglePinned: { [weak self] in self?.togglePinned(id) },
            toggleAllSpaces: { [weak self] in self?.toggleAllSpaces(id) },
            delete: { [weak self] in self?.delete(id) }
        )
        let view = NoteView(store: store, id: id, actions: actions, focusOnAppear: shouldFocus(id))
        let panel = NotePanel(noteID: id, frame: frame, window: note.window, content: AnyView(view))
        panels[id] = panel
        savedFrames[id] = frame
        place(panel)
        if makeKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFront(nil) }
        if note.window.isCollapsed { setCollapsed(panel, collapsed: true, animate: false) }
        panel.delegate = self   // only now: the placement above is not a user move
        return panel
    }

    /// A new note, cascaded below and right of the last one.
    func newNote(body: String = "") {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let note = store.createNote(
            color: NoteColor.allCases.randomElement() ?? .yellow,
            frame: defaultFrame(offset: store.notes.count, screen: screen),
            body: body
        )
        focusNoteID = note.id
        open(note.id)
        NSApp.activate()
    }

    private func defaultFrame(offset: Int, screen: CGRect? = nil) -> CGRect {
        let area = screen ?? (NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
        let step = CGFloat(offset % 8) * 26
        let size = CGSize(width: 280, height: 280)
        return CGRect(x: area.minX + 140 + step, y: area.maxY - 100 - size.height - step,
                      width: size.width, height: size.height)
    }

    func showAll() {
        for panel in panels.values { panel.orderFront(nil) }
    }

    // MARK: - Actions

    func close(_ id: String) {
        store.close(id)
        panels[id]?.close()
    }

    func delete(_ id: String) {
        panels[id]?.close()
        store.delete(id)
    }

    private func toggleCollapsed(_ id: String) {
        guard let note = store.note(id) else { return }
        let collapsed = !note.window.isCollapsed
        store.updateWindow(id) { $0.isCollapsed = collapsed }
        if let panel = panels[id] { setCollapsed(panel, collapsed: collapsed, animate: true) }
    }

    private func togglePinned(_ id: String) {
        store.updateWindow(id) { $0.pinned.toggle() }
        applyBehavior(id)
    }

    private func toggleAllSpaces(_ id: String) {
        store.updateWindow(id) { $0.showOnAllSpaces.toggle() }
        applyBehavior(id)
    }

    private func applyBehavior(_ id: String) {
        guard let window = store.note(id)?.window else { return }
        panels[id]?.apply(pinned: window.pinned, showOnAllSpaces: window.showOnAllSpaces)
    }

    // MARK: - Roll-up and placement

    /// Rolls a panel up to its header (or back), keeping the top edge where it is.
    private func setCollapsed(_ panel: NotePanel, collapsed: Bool, animate: Bool) {
        let id = panel.noteID
        let current = panel.frame
        let target: CGFloat
        if collapsed {
            if current.height > Self.collapsedHeight { expandedHeights[id] = current.height }
            target = Self.collapsedHeight
            panel.minSize = NSSize(width: panel.minSize.width, height: target)
            panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: target)
        } else {
            target = expandedHeights[id] ?? savedFrames[id]?.height ?? max(current.height, 240)
            expandedHeights[id] = nil
            panel.minSize = NSSize(width: panel.minSize.width, height: 120)
            panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        let frame = NSRect(x: current.minX, y: current.maxY - target, width: current.width, height: target)
        panel.setFrame(frame, display: true, animate: animate)
    }

    /// Puts a panel at its saved frame when a display shows it, else parks it on the main display.
    private func place(_ panel: NotePanel) {
        guard let saved = savedFrames[panel.noteID], let main = NSScreen.main else { return }
        let target = Self.placement(for: saved, screens: NSScreen.screens.map(\.visibleFrame), main: main.visibleFrame)
        placing = true
        panel.setFrameOrigin(NSPoint(x: target.minX, y: target.maxY - panel.frame.height))
        placing = false
    }

    nonisolated static func placement(for saved: CGRect, screens: [CGRect], main: CGRect) -> CGRect {
        if isVisible(saved, onAnyOf: screens) { return saved }
        var frame = saved
        frame.origin.x = min(max(saved.minX, main.minX), main.maxX - saved.width)
        frame.origin.y = min(max(saved.minY, main.minY), main.maxY - saved.height)
        return frame
    }

    nonisolated static func isVisible(_ frame: CGRect, onAnyOf screens: [CGRect]) -> Bool {
        screens.contains { screen in
            let overlap = screen.intersection(frame)
            return overlap.width >= 80 && overlap.height >= 80
        }
    }

    /// macOS moves windows off a vanished display; those moves must not become the saved frame.
    @objc private func screensDidChange() {
        suppressSavesUntil = Date().addingTimeInterval(2)
        for panel in panels.values { place(panel) }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) { saveFrame(notification) }
    func windowDidResize(_ notification: Notification) { saveFrame(notification) }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NotePanel else { return }
        expandedHeights[panel.noteID] = nil
        savedFrames[panel.noteID] = nil
        panels[panel.noteID] = nil
    }

    private func saveFrame(_ notification: Notification) {
        guard let panel = notification.object as? NotePanel, !placing, Date() >= suppressSavesUntil else { return }
        let id = panel.noteID
        let live = panel.frame
        // Rolled up: keep the expanded height, and the top edge where it is.
        let collapsed = store.note(id)?.window.isCollapsed == true
        let height = collapsed ? (expandedHeights[id] ?? live.height) : live.height
        let frame = CGRect(x: live.minX, y: live.maxY - height, width: live.width, height: height)
        savedFrames[id] = frame
        store.updateWindow(id) { $0.frame = frame }
    }
}
