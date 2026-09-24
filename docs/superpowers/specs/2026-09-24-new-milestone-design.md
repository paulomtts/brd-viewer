# New Milestone — design

Status: proposed. Builds on `2026-09-24-core-ui-architecture-design.md`
(core/ vs ui/, stores, shared components).

## Problem

The Board can only be read. Creating a milestone with its stories and subtasks
is done in a terminal by an agent following leave-me-alone's `setup-milestone`
skill. This adds a **＋ New milestone** button to the Board that does it from
the panel: either by hand (a title and description) or by handing a spec to the
user's default coding agent, which builds the whole milestone unattended while
the panel shows that work is happening.

## Non-goals

- No editing or deleting of cards. The only board write is creating cards, and
  it always goes through the `brd` CLI, never the database file.
- No interactive/visible agent terminal. The job is headless and ends by itself.
- No support for agents whose unattended mode has not been verified (they are
  listed as unsupported, not attempted).
- The job does not survive a shell restart (it survives closing the panel).
- No re-implementation of leave-me-alone's orchestrator or its dry run.

## User-facing behaviour

- Board toolbar: a bordered **＋ New milestone** button (icon + label style of
  the memories ＋ New), visible in the Board list view when a project is
  selected and no milestone job is running.
- Click opens a modal card (same look and behaviour as New memory: backdrop,
  Escape/backdrop cancels unless busy) with a **Manual / From spec** switch.
  - **Manual**: Title (required) and Description; Create runs
    `brd add --title … --description …` and closes; the board refreshes itself.
  - **From spec**: a searchable list of the project's Markdown documents
    (Specs first, then the rest; reuses the Documents listing), select one;
    the dialog shows which agent will run (`omarchy-default-agent`), or a clear
    message when there is none / it is not installed / it has no supported
    unattended mode (OK disabled). OK starts the job and closes the dialog.
