# Sidebar, project dropdown, and Documents — design

Status: implemented. Builds on
`2026-09-23-brd-board-viewer-design.md` (the Tree view described there has
since been removed).

## Problem

The panel opens on a project list, and picking a project leads to the Board.
There is no room to grow: a second kind of content (a project's documents) has
nowhere to live, and switching projects means going back to the list. This adds
a left **sidebar** with a project dropdown and two sections, **Board** and
**Documents**, and makes the panel remember which project you were on.

## Non-goals

- Editing documents or cards. Documents are read-only. The only write the
  plugin performs remains removing a project (`brd forget`) behind the
  type-to-confirm and mandatory snapshot from the delete design.
- Documents outside the selected project (no global doc browser), non-Markdown
  files, or full-text search across documents.
- A rewrite of existing code. Board, card detail, live refresh and delete stay
  in `Panel.qml`; only new pieces get their own files.

## Decisions (from the design conversation)

- Documents = every `.md` under the selected project's `docs/`. Each has one
  category (Architecture, Specs, Standards, Audits, Other): a `tag:` line in the
  file's YAML frontmatter wins, else the folder default (`docs/architecture`,
  `docs/specs` + `docs/superpowers/specs`, `docs/standards`, `docs/audits`),
  else Other. Category badges filter the list (one at a time, click again to
  clear, counts shown, combined with the search box). Revised twice: first
  root `README.md` + `docs/**`, then four fixed folders.
- On open, the panel shows the last project you viewed, remembered across
  restarts; if it is gone or none is stored, the first registered project.
- The per-row trash button and the Delete key on the project list are removed
  with the list. Deleting a project is a **Delete project…** button in the
  sidebar footer, feeding the existing confirm flow unchanged.
- Approach: hybrid. New files `Sidebar.qml` and `DocumentsView.qml` with
  explicit properties and signals; everything else stays in `Panel.qml`.
- Two phases. **A**: sidebar, dropdown, persistence, delete relocation (usable
  alone). **B**: Documents.

## Layout and navigation

The panel is a fixed-width sidebar (200 logical px) on the left and a content
area on the right. Total width becomes 840 (`Style.space(840)`, still capped to
the screen by `fittedContentWidth`); height cap 620.

```
┌──────────────┬─────────────────────────────────────┐
│ [ proj  ▾ ]  │  header: title · ⟳ · search         │
│              │                                     │
│  ▸ Board     │   content of the current section    │
│    Documents │   (Board / card / doc list / doc)   │
│              │                                     │
│ [Delete proj]│                                     │
└──────────────┴─────────────────────────────────────┘
```

`viewMode` becomes one of `"board" | "entry" | "documents" | "document"`. The
old `"projects"` mode and the first-screen project list are removed. The sidebar
highlights **Board** for `board`/`entry` and **Documents** for
`documents`/`document`. Choosing a section resets to that section's list view.

Back behaviour is unchanged: from a card or a document, Back / Escape / Left
returns to its list with the highlight and scroll position restored. From a
section's list, Escape closes the panel. With no projects registered the content
area shows "No projects registered with brd."; the Board and Documents rows and
the Delete button are disabled, while the project dropdown stays enabled and
shows "No projects registered."

Keyboard, in addition to the existing per-view keys: **Ctrl+P** toggles the
project dropdown, **Ctrl+1** shows Board, **Ctrl+2** shows Documents. The mouse
reaches every control.

## Project dropdown

