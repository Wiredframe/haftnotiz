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
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        minSize = NSSize(width: 180, height: 120)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let hosting = NSHostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
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
}
