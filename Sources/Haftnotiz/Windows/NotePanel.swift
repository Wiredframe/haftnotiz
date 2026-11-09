import AppKit
import SwiftUI

/// One sticky note window. A titled panel with a hidden, transparent title bar gives rounded
/// corners, the system shadow and edge resizing, while `fullSizeContentView` lets the SwiftUI
/// content cover the whole surface. `nonactivatingPanel` makes clicking a note not pull every other
/// note forward. Taken over from Tic (MIT, Kasun Vithanage).
final class NotePanel: NSPanel {
    let noteID: String

    init(noteID: String, frame: CGRect, window: WindowState, content: AnyView) {
        self.noteID = noteID
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false   // dragged by its header only, so text selection works
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .aqua)   // light paper: menus, popovers and scrollers to match
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        minSize = NSSize(width: 200, height: 200)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // The window manager owns the size (square notes, roll-up). The hosting view sits inside a plain
        // container, so SwiftUI can never resize the window itself: as the window's content view it did,
        // in the middle of a layout pass when shrinking a note, and AppKit aborted with a layout loop.
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        contentView = container
        apply(pinned: window.pinned, showOnAllSpaces: window.showOnAllSpaces)
    }

    /// Pinned notes float above other windows; optionally on every Space.
    func apply(pinned: Bool, showOnAllSpaces: Bool) {
        level = pinned ? .floating : .normal
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
        if showOnAllSpaces { behavior.insert(.canJoinAllSpaces) }
        collectionBehavior = behavior
    }

    override var canBecomeKey: Bool { true }

    /// ⌘W: close the note (the app has no File menu that would do it).
    var onClose: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            onClose?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
