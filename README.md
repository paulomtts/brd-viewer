# brd-viewer

An [Omarchy](https://omarchy.org/) shell plugin that browses a
[`brd`](https://github.com/paulomtts/brd) project's board (its cards, their
kanban status and how they nest) and the project's Markdown documents, right
from the bar. Cards and documents are strictly read-only; the one thing the
plugin can change is removing a whole project from brd (see below).

The panel is a centered popup, 840 wide, with a sidebar on the left (project
dropdown, Board / Documents navigation, Delete project...) and the current
section on the right.

## Features

- **Project dropdown** - the sidebar's top button shows the current project;
  click it or press **Ctrl+P** to open a searchable list of every project
  `brd` has registered (`brd projects`). Up/Down move, Enter or click selects.
- **Remembered project** - the panel reopens on the project you last viewed,
  also after a shell restart. It is stored in
  `~/.local/state/brd-viewer/state.json` (`$XDG_STATE_HOME` is respected). If
  that project is no longer registered, the first one is shown.
- **Sections** - **Board** (**Ctrl+1**) and **Documents** (**Ctrl+2**), also
  reachable from the sidebar with the mouse.
- **Board** - top-level cards in three status sections (Todo / In Progress /
  Done), each showing a done/total progress badge for its subtasks. A card
  reporting as blocked (derived status) appears in Todo, flagged in orange.
- **Card detail** - kind and status badges (Milestone / Story / Subtask by
  depth; Todo / In progress / Done / Blocked), full description, a parent link
  and clickable blocked-by/children lists, resolving ids to titles.
- **Documents** - lists the `.md` files under `docs/architecture/`,
  `docs/specs/` and `docs/superpowers/specs/`, and `docs/audits/` (at most 500;
  a note says when the list was cut off). Three badges above the list -
  Architecture, Specs (both spec folders), Audits - show counts; click one to
  filter, click it again to clear. The filter combines with the search box, and
  each row carries its category badge.
  Documents over 1 MB (1048576 bytes) are not displayed. A document is
  rendered as Markdown and reloads live when the file changes; links are not
  clickable, and a document that references remote images may cause them to be
  fetched when it is displayed. With none
  found the list says "No Markdown documents found in this project."
- **Status colors** - done is green, in progress is blue, blocked is orange;
  todo follows the theme's dim color.
- **Live refresh** - watches the selected project's `brd` database file
  and re-fetches automatically when it changes on disk (e.g. an agent
  updates the board while the panel is open), plus a manual refresh
  button.
- **Keyboard navigation** - Up/Down moves the highlight (the panel scrolls to
  keep it visible) through Board cards or documents and, inside a card, its
  parent/blocked-by/children links; Enter or Right-at-end opens the
  highlighted item. A card or document without links scrolls with Up/Down.
  Tab switches bar panels. Left goes Back from a card or document.
- **Escape** closes the project dropdown first; otherwise, from a card or
  document, goes Back; from a section list, closes the panel. If you have
  typed a search, Escape clears it first. Going Back restores the list
  highlight and scroll position you left.
- **Delete a project** - click **Delete project...** in the sidebar footer,
  then type `delete` to confirm, as in the Claude Memory plugin. This runs
  `brd forget`, which removes the project's board from brd. Your project's
  files are not touched. **A snapshot is always saved first**, to
  `~/Snapshots/brd-viewer/<name>-<timestamp>/` (override with
  `BRD_VIEWER_SNAPSHOT_DIR`), and if a snapshot can't be saved the project is
  not removed. Each snapshot holds `tree.json` and a `RESTORE.txt` with the
  exact commands (`brd init`, then `brd import tree.json`).
- No card or document is ever created or edited from the panel.

The plugin runs `brd` (`brd projects`, `brd tree`), plus small helpers in its
directory: `resolve-db-path.py`, `viewer-state.py` (remembers the last
project), `list-docs.py` (lists a project's documents) and
`snapshot-and-forget.py` (the delete flow).

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

## Keybinding (optional)

Add to `~/.config/hypr/bindings.lua` (Hyprland reloads it on save):

```lua
o.bind("CTRL + SUPER + J", "brd Viewer", "omarchy-shell shell toggle paulomtts.brd-viewer")
```

`CTRL + SUPER + J` is free in a stock Omarchy setup (check yours with
`hyprctl binds`); pick another key if it clashes.

## Uninstall

```bash
omarchy plugin disable paulomtts.brd-viewer
rm -rf ~/.config/omarchy/plugins/paulomtts.brd-viewer
```

## Development

```bash
./run-tests.sh
```

See `docs/superpowers/specs/2026-09-23-brd-board-viewer-design.md` and
`docs/superpowers/specs/2026-09-23-sidebar-and-documents-design.md` (sidebar
and documents) for the full design.
