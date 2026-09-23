# brd board viewer — design

Status: approved, not yet implemented.

## Problem

[`brd`](https://github.com/paulomtts/brd) is a local, no-visual-UI kanban
CLI: cards live in per-project SQLite files, keyed by absolute project
path, with a global registry (`~/.local/share/brd/master.db`) listing every
registered project. There's no way to see the shape of a board — its
columns, its hierarchy, which cards are blocked — without hand-composing
`brd list`/`brd tree` calls and reading raw JSON. This adds an
[Omarchy](https://omarchy.org/) bar-widget plugin, `paulomtts.brd-board`,
that gives every registered project a Board view (kanban columns) and a
Tree view (hierarchy + dependencies), one bar icon and one panel, following
the same shape as the existing `paulomtts.claude-memory` plugin.

## Non-goals

- **No writes.** Nothing in this plugin calls `brd add`/`update`/`delete`/
  `block`. Purely a viewer; card status changes still happen via the CLI
  or an agent.
- **No direct SQLite access.** All data comes from `brd`'s own JSON output
  (`brd projects`, `brd tree`). A helper script computes a project's DB
  *path* (to watch for changes) but never reads it — see Live refresh.
- **No project registration UI.** `brd init`/`forget` stay CLI-only; the
  plugin only lists what's already registered.
- **No card creation/editing/manage-mode-style deletion**, unlike the
  memory plugin's manage mode. Out of scope for v1.

## Data flow

Three `brd` CLI calls cover everything:

- `brd projects` — run with no particular `cwd` requirement (it reads the
  global registry) → `{root_path, name, created_at}[]`.
- `brd tree` — must run with the subprocess's **working directory** set to
  the selected project's `root_path`, since `brd` resolves "which project"
  purely from `cwd` (no `--project` flag exists). Returns the full nested
  card tree: `{id, title, description, status, blocked_by[], created_at,
  updated_at, children[]}[]`, recursively.

One `brd tree` fetch per project selection serves **both** Board and Tree
view — switching between them is a pure client-side re-render of the same
JSON, not a refetch. A `Map<id, card>` is built client-side by walking the
tree once (needed to resolve `blocked_by` ids to titles/status in the
detail view, and to compute each root card's descendant done/total counts
for the Board view's progress badge).

If `brd` is not on `PATH`, or the `brd tree` subprocess exits non-zero
(most commonly because the project's `root_path` no longer exists on
disk), show the existing loadError-text pattern from the memory plugin
rather than a blank panel.

## Navigation

Same three-level shape as `paulomtts.claude-memory`'s
projects → index → entry, reusing its shared components
(`CursorSurface`, `BarIconButton`, `KeyboardPanel`, `PanelKeyCatcher`,
`Style`, `Color`, `PanelSeparator`, `PanelSectionHeader` from `qs.Ui`/
`qs.Commons`) and its interaction conventions (search-box-has-focus,
Up/Down/Enter, Left-at-start-of-query/Escape = back, Tab = switch bar
panel, Delete not used — no delete feature here).

```
viewMode: "projects" | "board" | "tree" | "entry"
```

### 1. Projects (`viewMode: "projects"`)

`brd projects` → searchable, keyboard-navigable list of
`{name, root_path}`, sorted by name (mirrors `ProjectRow` in the memory
plugin — label only, no manage mode, no per-row actions). Selecting one
sets `selectedProject` and runs `brd tree` with `workingDirectory:
selectedProject.root_path`, then enters Board (the default landing view).

### 2. Board / Tree (`viewMode: "board"` or `"tree"`)

Header row: Back · project name (title) · a **Board/Tree segmented
toggle** · a refresh icon button (manual re-fetch, in addition to
automatic refresh — see below).

**Board** — 3 fixed columns, `Todo` / `In Progress` / `Done`. Only
top-level cards (`parent_id == null`, i.e. root entries of the `brd tree`
array) render as cards; a card with children shows a small
"⟨done⟩/⟨total⟩" badge computed by walking its subtree (counts every
descendant, not just direct children). Mouse-first: click a card → its
detail view. No keyboard cursor across columns in v1 (three independent
lists don't map cleanly onto one linear Up/Down cursor, and this is a
read-only viewer, not something requiring fast keyboard triage) — search
box still filters (a match anywhere in the still-visible subtree keeps a
root card visible), Escape/Tab/Left-at-start still work from the search
field.

**Tree** — the full nested hierarchy rendered as indented rows (title,
status badge, ⛔ marker when `blocked_by` is non-empty and at least one
blocker's own status isn't `done`), flattened into one keyboard-navigable
list (depth-first order) so Up/Down/Enter work exactly like the memory
plugin's index view. Search filters by title substring across the whole
tree, keeping ancestors of any match visible (so a matched leaf isn't
orphaned from context) — same `matchesQuery` + `filtered*` pattern as
today, extended to walk the tree rather than a flat array.

Both views' search field also supports the memory plugin's Left/Right
caret-edge back/forward shortcuts.

### 3. Card detail (`viewMode: "entry"`)

Reached by clicking/activating any card in Board or Tree. Shows:
- Title, status badge.
- Parent breadcrumb (if any) — clickable, jumps to the parent's detail.
- Full description (`Text.MarkdownText`, matching the memory plugin's
  entry-body treatment), or "No description." if null.
- **Blocked by** — resolved from the client-side `Map<id, card>`: each
  blocker's title + status, clickable. A blocker not present in the map
  (cross-project or since-deleted id) renders as the raw id with "(not in
  this board)".
- **Children** — same resolved-title-+-status list, clickable.

Back returns to whichever of Board/Tree was active before entering detail
(remember the prior `viewMode`, not just "index").

## Live refresh

A new helper script, `resolve-db-path.py <root_path>`, replicates `brd`'s
own hashing (`paths.py`: `sha256(str(Path(root_path).resolve())).hexdigest()`
under `~/.local/share/brd/projects/<digest>.db`, respecting
`$XDG_DATA_HOME` the same way `brd` does) and prints that path. It exists
**only** to give a `FileView` something to watch — it never opens or reads
the database. When that path changes on disk (`watchChanges: true`,
`onFileChanged: reload()` triggering a re-run of `brd tree`, not a read of
the DB file itself), the Board/Tree view silently re-fetches and
re-renders, preserving `viewMode` (board vs. tree), scroll position best-
effort, and — if still present in the refreshed tree — the current
selection.

If `resolve-db-path.py` can't compute a path (e.g. `$HOME` unset — mirrors
`paths.py`'s own assumption), auto-refresh is simply unavailable for that
project; the manual refresh button still works, and this is not surfaced
as an error (nothing is broken, just less responsive).

## Error handling

- `brd` missing from `PATH`: "Could not list brd projects (is brd
  installed?)." on the projects view, same tone/placement as the memory
  plugin's `loadError`.
- `brd tree` exits non-zero for a selected project (moved/deleted
  `root_path`, or any other CLI error): "Could not load the board for
  this project." in place of the Board/Tree content, with Back still
  available.
- Project has no cards: "This project's board is empty." empty-state text
  in Board/Tree, matching the memory plugin's "no entries yet" pattern.
- Malformed/unparseable JSON from either call: treated the same as a
  non-zero exit (defensive — `brd`'s output contract could change).

## Plugin scaffolding

`manifest.json` — `kinds: ["bar-widget"]`, `entryPoints.barWidget:
"Panel.qml"`, no `schema`/`defaults` needed (unlike the memory plugin's
`projectsRoot` override, there's nothing to configure: `brd projects`
always reads the one global registry). Bar icon: a distinct emoji/glyph
from the memory plugin's 🧠 — e.g. 🗂️.

Files: `Panel.qml` (all UI + state, same single-file shape as the memory
plugin), `logic.js` (pure tree-walking/filtering helpers — `buildCardMap`,
`flattenTree`, `subtreeCounts`, `matchesQuery` — unit-testable the same
way the memory plugin's `logic.js` is, via `tests/qml/tst_logic.qml`),
`resolve-db-path.py`, and a `tests/` dir mirroring the memory plugin's
layout (`test_resolve_db_path.py` at minimum — verifying the hash matches
`brd`'s own `paths.project_db_path` for a handful of inputs, including one
with `$XDG_DATA_HOME` set).