A button showing the current project name and a chevron. Clicking it (or
Ctrl+P) opens a list overlaid on the sidebar, with a filter field on top and one
row per project (same matching as today's project search). Up/Down move the
highlight, Enter or click selects, Escape closes without changing anything. On
selection: close the dropdown, set `selectedProject`, run the existing
fetch/resolve-db-path flow, persist the choice, reset to the Board section list.

## Persistence: `viewer-state.py`

QML cannot write files, so a small Python helper owns a state file at
`${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json`:

- `viewer-state.py get` prints one JSON line: `{"last_project": "<root_path>"}`
  or `{"last_project": null}`. A missing, empty or corrupt file yields `null`;
  it never raises.
- `viewer-state.py set-project <root_path>` stores the path atomically (write a
  temp file in the same directory, then rename), creating the directory if
  needed, and prints `{"ok": true}`. Any other content already in the file is
  preserved.
- Exit code 0 on success; non-zero with `{"ok": false, "error": "..."}` on
  failure. A failure to persist is not shown to the user and never blocks
  navigation.

The first time the panel opens after the shell loads it needs both
`brd projects` and `viewer-state.py get`, and selects the stored project if it
appears in the project list, else the first. Each later open re-runs
`brd projects` and keeps the current project if it is still registered (else
falls back the same way), so state survives close and reopen without rereading
the state file.
`stateReadOk` gates persistence: it is true only when `viewer-state.py get`
succeeded, so a failed state read never overwrites the stored project.
Deleting the current project selects the first remaining project (or shows the
empty state) and persists that.

A 2 s watchdog makes this fail soft: if `viewer-state.py get` has not answered
by then (python3 missing, spawn failure), it is treated as a failed read, so the
first project is selected and nothing stored is overwritten. A reply arriving
after the state was already settled is ignored, so it cannot move the selection.

## Documents (phase B)

### `list-docs.py <root_path>`

Prints one JSON line: `{"ok": true, "docs": [...], "truncated": false}` or
`{"ok": false, "error": "..."}`. Each doc is `{"path", "title", "size", "category"}` (`category` is
`architecture`, `specs`, `standards`, `audits` or `other`):

- `path` is relative to the project root with forward slashes (`README.md`,
  `docs/specs/x.md`). The panel builds the absolute path as
  `root_path + "/" + path`.
- Candidates: every `*.md` (case-insensitive extension) found recursively under
  `docs/`. Hidden directories are skipped. `category` is the frontmatter `tag:`
  (`architecture`, `spec(s)`, `standard(s)`, `audit(s)`; case-insensitive, quotes
  and trailing `# comments` ignored; only a leading, closed `---` block counts;
  unknown values are ignored) else the folder default else `other`; the title
  scan skips the frontmatter.
- **Path safety:** only regular files whose resolved path lies inside the
  resolved project root are listed; symlinks (files or directories) that escape
  the root are skipped, as are unreadable entries.
- `title` is the text of the first line beginning `# ` within the first 64 KB,
  else the file name without extension.
- Order: grouped Architecture, Specs, Standards, Audits, Other; within a group, paths sorted
  case-insensitively.
- Cap: at most 500 entries; `truncated` is `true` if more existed.
- A missing project directory or no matches returns `{"ok": true, "docs": []}`.

### `DocumentsView.qml`

Properties: `docs` (list from the helper), `query`, `cursorIndex`, `loading`,
`error`; signals: `docChosen(path)`, `hovered(index)`. Renders the filtered list
(title, dim path), with the same highlight, hover and auto-scroll behaviour as
the Board. Filtering by title/path uses the content header's search field.

Every `fetchDocs()` launch creates its own `Process` (from a `Component`), with
its own stdout collector and immutable `forRoot` (the project at launch) and
`seq` (a monotonic `docsSeq`). On exit it applies its result only if `seq` is
still the latest and `forRoot` is still the selected project, then destroys
itself either way. A newer fetch stops the previous instance, so a stale exit
arriving at any time, even after the newer run finished, can neither apply
another project's data or error nor wipe a good list.

### Viewing a document

Opening a doc sets `viewMode: "document"` and points a `FileView` at the absolute
path with `watchChanges: true` (live reload), rendered with
`Text.MarkdownText` like card descriptions. Documents larger than 1 MB show
"This document is too large to display." A document with no links to follow
scrolls with Up/Down. Read failures show an inline error with Back available.

## Sidebar component: `Sidebar.qml`

Explicit interface, no access to `Panel.qml` ids:

- Properties: `projects`, `selectedProject`, `section` (`"board"|"documents"`),
  `dropdownOpen`, `dropdownQuery`, `dropdownCursor`, `canDelete`, `foreground`,
  `dim`, `urgent`, `fontFamily`.
- Signals: `dropdownToggled()`, `projectChosen(var project)`,
  `queryEdited(string text)`, `sectionChosen(string section)`,
  `deleteRequested()`, `cursorHovered(int index)`, and, added while designing
  the component, `dropdownMove(int delta)`, `dropdownAccept()`,
  `dropdownCancel()`, `filterKey(var event)`.
- Also: property `documentsEnabled`, and the read-only property `filterItem`
  (the dropdown's filter field).
- `Panel.qml`'s `focusItem` is the single source of which item holds focus
  (confirm field, dropdown filter, key catcher or search field).

`Panel.qml` keeps all state (selection, cursor, delete flow) and passes it down;
the sidebar only renders and emits.

## Delete flow

Unchanged (`openDelete`, `performDelete`, `snapshot-and-forget.py`, the
type-to-confirm text and result parsing). The sidebar's **Delete project…**
button calls `openDelete(selectedProject)`; the confirmation replaces the
content area as it replaced the list before. The per-row trash button, the
Delete key handler and `ProjectRow` are removed.

## Error handling

- `brd projects` fails or `brd` is missing: the existing error text in the
  content area; the dropdown shows no rows.
- `viewer-state.py get` fails: treated as `null` (first project).
- `list-docs.py` fails or times out: the Documents list shows the error text;
  the Board is unaffected.
- A stored project no longer registered: silently the first project.

## Testing

- `logic.js` (unit-tested in `tests/qml/tst_logic.qml`): document title/path
  filtering, choosing the initial project from a project list and a stored path,
  and parsing the helpers' JSON results.
- `tests/test_viewer_state.py`: missing/corrupt/empty file, set then get,
  atomic replace, preserving unrelated keys, unwritable directory.
- `tests/test_list_docs.py`: README first, nested docs, title extraction,
  ordering, hidden dirs, non-Markdown ignored, symlink escaping the root skipped,
  cap and `truncated`, missing directory.
- The stub-panel harness flow tests are re-run for navigation: section switching,
  dropdown selection persisting, back-restores-position, delete from the sidebar.
- Manual live checks after `omarchy-restart-shell`: sidebar layout at 840, dropdown
  keyboard behaviour, Ctrl+P / Ctrl+1 / Ctrl+2 not being swallowed by the
  compositor, document rendering.

## Files

New: `Sidebar.qml`, `DocumentsView.qml` (phase B), `viewer-state.py`,
`list-docs.py` (phase B), `tests/test_viewer_state.py`,
`tests/test_list_docs.py` (phase B). Modified: `Panel.qml`, `logic.js`,
`tests/qml/tst_logic.qml`, `README.md`, `manifest.json` description.
