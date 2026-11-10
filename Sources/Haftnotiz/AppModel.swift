import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// App-wide coordinator: owns the note store and the window manager, and the actions the menu bar,
/// the Dock menu and the notes call.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let store: NoteStore
    let windows: NoteWindowManager
    @ObservationIgnored private var searchWindow: NSWindow?

    private init() {
        store = NoteStore.makeShared()
        windows = NoteWindowManager(store: store)
        NSLog("[Haftnotiz] notes folder \(store.folder.path)")
    }

    func bootstrap() {
        store.startWatching()
        if store.notes.isEmpty, !UserDefaults.standard.bool(forKey: Self.welcomedKey) {
            UserDefaults.standard.set(true, forKey: Self.welcomedKey)
            windows.newNote(body: Self.welcomeText)
        } else {
            windows.restoreAll()
        }
        applyLaunchAtLogin(launchAtLogin)
    }

    // MARK: - Actions

    func newNote() {
        windows.newNote()
    }

    func open(_ id: String) {
        windows.open(id)
        NSApp.activate()
    }

    func showAll() {
        windows.showAll()
        NSApp.activate()
    }

    /// Lets the user pick another notes folder; the open notes switch over.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.folder
        panel.prompt = "Auswählen"
        panel.message = "Ordner für die Notizen (eine Markdown-Datei je Notiz)"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, url != store.folder else { return }
        windows.closeAllWindows()
        store.changeFolder(to: url)
        windows.restoreAll()
    }

    func revealFolder() {
        NSWorkspace.shared.open(store.folder)
    }

    // MARK: - Search palette

    func openSearch() {
        if searchWindow == nil {
            // Borderless, so all four corners are rounded by the content (a titled window rounds only the top).
            let panel = SearchPanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 400),
                styleMask: [.borderless],
                backing: .buffered, defer: false
            )
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.contentView = NSHostingView(rootView: SearchView())
            searchWindow = panel
        }
        guard let window = searchWindow else { return }
        let pointer = NSEvent.mouseLocation
        if let area = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main)?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2 + 80))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func dismissSearch() {
        searchWindow?.orderOut(nil)
    }

    // MARK: - Launch at login

    private static let launchAtLoginKey = "launchAtLogin"
    private static let welcomedKey = "welcomed"

    private(set) var launchAtLogin = UserDefaults.standard.bool(forKey: AppModel.launchAtLoginKey)

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        UserDefaults.standard.set(enabled, forKey: Self.launchAtLoginKey)
        applyLaunchAtLogin(enabled)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled: try SMAppService.mainApp.register()
            case (false, .enabled): try SMAppService.mainApp.unregister()
            default: break
            }
        } catch {
            NSLog("[Haftnotiz] launch at login: \(error)")
        }
    }

    private static let welcomeText = """
    # Haftnotiz
    Einfach lostippen, die ganze Notiz ist Schreibfläche.

    - [ ] Zeile mit `- [ ] ` beginnen oder ⇧⌘L drücken
    - [x] Ein Klick auf den Kreis hakt ab
    - Aufzählungen mit `- `, einrücken mit Tab
    **fett** (⌘B), *kursiv* (⌘I), ~~durchgestrichen~~ (⇧⌘S), `Code` (⌘E)

    Jede Notiz ist eine Markdown-Datei. Der Pin oben rechts hält sie im Vordergrund, ein Doppelklick auf die Kopfzeile klappt sie zu.
    """
}

/// The search palette's window: borderless, but it must take the keyboard.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