- While a job runs: the toolbar button is replaced by a **running indicator**
  (spinning icon, "Creating milestone…", elapsed time, and a **Cancel** button);
  cards appear on the Board live as the agent creates them (the board already
  refetches when brd's database changes) and the indicator shows how many new
  cards have appeared. Keyboard: Escape closes the panel as usual; the job keeps
  running.
- On finish the indicator becomes a result: **done** (n cards created) or
  **failed** with the reason and the log path; dismissable; the Board is
  refetched once more.
- One job at a time per shell; starting is blocked while one runs.

## Architecture

```
core/backend/milestones/
  setup-milestone.md        the prompt (copied from leave-me-alone, edited, see below)
  agents.py                 adapter table: agent name -> unattended command builder + verified flag
  create-milestone.py       manual mode: brd add, prints one JSON line
  run-setup-milestone.py    from-spec mode: validate, spawn agent, wait, log, prints one JSON line
core/domain/milestones.js   parse the two scripts' results; job-state text helpers
core/stores/MilestoneStore.qml   dialog state + job state machine (idle/running/done/failed)
ui/components/NewMilestoneDialog.qml   modal (ModalCard, ChipRow for the mode, TextField, spec list)
ui/components/MilestoneJobIndicator.qml   spinner + label + elapsed + Cancel / result
ui/Panel.qml              hosts the toolbar button/indicator and the dialog
```

- **Store** (`MilestoneStore`, `Scope` root like the others): properties `mode`,
  `dialogOpen`, `title`, `description`, `selectedSpec`, `agentInfo`
  (name/supported/reason), `jobState`, `jobStartedAt`, `jobLog`, `jobError`,
  `cardsCreated`; commands `open()`, `cancelDialog()`, `createManual()`,
  `startFromSpec()`, `cancelJob()`, `dismissResult()`. It uses two
  `HelperRunner`s (manual, spec). `guard` is the project root so a switch never
  applies a stale result; the running job keeps its own busy flag from the
  runner (the Ruling-7 semantics: busy clears when the newest run exits).
- **Wiring** in `App.qml`: `milestones.project`, `milestones.backendDir`,
  `milestones.cardCount: board.boardCards.length + …` (a plain count property
  handed in, so the store never imports the board store).
- **UI rules** unchanged: components take props/signals, screens/components
  never import `core/stores`; only Panel talks to `app`.
- The Documents listing feeds the spec picker: opening the dialog in From-spec
  mode makes the docs store fetch if it has not (Panel wiring, not a store
  import).

## The agent run (`run-setup-milestone.py <project_root> <spec_path>`)

1. Validate: project root is a directory; the spec is a regular file whose real
   path is inside the project root (same containment rule as the other
   helpers); `brd` is on PATH; a prompt file exists. No extension check: the
   picker only ever offers the project's Markdown documents, and the agent is
   given the path to read, so refusing a file for its name would buy nothing.
2. Resolve the agent: `omarchy-default-agent` (empty → error "No default agent
   is set"), the adapter for it (unknown/unverified → error "<agent> has no
   supported unattended mode"), `command -v` (missing → "<agent> is not
   installed").
3. Build the prompt: the contents of `setup-milestone.md`, then a final section
   `## This run` giving the spec's path relative to the project and the
   instruction to read it, apply the skill and create the cards with `brd`
   in the current directory.
4. Spawn the agent **in its own session/process group** with cwd = project
   root, stdin closed, output appended to a log file
   `${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/agent-logs/<UTC>-<project>.log`
   (directory 0700, file 0600). A wall-clock limit (default 30 min) kills the
   group.
5. On `SIGTERM` (the panel's Cancel) or the limit: kill the whole process group,
   report `cancelled`/`timed out`. Otherwise report the exit status.
6. Print exactly one JSON line: `{"ok": bool, "agent", "log", "exit_code",
   "error"}`; exit code 0 on ok.
- **Permissions:** for `claude` the run is restricted: `-p --permission-mode
  dontAsk --no-session-persistence --allowedTools "Read Glob Grep Bash(brd *)"`
  (a spec is untrusted text the agent follows; it can read the project and run
  `brd`, and nothing else). Adapters for other agents use the strictest
  unattended flags that agent offers; where an agent cannot be restricted, the
  dialog states "runs with full auto-approval" next to the agent name.
- **Adapters (v1):** `claude` (`-p …`), `codex` (`exec …`), `crush` (`run …`),
  `copilot` (`-p …`), `pi` (`-p …`), `hermes` (`chat -q …`). Every other agent is
  unsupported until its headless invocation has been verified on this machine
  (gemini, opencode, cursor-agent, grok, omp, muse are checked during the build;
  each is enabled only with a passing adapter test).
- The prompt is passed as an argument or on stdin per adapter (never through a
  shell string; argv arrays only), so a spec's content cannot inject commands.

## The prompt (`setup-milestone.md`)

Copied from leave-me-alone's `setup-milestone` skill with these edits, and no
source header:
- drop the frontmatter (it is a plain prompt now) and the sentence that
  refers to running `superpowers:brainstorming` (a spec is always supplied);
- drop step 7 (the orchestrator dry run) and every reference to invoking
  leave-me-alone workflows/`Workflow(...)`; the stack/branch guidance stays,
  because the cards are meant to be consumed by branch-per-subtask tooling;
- keep discover-don't-invent (`brd tree`), the sizing rules, chaining with
  `--blocked-by`/`brd block`, one blocker per story, and the verification
  (`brd tree <milestone id>`) — the agent must finish by printing the tree.

## Testing

- **Hermetic:** tests never run a real agent or touch real brd data. Backend
  tests put fake `omarchy-default-agent`, agent binaries and `brd` on a temp
  `PATH` (argv-recording scripts) and assert: validation errors, adapter argv
  per agent, prompt file content and spec section, cwd, log permissions,
  process-group kill on SIGTERM and on the time limit, JSON output, that a
  spec outside the project is refused.
- **Store/UI:** store tests drive the stub `Process` (state machine, guard,
  cancel, busy semantics, one job at a time, count of created cards);
  component tests for the dialog (modes, validation, spec list search/select,
  agent info messages, busy) and the indicator (spinning, elapsed, cancel,
  result states); Panel wiring tests (button visibility, indicator swap).
- **One real end-to-end run** at the end, by the controller, on a scratch brd
  project (temporary `XDG_DATA_HOME`) with a tiny spec and the real `claude`
  adapter, asserting cards exist and the process exits by itself.
- Architecture tests stay green (layers, name clashes, no duplicated visual
  patterns, icon glyph coverage).

## Risks

- **Agent behaviour differs per version.** Adapters are data plus one
  test each; unverified agents stay disabled.
- **Cancel must not leave a runaway agent.** Process-group kill is tested with
  a fake agent that spawns a child.
- **Prompt drift** from the upstream skill is accepted (a plain copy); the file
  is the plugin's own.
- **No real-shell verification while the desktop is locked**; the end-to-end
  run above needs no desktop, the UI is checked live once unlocked.
