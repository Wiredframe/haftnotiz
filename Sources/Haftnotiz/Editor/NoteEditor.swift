import AppKit
import SwiftUI

/// The SwiftUI wrapper around the note's `MarkdownTextView`, filling the whole note below the header.
struct NoteEditor: NSViewRepresentable {
    let text: String
    let theme: NoteTheme
    var focusOnAppear = false
    let onChange: (String) -> Void

    static let inset = NSSize(width: 14, height: 4)

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = CheckboxLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = Self.inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.focusOnAppear = focusOnAppear
        textView.delegate = context.coordinator
        storage.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView
        // Keep the text view at least as tall as the note, so a click anywhere below the text lands in it.
        scrollView.contentView.postsFrameChangedNotifications = true
        context.coordinator.observeClipView(scrollView.contentView)

        context.coordinator.textView = textView
        context.coordinator.apply(theme: theme)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        if coordinator.theme != theme { coordinator.apply(theme: theme) }
        guard let textView = coordinator.textView, textView.string != text, !textView.hasMarkedText() else { return }
        // Changed elsewhere (another app, the folder watcher): take it over, keeping the caret if possible.
        let selection = textView.selectedRange()
        textView.string = text
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var onChange: (String) -> Void
        weak var textView: MarkdownTextView?
        var theme: NoteTheme?
        private var styler = MarkdownStyler(ink: .labelColor, secondary: .secondaryLabelColor, accent: .controlAccentColor)
        private var clipObserver: NSObjectProtocol?

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func apply(theme: NoteTheme) {
            self.theme = theme
            styler = MarkdownStyler(ink: theme.nsInk, secondary: theme.nsSecondary, accent: theme.nsAccent)
            guard let textView, let storage = textView.textStorage else { return }
            textView.insertionPointColor = theme.nsInk
            textView.typingAttributes = styler.baseAttributes
            textView.linkTextAttributes = [
                .foregroundColor: theme.nsAccent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                .cursor: NSCursor.pointingHand,
            ]
            textView.selectedTextAttributes = [.backgroundColor: theme.nsAccent.withAlphaComponent(0.28)]
            if let layoutManager = textView.layoutManager as? CheckboxLayoutManager {
                layoutManager.openColor = theme.nsSecondary
                layoutManager.doneColor = theme.nsCheckbox
            }
            styler.applyAll(to: storage)
            textView.needsDisplay = true
        }

        func observeClipView(_ clipView: NSClipView) {
            clipObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: clipView, queue: .main
            ) { [weak self, weak clipView] _ in
                MainActor.assumeIsolated {
                    guard let height = clipView?.bounds.height else { return }
                    self?.textView?.minSize = NSSize(width: 0, height: height)
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }

        nonisolated func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            // Text storage callbacks arrive on the main thread, where the text view lives.
            nonisolated(unsafe) let storage = textStorage
            MainActor.assumeIsolated {
                styler.apply(to: storage, in: editedRange)
                if let textView { textView.window?.invalidateCursorRects(for: textView) }
            }
        }
    }
}
