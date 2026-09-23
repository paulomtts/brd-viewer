# brd-viewer

An [Omarchy](https://omarchy.org/) shell plugin that visualizes a
[`brd`](https://github.com/paulomtts/brd) project's board — its cards,
their kanban status, and their dependency/hierarchy structure — read-only,
right from the bar.

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
- Entirely read-only: no card is ever created, edited, or deleted from
  the panel.

## Install

```bash
git clone https://github.com/paulomtts/brd-viewer.git \
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
