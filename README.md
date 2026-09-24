# Omarchy Project Manager

An [Omarchy](https://omarchy.org/) shell plugin for working across your
[`brd`](https://github.com/paulomtts/brd) projects, right from the bar. Pick a
project in the sidebar, then browse its kanban **Board**, its milestone
**Graph**, its Markdown **Documents** (with typed badges you can assign), and
the **Memories** Claude Code keeps for it, which you can read, edit, create and
delete. Cards are read-only; the plugin's writes are limited to a document's
frontmatter `tag:`, a project's Claude memory notes, and removing a whole
project from brd (each described below, each with a backup or snapshot).

The panel is a centered popup (about 80% of the screen), with a sidebar on the
left (project dropdown, section navigation, Delete project...) and, on the
right, a fixed toolbar above the scrolling content.

Formerly named brd-viewer (`paulomtts.brd-viewer`). Data written under the old
name stays where it is: the remembered project is read from the old location
until it is next saved, and existing snapshots and backups are left in their
`brd-viewer` folders.

## Features

- **Project dropdown** - the sidebar's top button shows the current project;
  click it or press **Ctrl+P** to open a searchable list of every project
  `brd` has registered (`brd projects`). Up/Down move, Enter or click selects.
- **Remembered project** - the panel reopens on the project you last viewed,
  also after a shell restart. It is stored in
  `~/.local/state/omarchy-project-manager/state.json` (`$XDG_STATE_HOME` is respected). If
  that project is no longer registered, the first one is shown.
- **Sections** - **Board** (**Ctrl+1**), **Graph** (**Ctrl+2**), **Documents** (**Ctrl+3**) and **Memories** (**Ctrl+4**), also
  reachable from the sidebar with the mouse, where each one carries its own
  icon. The digits follow the order the sidebar lists the sections in.
- **Board** - top-level cards in three status sections (Todo / In Progress /
  Done), each showing a done/total progress badge for its subtasks. A card
  reporting as blocked (derived status) appears in Todo, flagged in orange.
- **Graph** (Ctrl+2) - a pan/zoom canvas with one node per milestone (title,
  status colour, done/total progress) and an arrow for each `blocked_by` link
  between milestones, laid out left to right. Arrow keys move the selection to
  the nearest node in that direction and the view follows; Enter or a click
  opens the milestone's card, and Back returns to the graph. The canvas also
  has mouse pan/zoom, `+`/`-` and on-screen zoom/organize/fit buttons. Nodes can
  be dragged for a look around, but the graph never creates or removes links.
- **Memories** (Ctrl+4) - the project's Claude Code memory notes, from
  `~/.claude/projects/<slug>/memory/` (the slug is the project path with every
  non-alphanumeric character turned into `-`; if that folder is missing, a
  project whose session transcripts record this path is used). Each note shows
  its name, description and a type badge (User, Feedback, Project, Reference,
  Other) that filters like the Documents badges; search matches name,
  description and file name. Open a note to read it, then **Edit** (Ctrl+E) to
  change its raw text (Ctrl+S saves, Escape leaves a clean editor and never
  discards unsaved changes), **Delete** (type `delete`), or **＋ New** (Ctrl+N)
  to create one. Every change goes through `core/backend/memories/memory-op.py`, which first copies the
  note and `MEMORY.md` to `~/.cache/omarchy-project-manager/memory-backups/`, replaces files
  atomically, and keeps the note's `- [Title](file.md) - hook` line in
  `MEMORY.md` in sync (name and description come from the note's frontmatter).
  A project that was renamed since Claude Code stored its memory will show none,
  because Claude Code keys memory by path; nothing is lost on disk.
- **New milestone** - in the Board list, **＋ New milestone** opens a modal with
  two ways to create one.
  - **Manual** - a title and an optional description go straight to
    `brd add` in the project, and the board refreshes.
  - **From spec** - pick one of the project's Markdown documents (the Specs
    ones lead the list; search by title or path) and your default coding agent
    reads it and builds the milestone, story and subtask cards with `brd`,
    unattended. The agent is whatever `omarchy-default-agent` reports; the
    dialog names it and says how it will run, and refuses to start when no
    default agent is set, it is not installed, or it has no supported
    unattended mode. Supported: `claude`, `codex`, `crush`, `copilot`, `pi`,
    `hermes`, `gemini`, `opencode`, `cursor-agent`, `grok`, `omp`, `muse`.
    **Only `claude` is restricted** (it runs with `--allowedTools
    "Read Glob Grep Bash(brd *)"`, i.e. reading the project and running `brd`);
    every other agent runs with its own full auto-approval flags, which is
    stated in the dialog before you start.
  - While it runs, a toolbar indicator replaces the button with the elapsed
    time and a **Cancel** (which kills the agent's whole process group), and at
    the end it reports how many cards appeared, or why the run failed, plus the
    log path. The agent's output is written to
    `~/.local/state/omarchy-project-manager/agent-logs/<utc>-<project>.log`
    (`$XDG_STATE_HOME` is respected; the directory is `0700` and the file
    `0600`).
  - Limits: **one job at a time**, per shell - a second Start is refused with a
    note in the dialog, also when the run belongs to another project. The job
    is a child of the shell, so restarting the shell (or logging out) ends it;
    the cards already created stay. A run gives up after 30 minutes
    (`OPM_AGENT_TIMEOUT_SECONDS`). That shutdown kills the agent's whole
    process group - but if the shell itself is killed outright (`SIGKILL`, a
    crash) the agent is orphaned and keeps writing cards until it finishes or
    the time limit ends it; the log file is how you see what it did. The job keeps running when you switch
    project, but only its own project's Board shows it. Nothing the agent does
    is reviewed by the plugin - it writes cards to `brd` on your behalf.
- **Card detail** - kind and status badges (Milestone / Story / Subtask by
  depth; Todo / In progress / Done / Blocked), full description, a parent link
  and clickable blocked-by/children lists, resolving ids to titles.
- **Documents** - lists every `.md` file under `docs/` (at most 500; a note says
  when the list was cut off). Each document has one type: Architecture, Specs,
  Standards, Audits, or Other. Set it with a `tag:` line in the file's YAML
  frontmatter (`tag: spec`, `standard`, `audit`, `architecture`; case and
  singular/plural do not matter); without one the folder decides
  (`docs/architecture`, `docs/specs` and `docs/superpowers/specs`,
  `docs/standards`, `docs/audits`), and anything else is Other. Badges in the
  fixed toolbar show counts; click one to filter, click it again to clear. An
  open document keeps its path and its type picker in that toolbar too, so only
  the document body scrolls. The filter
  combines with the search box, and each row carries its badge. The frontmatter
  block is not shown when a document is opened.
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
- **Breadcrumbs** - the toolbar always leads with the trail to where you are:
  `Board`, or `Board › Milestone › Story › Subtask` inside a card (`Graph ›` …
  when the card was opened from the graph), `Documents › <title>` and
  `Memories › <note>`. Click the section crumb to go back the way the old
  "Back" did, or an ancestor crumb to open that card; the last crumb is where
  you are.
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
  then type `delete` in the confirmation dialog (a modal over a dimmed backdrop; Escape or a click outside cancels) to confirm, as in the Claude Memory plugin. This runs
  `brd forget`, which removes the project's board from brd. Your project's
  files are not touched. **A snapshot is always saved first**, to
  `~/Snapshots/omarchy-project-manager/<name>-<timestamp>/` (override with
  `OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR`), and if a snapshot can't be saved the project is
  not removed. Each snapshot holds `tree.json` and a `RESTORE.txt` with the
  exact commands (`brd init`, then `brd import tree.json`).
- No card or document is ever created or edited from the panel.

The plugin runs `brd` (`brd projects`, `brd tree`), plus small helpers in its
`core/backend/<domain>/` folders: `projects/resolve-db-path.py`,
`projects/viewer-state.py` (remembers the last project),
`documents/list-docs.py` (lists a project's documents),
`projects/snapshot-and-forget.py` (the delete flow), and the New-milestone
pair: `milestones/create-milestone.py` (manual mode: one `brd add`) and
`milestones/run-setup-milestone.py` (the unattended agent run, plus
`--describe` for which agent the dialog will use), which builds its prompt from
`milestones/setup-milestone.md` and resolves the agent's argv through
`milestones/agents.py`.

## Install

```bash
git clone https://github.com/paulomtts/omarchy-project-manager.git
cd omarchy-project-manager
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
o.bind("CTRL + SUPER + J", "Omarchy Project Manager", "omarchy-shell shell toggle paulomtts.omarchy-project-manager")
```

`CTRL + SUPER + J` is free in a stock Omarchy setup (check yours with
`hyprctl binds`); pick another key if it clashes.

## Uninstall

```bash
omarchy plugin disable paulomtts.omarchy-project-manager
rm -rf ~/.config/omarchy/plugins/paulomtts.omarchy-project-manager
```

## Development

Layout (details and rules in `docs/architecture.md`):

```
manifest.json          entryPoints.barWidget -> ui/Panel.qml
install.sh             installer (the only source file at the root)
core/domain/           pure JavaScript rules and parsers
core/backend/<domain>/ Python helpers (one JSON line each) + common/
core/stores/           non-visual QML state and workflows (App composes them)
ui/                    Panel, Shortcuts, Navigator, screens/, components/, theme/
vendor/canvas/         vendored canvas plugin (see VENDORED.md)
tests/                 core/, ui/, architecture/, helpers/, stubs/
```

Data flow: `Panel` creates one `App`; stores run `brd` and the helpers and
expose properties; screens and components bind to them. `ui/` may use `core/`,
never the reverse.

## Tests

```bash
bash tests/run.sh [filter]   # pytest, then every QML test (optional path filter)
./run-tests.sh               # thin delegate to tests/run.sh
bash tests/live-check.sh     # restarts the real shell; needs the desktop session
```

See `docs/architecture.md` and the specs in `docs/superpowers/specs/`
(board viewer, sidebar and documents, core/ui architecture) for the design.
