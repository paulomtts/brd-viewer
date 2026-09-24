# Core / UI architecture — design

Status: proposed. Behaviour-preserving restructure; no user-visible change.

## Problem

The plugin grew feature by feature into a flat folder. `Panel.qml` is about
1,800 lines and is at once the shell, the state store for every feature
(navigation, projects, board, documents, memories, delete flows), the
orchestrator of every helper script, and the layout. The view components are
already presentation-only, but nothing enforces or even shows where the line is:
rules live in one `logic.js`, helpers sit beside QML files, and tests can only
reach state through a fake `Panel`.

## Goal

A clear separation between **presentation** (`ui/`) and **core** (`core/`), a
folder structure that shows it, and a rule the test suite enforces:

> `ui/` may use `core/`. `core/` never imports anything visual.

## Non-goals

- No new features and no behaviour change; every existing test keeps its
  meaning (some move to a lower layer).
- No change to the helper scripts' JSON contracts, the plugin id, or the
  user-facing names, data folders and shortcuts.
- No per-screen view-model layer (too heavy for this size).

## Layout

```
manifest.json                 entryPoints.barWidget -> ui/Panel.qml
install.sh, README.md, LICENSE, run-tests.sh, pytest.ini
core/
├── domain/                   pure JavaScript (.pragma library), no QML imports
│   ├── projects.js           project list filtering, initial selection, state/delete parsing
│   ├── board.js              card index, progress, status order, detail links
│   ├── graph.js              milestone graph model, keyboard movement (uses vendor layout)
│   ├── documents.js          doc filtering, frontmatter, listing parser
│   ├── memories.js           file naming, note composing, parsers
│   ├── taxonomy.js           shared: a set of typed labels with colours, counts and filtering
│   └── results.js            shared: the "one JSON line + exit code" parsing
├── backend/                  Python helpers, each prints one JSON line
│   ├── common/               shared: json_line, safe_paths, atomic_write, frontmatter
│   ├── projects/             resolve-db-path.py, viewer-state.py, snapshot-and-forget.py
│   ├── documents/            list-docs.py, set-doc-tag.py
│   └── memories/             list-memories.py, memory-op.py, memory_lib.py
└── stores/                   non-visual QML objects: state + workflows
    ├── App.qml               composes the stores below and wires them together
    ├── HelperRunner.qml      shared: run a helper script, latest-run-wins, stale guard, parsed result
    ├── FilterState.qml       shared: one active filter value with toggle and cursor reset
    ├── NavigationStore.qml   view mode, section, back/return positions, cursor, search, dropdown
    ├── ProjectStore.qml      registry, selection, remembered project, DB watch path
    ├── ProjectDeleteStore.qml   delete-project confirm/snapshot flow
    ├── BoardStore.qml        cards, index, card selection, board order; owns the DB FileView
    ├── GraphStore.qml        graph model from BoardStore, graph cursor and movement
    ├── DocumentsStore.qml    listing, category filter, open document, type tagging
    └── MemoriesStore.qml     listing, type filter, open/edit/create/delete a note
ui/
├── Panel.qml                 entry point: creates App, hosts the bar icon and KeyboardPanel
├── Shortcuts.qml             key events -> store calls (Ctrl+P/1..4/N/E, Escape order)
├── screens/                  Board, CardDetail, Graph, Documents, Document, Memories, MemoryNote
├── components/               shared building blocks (see below) and the composed widgets
│                             Sidebar, TagPicker, dialogs, note view
└── theme/                    colours/fonts resolved from the shell (foreground, dim, urgent, font)
vendor/
└── canvas/                   vendored canvas plugin: QML for ui/, pure layout.js/camera.js/positions.js for core
docs/
tests/
├── stubs/                    stub shell types (qs.Ui, qs.Commons, Quickshell, Quickshell.Io)
├── helpers/                  shared test helpers: find(), make-panel, run-helper, write-tree
├── core/{domain,backend,stores}/   headless: no Quickshell UI stubs beyond Io
├── ui/                       component and Panel-wiring tests
├── architecture/             layer-rule and name-clash tests
└── run.sh                    replaces run-tests.sh + tests/panel/run.sh
```

## The dependency rule

