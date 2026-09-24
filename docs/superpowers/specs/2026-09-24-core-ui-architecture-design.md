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
│   ├── documents.js          doc filtering, categories, frontmatter, listing parser
│   ├── memories.js           types, filtering, file naming, note composing, parsers
│   └── results.js            the shared "one JSON line + exit code" parsing
├── backend/                  Python helpers, each prints one JSON line
│   ├── projects/             resolve-db-path.py, viewer-state.py, snapshot-and-forget.py
│   ├── documents/            list-docs.py, set-doc-tag.py
│   └── memories/             list-memories.py, memory-op.py, memory_lib.py
└── stores/                   non-visual QML objects: state + workflows
    ├── App.qml               composes the stores below and wires them together
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
├── components/               Sidebar, chips, TagPicker, dialogs, badges, rows
└── theme/                    colours/fonts resolved from the shell (foreground, dim, urgent, font)
vendor/
└── canvas/                   vendored canvas plugin: QML for ui/, pure layout.js/camera.js/positions.js for core
docs/
tests/
├── stubs/                    stub shell types (qs.Ui, qs.Commons, Quickshell, Quickshell.Io)
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

## Migration

Behaviour stays green at every step; each step is its own commit.

1. **Tests and harness first:** one `tests/run.sh`, stubs moved to `tests/stubs`,
   directories mirrored; add the (initially permissive) architecture test.
2. **Backend:** move helpers into `core/backend/<domain>/`; update script paths
   in `Panel.qml`, `install.sh`, tests and docs.
3. **Domain:** split `logic.js` into `core/domain/*.js`; move `canvas/` to
   `vendor/canvas/`; `graph.js` imports the vendored `layout.js`.
4. **Stores, one domain per commit:** Navigation, ProjectStore +
   ProjectDeleteStore, BoardStore + GraphStore, DocumentsStore, MemoriesStore.
   For each: create the store, move the state and workflows out of `Panel.qml`,
   move the matching `Panel`-level flow tests to `tests/core/stores`.
5. **UI:** slim `Panel.qml` to the shell, extract `Shortcuts.qml` and the
   screens, move components; flip the manifest entry point to `ui/Panel.qml` (the plugin symlink
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
  is updated.
- **The shell caches components.** Every step ends with a shell restart and a
  clean-log check, as before.
- **Big diff, small commits.** Steps 2–3 are mechanical moves; steps 4–5 move
  code without changing it, so review is "did it move intact".

## Testing

- Every existing test keeps passing or moves with the code it tests.
- Store tests need no UI stubs: they drive `Process`/`FileView` stubs and
  assert on properties.
- `tests/architecture` enforces the dependency rule and the name-clash list.
- A live smoke check after step 5: open the panel, visit every section, edit a
  memory note, tag a document, and confirm the shell log shows no plugin errors.

## Done when

- `ui/Panel.qml` is under about 400 lines and holds no feature state.
- Every store is exercised by a headless test.
- The layer test passes in strict mode.
- All previous behaviour tests pass; the live smoke check is clean.
