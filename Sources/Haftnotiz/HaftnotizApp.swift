import AppKit
import SwiftUI

@main
struct HaftnotizApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "note.text")
        }
    }
}

/// The menu bar menu: new note, recent notes, search, folder, launch at login, quit.
private struct MenuBarContent: View {
    private var model: AppModel { AppModel.shared }

    var body: some View {
        Button("Neue Notiz") { model.newNote() }
            .keyboardShortcut("n")
        Button("Alle Notizen nach vorne") { model.showAll() }

        Divider()

        let recent = model.store.byRecency.filter { !$0.title.isEmpty }
        if recent.isEmpty {
            Text("Noch keine Notizen")
        } else {
            Section("Zuletzt bearbeitet") {
                ForEach(Array(recent.prefix(6))) { note in
                    Button(String(note.title.prefix(48))) { model.open(note.id) }
                }
            }
        }
        Button("Notizen durchsuchen …") { model.openSearch() }
            .keyboardShortcut("f", modifiers: [.command, .shift])

        Divider()

        Button("Notizordner im Finder zeigen") { model.revealFolder() }
        Button("Notizordner wählen …") { model.chooseFolder() }
        Toggle("Beim Anmelden starten", isOn: Binding(
            get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
        ))

        Divider()

        Button("Haftnotiz beenden") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // No "AutoFill" (contacts, passwords) in the notes' context menu.
        UserDefaults.standard.register(defaults: ["NSAutoFillSystemInsertMenuEnabled": false])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one Haftnotiz at a time (e.g. a second copy of the app): two would edit the same files.
        if let bundleID = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .first(where: { $0 != NSRunningApplication.current }) {
            running.activate()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        AppModel.shared.bootstrap()
        // ⌘N while a note is key (the menu bar item's shortcut only works while its menu is open).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !flags.contains(.shift), !flags.contains(.option), !flags.contains(.control),
                  event.charactersIgnoringModifiers?.lowercased() == "n" else { return event }
            AppModel.shared.newNote()
            return nil
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard started else { return }
        AppModel.shared.store.refreshFromDisk()
    }

    private var started: Bool { keyMonitor != nil }

    func applicationWillTerminate(_ notification: Notification) {
        guard started else { return }   // a second instance quitting right away touches nothing
        AppModel.shared.store.flush()
    }

    /// A click on the Dock icon with no note open starts a new one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if AppModel.shared.windows.openCount == 0 { AppModel.shared.newNote() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Neue Notiz", action: #selector(newNote), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Notizen durchsuchen …", action: #selector(search), keyEquivalent: "").target = self
        return menu
    }

    @objc private func newNote() { AppModel.shared.newNote() }
    @objc private func search() { AppModel.shared.openSearch() }
}
