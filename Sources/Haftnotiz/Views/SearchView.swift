import SwiftUI

/// The floating search palette (after Tic's): search all notes by their text, ↑↓ to move, ↩ to open.
struct SearchView: View {
    @State private var model = AppModel.shared
    @State private var query = ""
    @State private var selectedID: String?
    @State private var scrollRequest: String?
    @State private var pointerAtKeyMove: NSPoint?
    @FocusState private var searchFocused: Bool

    private var results: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let notes = model.store.byRecency.filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !q.isEmpty else { return notes }
        return notes.filter { $0.body.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            list
        }
        .frame(width: 620, height: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        .ignoresSafeArea()
        .task {
            searchFocused = true
            selectedID = results.first?.id
        }
        .onChange(of: query) { _, _ in selectedID = results.first?.id }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onExitCommand { model.dismissSearch() }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(.secondary)
            TextField("Notizen durchsuchen …", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($searchFocused)
                .onSubmit { openSelected() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if results.isEmpty {
                        Text(query.isEmpty ? "Noch keine Notizen" : "Nichts gefunden")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                    ForEach(results) { note in
                        SearchRow(note: note, query: query, selected: note.id == selectedID)
                            .id(note.id)
                            .onHover { if $0, NSEvent.mouseLocation != pointerAtKeyMove { selectedID = note.id } }
                            .onTapGesture { selectedID = note.id; openSelected() }
                    }
                }
                .padding(8)
            }
            .onChange(of: scrollRequest) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                scrollRequest = nil
            }
        }
    }

    private func move(_ delta: Int) {
        let ids = results.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selectedID.flatMap { ids.firstIndex(of: $0) } ?? -1
        let next = min(max(current + delta, 0), ids.count - 1)
        selectedID = ids[next]
        scrollRequest = ids[next]
        pointerAtKeyMove = NSEvent.mouseLocation
    }

    private func openSelected() {
        guard let id = selectedID else { return }
        model.open(id)
        model.dismissSearch()
    }
}

private struct SearchRow: View {
    let note: Note
    let query: String
    let selected: Bool

    /// The line containing the match (or the second line), shown under the title.
    private var snippet: String {
        let lines = note.body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let q = query.trimmingCharacters(in: .whitespaces)
        let plain = lines.map { Note.title(of: $0) }.filter { !$0.isEmpty }
        if !q.isEmpty, let hit = plain.dropFirst().first(where: { $0.localizedCaseInsensitiveContains(q) }) {
            return hit
        }
        return plain.dropFirst().first ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(note.color.fill)
                .frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.15)))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).lineLimit(1)
                if !snippet.isEmpty {
                    Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(note.modified, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