| layer | may import | must not import |
|---|---|---|
| `core/domain` | other `core/domain` files, `vendor/canvas/*.js` (pure JS only) | any QML, `Qt*`, `Quickshell*`, `qs.*` |
| `core/backend` | Python stdlib, sibling helpers | anything in QML |
| `core/stores` | `core/domain`, `Quickshell.Io` (Process, FileView), `QtQml`, `Quickshell` `Scope` | `QtQuick`, `QtQuick.*`, `qs.Ui`, `qs.Commons`, `ui/`, `vendor/canvas/*.qml` |
| `ui/` | everything in `core/`, `qs.Ui`, `qs.Commons`, `QtQuick*`, `vendor/canvas` | (no restriction) |

`tests/architecture/test_layers.py` reads the imports of every file and fails on
a violation. It also fails when a `ui/` or `core/` QML file has the same base
name as a type in the shell's `qs.Ui` (a clash makes the shell load its own type
instead of ours, which is what broke `ConfirmDialog`), using a maintained list
of those names.

## How the pieces talk

- `ui/Panel.qml` creates one `App` and passes it (`property var app`) to
  screens and components. There is no other shared state.
- A store exposes **properties** (state), **derived read-only properties**
  (filtered lists, counts) and **functions** (commands such as `open(file)`,
  `save()`, `toggleType(id)`). It talks to the Python helpers through
  `Process` and to files through `FileView`, and reports results by changing
  properties. It never touches an `Item`, a colour or a focus.
- Cross-store needs are explicit properties set in `App.qml`
  (`docs.project: projects.selected`); a store reacts to `onProjectChanged`.
  Stores do not import each other.
- Views bind to store properties and call store functions (or emit a signal the
  screen forwards). Pure presentation state stays in `ui/`: `focusItem`,
  scroll position and reveal-into-view, hover/keyboard-cursor timing,
  theme colours.
- Paths to helper scripts are built from one `backendDir` property that
  `App` receives from `ui/Panel.qml` (`pluginDir + "core/backend/"`).

## Shared abstractions: no second copy

Rule: **when the same thing is needed in a second place, it becomes a shared
abstraction before the second use is written.** A review checklist item and a
small architecture test (below) back it. What the code duplicates today, and
what replaces it:

| Duplicated today | Where | Becomes |
|---|---|---|
| Coloured pill/badge | DocumentsView, MemoriesView, MemoryNoteView rows and headers | `ui/components/Badge.qml` (text, tint) |
| Filter/choice chip with count and active state | DocumentsView `CategoryChip`, MemoriesView `TypeChip`, TagPicker, NewMemoryDialog | `ui/components/Chip.qml` plus `ChipRow.qml` (Flow of chips over a model) |
| Modal card over a dimmed backdrop, click-outside to cancel | delete-project modal in Panel, TypedConfirmDialog, NewMemoryDialog | `ui/components/ModalCard.qml`; the delete-project modal reuses `TypedConfirmDialog` instead of its own copy |
| Bordered action button with the same six style properties | note view, dialogs, Panel (10+ uses) | `ui/components/ActionButton.qml` (label, tone: normal or danger) |
| List row with hover, keyboard cursor and reveal-into-view | DocumentsView `DocRow`, MemoriesView `NoteRow`, board cards, detail links | `ui/components/ListRow.qml` |
| Loading / error / empty message with the same precedence | DocumentsView, MemoriesView | `ui/components/ListStatus.qml` |
| Chips + status + rows list with type filter | DocumentsView, MemoriesView | `ui/components/FilterableList.qml` (row delegate supplied by the screen) |
| Bordered multi-line text box | MemoryNoteView editor, NewMemoryDialog body | `ui/components/TextAreaBox.qml` |
| Text with the theme colour, font and size variants | everywhere | `ui/components/ThemedText.qml` (variant: body, caption, heading, dim) |
| "Run a helper, ignore stale results, parse one JSON line" (per-run processes with a sequence number and project guard, single-run ops with a busy flag) | docs list, memories list, memory ops, tag op, delete, board tree, state | `core/stores/HelperRunner.qml` used by every store |
| "One active filter, toggle it, reset the cursor" | `toggleDocCategory`, `toggleMemoryType` | `core/stores/FilterState.qml` |
| Return-to-list bookkeeping (return cursor, scroll, mode) | `openCard`, `openDoc`, `openMemory` and their restores | one `push/pop` on `NavigationStore` |
| Label, colour, counts and filter for a fixed set of types | `docCategory*`, `memoryType*` in `logic.js` | `core/domain/taxonomy.js` (one factory; documents and memories each declare their items) |
| Six near-identical result parsers | `parseDocsResult`, `parseStateResult`, `parseDeleteResult`, `parseTagResult`, `parseMemoriesResult`, `parseMemoryOpResult` | `core/domain/results.js` (`parseJsonLine` with a generic message and a payload mapper) |
| `emit`, `inside`, atomic write, frontmatter split, real-path containment | six Python helpers, three copies of atomic write, two of frontmatter parsing | `core/backend/common/` (`json_line.py`, `safe_paths.py`, `atomic_write.py`, `frontmatter.py`) |
| `find()` / `make()` / `run()` / `write()` test helpers | 14 QML tests, 8 Python test files | `tests/helpers/` |

