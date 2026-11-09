# CLAUDE.md

Haftnotiz: minimal Markdown sticky notes for macOS. SwiftPM executable, SwiftUI views inside AppKit
`NSPanel`s, no dependencies, macOS 14, Swift 6. README, comments and commits in English, UI in German.
Fully offline: never add network access.

## Commands

```sh
swift build && swift test
./build.sh [--install|--zip]     # release app in build/, Developer ID signed
```

## Architecture

- `Model/NoteStore` (`@MainActor @Observable`): one `.md` file per note in the notes folder
  (`UserDefaults notesFolder`, default `~/Vault/Wiredframe/Notizen/Haftnotiz`). Debounced atomic
  writes; `diskText` tells own writes from outside edits; the folder is watched with FSEvents
  file-level events (a directory watch misses in-place rewrites, which is how Obsidian saves) and
  re-read when a note becomes key; a note with a pending write is never overwritten from disk. A new note
  reaches disk only with text; closed empty, it goes away. Delete = move to Trash. File names are
  stable (`Notiz <date> <time>.md`), never renamed.
- `Note`: `body` (what the editor shows) + `FrontMatter` (hidden YAML, every line kept verbatim; the
  app only reads and writes top-level `created` and `color`) + `WindowState` (frame, material, pinned, all Spaces, collapsed, open), stored per Mac in
  `~/Library/Application Support/Haftnotiz/fenster.json`.
- `Editor/`: `MarkdownSyntax` (pure, line-local spans) and `ListEditing` (pure: Return/Tab/⇧⌘L on
  list lines) are unit-tested. `MarkdownStyler` maps spans to attributes (syntax stays visible,
  dimmed) and restyles the edited paragraphs from the text storage delegate. Checkbox characters
  are made invisible and `CheckboxLayoutManager` draws SF Symbol circles over them;
  `MarkdownTextView` toggles them on click (undoable, first click works on an inactive note). It
  also handles ⌥↑/⌥↓ (`ListEditing.movingLines`) and the standard editing shortcuts itself, because
  the app has no Edit menu of its own. TextKit 1 on purpose (custom layout manager).
- `Windows/`: `NotePanel` and `NoteWindowManager` come from Tic (MIT): header-only drag
  (`WindowMoveArea`), multi-display placement that never saves macOS's own moves, roll-up keeping the
  top edge.
- `Views/NoteView`: slim header (controls on hover; the pin stays visible on pinned notes) + editor.
