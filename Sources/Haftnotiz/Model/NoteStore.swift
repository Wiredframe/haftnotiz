import Foundation
import Observation

/// All notes, backed by one Markdown file each in the notes folder, plus a small JSON file in
/// Application Support with the per-Mac window state.
///
/// Writes are debounced and atomic. The folder is watched, and re-read when the app becomes active,
/// so edits made elsewhere (Obsidian, a text editor, sync) show up; a note with unsaved typing is never
/// overwritten from disk. Deleting moves the file to the Trash.
@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    private(set) var folder: URL

    @ObservationIgnored private let stateURL: URL
    /// What each file held when we last read or wrote it, to tell our own writes from outside edits.
    @ObservationIgnored private var diskText: [String: String] = [:]
    @ObservationIgnored private var pendingWrites: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingStateSave: Task<Void, Never>?
    /// Notes deleted since the last state save, whose entries must leave the state file.
    @ObservationIgnored private var forgotten: Set<String> = []
    @ObservationIgnored private var watcher: FSEventStreamRef?
    @ObservationIgnored private let writeDelay: Duration

    /// Called when a note's file disappeared from disk, so its window can close.
    @ObservationIgnored var onNoteRemoved: ((String) -> Void)?

    init(folder: URL, stateURL: URL, writeDelay: Duration = .milliseconds(400)) {
        self.folder = folder
        self.stateURL = stateURL
        self.writeDelay = writeDelay
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        load()
    }

    // MARK: - Locations

    private static let folderKey = "notesFolder"

    /// `~/Vault/Wiredframe/Notizen/Haftnotiz` when the vault exists, else Application Support.
    static var defaultFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let vault = home.appending(path: "Vault/Wiredframe/Notizen", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: vault.path) {
            return vault.appending(path: "Haftnotiz", directoryHint: .isDirectory)
        }
        return supportDirectory.appending(path: "Notizen", directoryHint: .isDirectory)
    }

    static var supportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Haftnotiz", directoryHint: .isDirectory)
    }

    static func makeShared() -> NoteStore {
        let saved = UserDefaults.standard.string(forKey: folderKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
        return NoteStore(folder: saved ?? defaultFolder, stateURL: supportDirectory.appending(path: "fenster.json"))
    }

    // MARK: - Reading

    func note(_ id: String) -> Note? { notes.first { $0.id == id } }

    /// Most recently edited first.
    var byRecency: [Note] { notes.sorted { $0.modified > $1.modified } }

    private func markdownFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == "md" }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func load() {
        let states = readStates()
        diskText = [:]
        notes = markdownFiles().compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let id = url.lastPathComponent
            diskText[id] = text
            let (matter, body) = FrontMatter.split(text)
            return Note(id: id, body: body, frontMatter: matter, window: states[id] ?? WindowState(),
                        modified: Self.modificationDate(url))
        }
        .sorted { $0.id < $1.id }
    }

    /// Picks up files added, removed or edited outside the app.
    func refreshFromDisk() {
        let urls = markdownFiles()
        let onDisk = Set(urls.map(\.lastPathComponent))
        for note in notes where !onDisk.contains(note.id) && diskText[note.id] != nil && pendingWrites[note.id] == nil {
            notes.removeAll { $0.id == note.id }
            diskText[note.id] = nil
            onNoteRemoved?(note.id)
        }
        for url in urls {
            let id = url.lastPathComponent
            guard let text = try? String(contentsOf: url, encoding: .utf8), text != diskText[id] else { continue }
            guard pendingWrites[id] == nil else { continue }   // unsaved typing wins
            diskText[id] = text
            let (matter, body) = FrontMatter.split(text)
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].body = body
                notes[index].frontMatter = matter
                notes[index].modified = Self.modificationDate(url)
            } else {
                notes.append(Note(id: id, body: body, frontMatter: matter, window: WindowState(),
                                  modified: Self.modificationDate(url)))
            }
        }
    }

    // MARK: - Creating and editing

    /// A new, empty note. It reaches the disk with its first text; closed empty, it simply goes away.
    @discardableResult
    func createNote(color: NoteColor, frame: CGRect, body: String = "") -> Note {
        var matter = FrontMatter()
        let now = Date()
        matter["created"] = FrontMatter.string(from: now)
        matter["color"] = color.rawValue
        var window = WindowState()
        window.frame = frame
        window.isOpen = true
        let note = Note(id: uniqueFileName(for: now), body: body, frontMatter: matter, window: window, modified: now)
        notes.append(note)
        if !body.isEmpty { scheduleWrite(note.id) }
        scheduleStateSave()
        return note
    }

    private func uniqueFileName(for date: Date) -> String {
        let stamp = date.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            timeZone: .current, calendar: .current
        ))
        var name = "Notiz \(stamp).md"
        var counter = 2
        while note(name) != nil || FileManager.default.fileExists(atPath: folder.appending(path: name).path) {
            name = "Notiz \(stamp) \(counter).md"
            counter += 1
        }
        return name
    }

    func setBody(_ id: String, _ body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].body != body else { return }
        notes[index].body = body
        notes[index].modified = Date()
        scheduleWrite(id)
    }

    func setColor(_ id: String, _ color: NoteColor) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].frontMatter["color"] = color.rawValue
        if diskText[id] != nil || !notes[index].body.isEmpty { scheduleWrite(id) }
    }

    /// Changes the per-Mac window state (frame, pin, roll-up, …).
    func updateWindow(_ id: String, _ change: (inout WindowState) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var window = notes[index].window
        change(&window)
        guard window != notes[index].window else { return }
        notes[index].window = window
        scheduleStateSave()
    }

    /// Closes a note: an empty one is removed, any other is marked closed.
    func close(_ id: String) {
        guard let note = note(id) else { return }
        if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            delete(id)
        } else {
            updateWindow(id) { $0.isOpen = false }
        }
    }

    /// Moves the note's file to the Trash (recoverable) and forgets the note.
    func delete(_ id: String) {
        pendingWrites[id]?.cancel()
        pendingWrites[id] = nil
        let url = folder.appending(path: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        diskText[id] = nil
        notes.removeAll { $0.id == id }
        forgotten.insert(id)
        scheduleStateSave()
    }

    // MARK: - Writing

    private func scheduleWrite(_ id: String) {
        pendingWrites[id]?.cancel()
        pendingWrites[id] = Task { [weak self, writeDelay] in
            try? await Task.sleep(for: writeDelay)
            guard !Task.isCancelled else { return }
            self?.write(id)
        }
    }

    private func write(_ id: String) {
        pendingWrites[id] = nil
        guard let note = note(id) else { return }
        let text = note.fileText
        guard text != diskText[id] else { return }
        // A note that was never saved and is still blank stays off the disk.
        if diskText[id] == nil, note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        do {
            try text.write(to: folder.appending(path: id), atomically: true, encoding: .utf8)
            diskText[id] = text
        } catch {
            NSLog("[Haftnotiz] write \(id) failed: \(error)")
        }
    }

    private func readStates() -> [String: WindowState] {
        guard let data = try? Data(contentsOf: stateURL) else { return [:] }
        return (try? JSONDecoder().decode([String: WindowState].self, from: data)) ?? [:]
    }

    private func scheduleStateSave() {
        pendingStateSave?.cancel()
        pendingStateSave = Task { [weak self, writeDelay] in
            try? await Task.sleep(for: writeDelay)
            guard !Task.isCancelled else { return }
            self?.saveStates()
        }
    }

    private func saveStates() {
        pendingStateSave = nil
        // Keep the state of notes in other folders, so switching folders back and forth loses nothing.
        var states = readStates()
        for id in forgotten { states[id] = nil }
        forgotten.removeAll()
        for note in notes { states[note.id] = note.window }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(states) { try? data.write(to: stateURL, options: .atomic) }
    }

    /// Writes everything pending right now (quit, folder change).
    func flush() {
        for (id, task) in pendingWrites {
            task.cancel()
            write(id)
        }
        pendingWrites.removeAll()
        pendingStateSave?.cancel()
        saveStates()
    }

    // MARK: - Folder

    /// Switches to another notes folder and remembers it.
    func changeFolder(to url: URL) {
        flush()
        stopWatching()
        folder = url
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        load()
        startWatching()
    }

    /// Re-reads the folder whenever a file in it is added, removed or changed. FSEvents with file-level
    /// events, because editors like Obsidian rewrite a file in place, which a plain directory watch
    /// never reports.
    func startWatching() {
        stopWatching()
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let store = Unmanaged<NoteStore>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { store.refreshFromDisk() }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        watcher = stream
    }

    func stopWatching() {
        guard let watcher else { return }
        FSEventStreamStop(watcher)
        FSEventStreamInvalidate(watcher)
        FSEventStreamRelease(watcher)
        self.watcher = nil
    }
}