`ui/components` are created **before** the screens that use them (migration
step 5), and every one has a small test. `core/backend/common` is created in
step 2 and the helpers are ported onto it in the same commits that move them.
The Python helpers import it by inserting their own directory's parent on
`sys.path`, the pattern `memory_lib` already uses.

The architecture test also fails if a known-duplicated name (`emit`,
`inside`, `write_atomic`, `split_frontmatter`, `find`) is defined twice in
non-test code, so the duplication cannot silently come back.

## Migration

Behaviour stays green at every step; each step is its own commit.

1. **Tests and harness first:** one `tests/run.sh`, stubs moved to `tests/stubs`,
   directories mirrored; add the (initially permissive) architecture test.
2. **Backend:** create `core/backend/common/`, then move each helper into
   `core/backend/<domain>/` and port it onto the shared modules in the same
   commit; update script paths in `Panel.qml`, `install.sh`, tests and docs.
3. **Domain:** split `logic.js` into `core/domain/*.js`, introducing
   `results.js` and `taxonomy.js` and porting the parsers and the two type sets
   onto them; move `canvas/` to `vendor/canvas/`; `graph.js` imports the
   vendored `layout.js`.
4. **Stores:** first `HelperRunner` and `FilterState` (with tests), then one
   domain per commit: Navigation, ProjectStore +
   ProjectDeleteStore, BoardStore + GraphStore, DocumentsStore, MemoriesStore.
   For each: create the store, move the state and workflows out of `Panel.qml`,
   move the matching `Panel`-level flow tests to `tests/core/stores`.
5. **UI:** first the shared components (`Badge`, `Chip`, `ChipRow`, `ModalCard`,
   `ActionButton`, `ListRow`, `ListStatus`, `FilterableList`, `TextAreaBox`,
   `ThemedText`), each replacing its duplicates; then slim `Panel.qml` to the
   shell, extract `Shortcuts.qml` and the screens; flip the manifest entry point to `ui/Panel.qml` (the plugin symlink
   links the whole folder, so it needs no change).
6. **Enforce and document:** turn the architecture test to strict, rewrite the
   README "Layout" section, and record the rule in a short `docs/architecture.md`.

## Risks and how they are handled

- **QML directory imports.** Files in other folders need qualified imports
  (`import "../components" as C`); a mistake only shows at load time. The
  harness compiles the real files with the same folder structure, so it catches
  them, and the final check is a live load in the shell.
- **Non-visual container type.** Stores that own `Process`/`FileView` children
  need a container that accepts children; the plan starts with a one-file spike
  to confirm Quickshell's `Scope` (or `QtObject` with property-declared
  children) works in both the harness and the real shell before any store is
  moved. If neither works, stores create their `Process`/`FileView` children with
  `Component.createObject` (already used for per-run processes), and this spec
  is updated. Spike outcome: a `Scope` root owning `Process` and `StdioCollector` children works in both the harness and the real shell (journal after `tests/live-check.sh` showed `qml: SPIKE store out=ok` from a `Scope` store instantiated in `Panel.qml`, with no plugin-load errors), so stores use `Scope`.
- **The shell caches components.** Every step ends with a shell restart and a
  clean-log check, as before.
- **Big diff, small commits.** Steps 2–3 are mechanical moves; steps 4–5 move
  code without changing it, so review is "did it move intact".

## Testing

- Every existing test keeps passing or moves with the code it tests.
- Store tests need no UI stubs: they drive `Process`/`FileView` stubs and
  assert on properties.
- `tests/architecture` enforces the dependency rule, the name-clash list and
  the no-duplicate-helper check.
- A live smoke check after step 5: open the panel, visit every section, edit a
  memory note, tag a document, and confirm the shell log shows no plugin errors.

## Done when

- `ui/Panel.qml` is under about 400 lines and holds no feature state.
- Every store is exercised by a headless test.
- None of the duplications in the table above remains (checked by grep and the
  architecture test).
- The layer test passes in strict mode.
- All previous behaviour tests pass; the live smoke check is clean.
