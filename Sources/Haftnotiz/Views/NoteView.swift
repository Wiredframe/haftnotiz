import AppKit
import SwiftUI

/// A sticky note: a slim header that is the drag handle (its controls appear on hover) and below it
/// the writing surface. Rolled up, only the header with the note's first line remains.
struct NoteView: View {
    let store: NoteStore
    let id: String
    let actions: NoteActions
    let focusOnAppear: Bool

    @State private var hovering = false
    @State private var showColors = false

    var body: some View {
        if let note = store.note(id) {
            let theme = NoteTheme(color: note.color, material: note.window.material)
            VStack(spacing: 0) {
                header(note, theme)
                if !note.window.isCollapsed {
                    NoteEditor(text: note.body, theme: theme, focusOnAppear: focusOnAppear) { store.setBody(id, $0) }
                        .overlay(alignment: .topLeading) {
                            if note.body.isEmpty {
                                Text("Schreib los …")
                                    .font(.system(size: MarkdownStyler.fontSize))
                                    .foregroundStyle(theme.secondary.opacity(0.8))
                                    .padding(.leading, NoteEditor.inset.width)
                                    .padding(.top, NoteEditor.inset.height + 2)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(NoteBackground(color: note.color, material: note.window.material))
            .ignoresSafeArea()
            .onHover { inside in withAnimation(.easeInOut(duration: 0.15)) { hovering = inside } }
        }
    }

    // MARK: - Header

    private func header(_ note: Note, _ theme: NoteTheme) -> some View {
        HStack(spacing: 8) {
            if note.window.isCollapsed {
                Text(note.title.isEmpty ? "Leere Notiz" : note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            if hovering || note.window.isCollapsed { leftControls(note, theme).opacity(hovering ? 1 : 0) }
            Spacer(minLength: 0)
            rightControls(note, theme)
        }
        .padding(.horizontal, 10)
        .frame(height: NoteWindowManager.collapsedHeight - 8)
        .padding(.top, 4)
        .padding(.bottom, note.window.isCollapsed ? 4 : 0)
        .frame(maxWidth: .infinity)
        // The header is the drag handle; a double-click rolls the note up or down.
        .background(WindowMoveArea { actions.toggleCollapsed() })
    }

    @ViewBuilder
    private func leftControls(_ note: Note, _ theme: NoteTheme) -> some View {
        HStack(spacing: 6) {
            iconButton("plus", theme, help: "Neue Notiz", action: actions.newNote)
            Button { showColors.toggle() } label: {
                Circle()
                    .fill(note.color.fill)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(theme.secondary.opacity(0.5), lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Farbe")
            .popover(isPresented: $showColors, arrowEdge: .bottom) { colorPicker(note) }
        }
    }

    private func rightControls(_ note: Note, _ theme: NoteTheme) -> some View {
        HStack(spacing: 2) {
            if hovering {
                iconButton(note.window.isCollapsed ? "chevron.down" : "chevron.up", theme,
                           help: note.window.isCollapsed ? "Aufklappen" : "Zuklappen", action: actions.toggleCollapsed)
                moreMenu(note, theme)
            }
            // The pin stays visible on a pinned note, so you can tell which ones float.
            if hovering || note.window.pinned {
                iconButton(note.window.pinned ? "pin.fill" : "pin", theme, active: note.window.pinned,
                           help: note.window.pinned ? "Nicht mehr im Vordergrund halten" : "Im Vordergrund halten",
                           action: actions.togglePinned)
            }
            if hovering {
                iconButton("xmark", theme, help: "Schließen", action: actions.close)
            }
        }
    }

    private func moreMenu(_ note: Note, _ theme: NoteTheme) -> some View {
        Menu {
            Toggle("Glas", isOn: Binding(
                get: { note.window.material == .glass },
                set: { glass in store.updateWindow(id) { $0.material = glass ? .glass : .solid } }
            ))
            Toggle("Auf allen Schreibtischen", isOn: Binding(
                get: { note.window.showOnAllSpaces }, set: { _ in actions.toggleAllSpaces() }
            ))
            Divider()
            Button("Im Finder zeigen") {
                let url = store.folder.appending(path: id)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.open(store.folder)
                }
            }
            Divider()
            Button("In den Papierkorb legen", role: .destructive, action: actions.delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Mehr")
    }

    private func colorPicker(_ note: Note) -> some View {
        HStack(spacing: 8) {
            ForEach(NoteColor.allCases) { swatch in
                Button {
                    store.setColor(id, swatch)
                    showColors = false
                } label: {
                    Circle()
                        .fill(swatch.fill)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(
                            swatch == note.color ? swatch.accent : Color.black.opacity(0.12),
                            lineWidth: swatch == note.color ? 2.5 : 1
                        ))
                }
                .buttonStyle(.plain)
                .help(swatch.displayName)
            }
        }
        .padding(10)
    }

    private func iconButton(
        _ symbol: String, _ theme: NoteTheme, active: Bool = false, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? theme.accent : theme.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
