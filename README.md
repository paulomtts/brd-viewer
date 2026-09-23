# omarchy-brd-viewer

An [Omarchy](https://omarchy.org/) shell plugin that visualizes a
[`brd`](https://github.com/paulomtts/brd) project's board — its cards,
their kanban status, and their dependency/hierarchy structure — read-only,
right from the bar.

## Features

- **Projects list** — every project `brd` already has registered
  (`brd projects`), searchable.
- **Board view** — top-level cards in three columns (Todo / In Progress /
  Done), each showing a done/total progress badge for its subtasks. A card
  reporting as blocked (derived status) appears in the Todo column.
- **Tree view** — the full nested hierarchy, indented, with a ⛔ marker on
  any card still blocked by an unfinished dependency.
- **Card detail** — full description, parent breadcrumb, and clickable
  blocked-by/children lists, resolving ids to titles.
- **Live refresh** — watches the selected project's `brd` database file
  and re-fetches automatically when it changes on disk (e.g. an agent
  updates the board while the panel is open), plus a manual refresh
  button.
- Keyboard navigation in Projects and Tree views: Up/Down/Enter to navigate,
  Escape or Left-at-start-of-search-box to go Back, Right-at-end to open
  the highlighted item, and Tab to switch bar panels. Board view is
  mouse-first.
- Entirely read-only: no card is ever created, edited, or deleted from
  the panel.

## Install

```bash
git clone https://github.com/paulomtts/omarchy-brd-viewer.git \
  ~/.config/omarchy/plugins/paulomtts.brd-viewer
omarchy-shell shell rescanPlugins
omarchy plugin enable paulomtts.brd-viewer
```

Requires `brd` on `PATH`. See <https://github.com/paulomtts/brd>.

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
