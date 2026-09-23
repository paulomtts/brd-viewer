# brd-viewer

An [Omarchy](https://omarchy.org/) shell plugin that visualizes a
[`brd`](https://github.com/paulomtts/brd) project's board — its cards,
their kanban status, and their dependency/hierarchy structure — right from
the bar. Cards are strictly read-only; the one thing it can change is removing
a whole project from brd (see below).

## Features

- **Projects list** — every project `brd` already has registered
  (`brd projects`), searchable.
- **Board view** — top-level cards in three status sections (Todo / In
  Progress / Done), each showing a done/total progress badge for its
  subtasks. A card reporting as blocked (derived status) appears in the Todo
  section, flagged in orange.
- **Tree view** — the full nested hierarchy, indented, with a ⛔ marker on
  any card still blocked by an unfinished dependency.
- **Card detail** — kind and status badges (Milestone / Story / Subtask by
  depth; Todo / In progress / Done / Blocked), full description, a parent link
  and clickable blocked-by/children lists, resolving ids to titles.
- **Status colors** — done is green, in progress is blue, blocked is orange;
  todo follows the theme's dim color.
- **Live refresh** — watches the selected project's `brd` database file
  and re-fetches automatically when it changes on disk (e.g. an agent
  updates the board while the panel is open), plus a manual refresh
  button.
- **Keyboard navigation** everywhere: Up/Down moves the highlight (the panel
  scrolls to keep it visible) through projects, Board cards, Tree rows, and,
  inside a card, its parent/blocked-by/children links; Enter or
  Right-at-end opens the highlighted item. Escape or Left-at-start-of-search-box
  goes Back (from Board, Tree, or card detail; in the Projects list Escape
  closes the panel), and going Back from a card restores the list position.
  A card without links scrolls with Up/Down instead. Tab switches bar panels.
- **Delete a project** — press Delete on a highlighted project (or click its
  🗑 button), then type `delete` to confirm, as in the Claude Memory plugin.
  This runs `brd forget`, which removes the project's board from brd. Your
  project's files are not touched. **A snapshot is always saved first**, to
  `~/Snapshots/brd-viewer/<name>-<timestamp>/` (override with
  `BRD_VIEWER_SNAPSHOT_DIR`), and if a snapshot can't be saved the project is
  not removed. Each snapshot holds `tree.json` and a `RESTORE.txt` with the
  exact commands (`brd init`, then `brd import tree.json`).
- No card is ever created, edited, or deleted from the panel.

## Install

```bash
git clone https://github.com/paulomtts/brd-viewer.git
cd brd-viewer
./install.sh              # links the plugin, rescans, enables it
./install.sh --with-brd   # ...and installs the brd CLI first if it is missing
```

The plugin only reads from `brd`, and the two are separate projects, so
installing `brd` is optional: without `--with-brd` (or `--no-brd`) you are
asked when it is missing, and a non-interactive run skips it. `--with-brd` uses
`uv tool install` (or `pipx`) on `git+https://github.com/paulomtts/brd.git`, so
it needs access to that repository; if the install fails the plugin is still
installed. Set `BRD_SOURCE` to install `brd` from somewhere else. Use
`--dry-run` to see what would happen. The installer links the checkout instead
of copying it, so `git pull` updates the plugin (then run
`omarchy-restart-shell`).

Requires `brd` on `PATH` to show anything. See <https://github.com/paulomtts/brd>.

## Uninstall

```bash
omarchy plugin disable paulomtts.brd-viewer
rm -rf ~/.config/omarchy/plugins/paulomtts.brd-viewer
```

## Development

```bash
./run-tests.sh
```

See `docs/superpowers/specs/2026-09-23-brd-board-viewer-design.md` for
the full design.
