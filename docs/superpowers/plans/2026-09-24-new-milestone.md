# New Milestone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A "＋ New milestone" button on the Board that opens a modal with two modes — manual (title + description → `brd add`) and from-spec (pick a spec → the user's default coding agent runs unattended with the setup-milestone prompt) — with a running indicator and a result, ending by itself.

**Architecture:** Python backend `core/backend/milestones/` (prompt, agent adapters, two runner scripts), a pure `core/domain/milestones.js`, a `MilestoneStore` (two `HelperRunner`s and a job state machine), two presentational components, and Panel wiring. Follows `docs/architecture.md` (layers, no `core/stores` import in ui components/screens, shared components, no second copies).

**Tech Stack:** QML/Quickshell, `.pragma library` JS, Python 3, pytest, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-09-24-new-milestone-design.md` (binding; read it first).

## Global Constraints

- Work only in the worktree `/home/paulomtts/Code/opm-milestone` (branch `feature/new-milestone`). NEVER touch `/home/paulomtts/Code/omarchy-project-manager` (that folder is the user's live plugin, on `main`). Never git checkout/switch/reset/rebase; never push.
- **Tests never run a real coding agent and never touch real brd data or `~/.claude`/`~/.local`.** Fakes on a temp `PATH` (argv-recording scripts named `omarchy-default-agent`, `claude`, `brd`, …), temp `XDG_STATE_HOME`/`XDG_DATA_HOME`/`HOME`. The only real agent run is the controller's final end-to-end check.
- Judge every run by exit code: `bash tests/run.sh; echo exit=$?` (baseline: exit 0, pytest 212, all QML suites pass). `omarchy plugin validate .` exit 0. Never judge by filtered output.
- **Do not run `tests/live-check.sh` or restart the desktop shell** (the worktree is not the live plugin; the session may be locked). Never send keystrokes/clicks to the desktop.
- Argv arrays only for every subprocess (no shell strings); the spec is untrusted text.
- Architecture rules stay green (`tests/architecture`): stores import only Quickshell/Quickshell.Io/QtQml/`../domain/*.js`; components/screens never import `core/stores`; `font.family:` only in ThemedText/TextAreaBox; icon glyph codepoints must exist in a Nerd Font (verify with `fc-list ":charset=<hex>"`); no local QML file named like a shell/QtQuick.Controls type.
- Commits: `git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit` with trailers `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa`.
- QML pitfalls: property names can't start uppercase; MouseArea directly in a Layout warns; click tests need `visible: true` on the TestCase; Loader-supplied `modelData` must not be `required`.

## Review Focus

1. **Runaway agent** on Cancel/timeout: the whole process group must die (test with a fake agent that spawns a child).
2. **Path/argv safety**: spec path containment (real path inside the project), no shell strings, prompt never interpreted by a shell.
3. **Stuck-flag class** (Tasks 10/11 of the previous refactor): `busy`/job state must clear on the newest run's exit even if the project changed; cancel must end in a terminal state.
4. **Board refresh** while the job runs and once at the end; card counter correct across project switches.
5. **Unsupported/unset agent** must disable OK with a clear message, never start a partial run.

---

### Task 1: The prompt and manual mode (`create-milestone.py`)

**Files:** Create `core/backend/milestones/setup-milestone.md`, `core/backend/milestones/create-milestone.py`, `tests/core/backend/milestones/test_create_milestone.py`, `tests/core/backend/milestones/test_setup_milestone_prompt.py`.

- Prompt: copy `/home/paulomtts/.claude/plugins/cache/paulomtts-plugins/leave-me-alone/4.1.2/skills/setup-milestone/SKILL.md` and apply exactly the edits listed in the spec's "The prompt" section (drop frontmatter, the brainstorming sentence, step 7 and every Workflow/orchestrator-invocation reference; keep everything else; no source header). Tests: the file exists, has no `---` frontmatter, contains `brd add`, `--blocked-by`, `brd block`, `brd tree <milestone id>`, and contains none of `superpowers:brainstorming`, `Workflow({`, `dryRun`, `taskScript`.
- `create-milestone.py <project_root> --title T [--description D]`: validates (root is a dir, title non-empty after strip, `brd` found on PATH), runs `brd add --title T [--description D]` via argv with `cwd=project_root` (brd resolves the project from cwd), parses brd's JSON output for the new card id (inspect real `brd add --help` and its output format WITHOUT running it on real data — read `brd add --help` only; for output shape use the fake), prints one JSON line `{"ok": true, "id": "<id>"}` or `{"ok": false, "error": "..."}` (exit 0/1; usage error 2). Use `core/backend/common` (`json_line`, etc.).
- Tests (hermetic, fake `brd` on PATH recording argv/cwd): argv exactly `["brd","add","--title",T,"--description",D]`, cwd is the project root, empty title refused, missing brd refused, brd failure → ok false with its message, description omitted when empty.
- [ ] RED, GREEN, run `bash tests/run.sh; echo exit=$?`, commit.

### Task 2: Agent adapters and the unattended runner

**Files:** Create `core/backend/milestones/agents.py`, `core/backend/milestones/run-setup-milestone.py`, `tests/core/backend/milestones/test_agents.py`, `test_run_setup_milestone.py`.

- `agents.py`: `ADAPTERS` mapping agent name → adapter with `build(prompt: str) -> list[str]` (argv), `restricted: bool` (True only when the agent can be limited to read + `brd`), `note` (e.g. "runs with full auto-approval"). v1 set: `claude` = `["claude","-p","--permission-mode","dontAsk","--no-session-persistence","--allowedTools","Read Glob Grep Bash(brd *)", prompt]` (restricted); `codex`, `crush`, `copilot`, `pi`, `hermes` per the spec, each built from that agent's own `--help` (read `codex exec --help`, `crush run --help`, `copilot --help`, `pi --help`, `hermes chat --help`; `--help` is safe, some agents are slow to start so allow up to 90 s) using the strictest unattended flags offered, marked `restricted=False` unless the agent offers a tool allow-list. Also read `--help` for gemini, opencode, cursor-agent, grok, omp, muse (they may be slow or trigger a first-run install; use `timeout 90`, and if `--help` cannot be obtained, leave the agent OUT of ADAPTERS): add an adapter only if its help documents a non-interactive prompt mode. Record in your report, per agent, the exact help lines that justify the argv. `supported(name)`, `describe(name) -> {supported, restricted, note}`.
- `run-setup-milestone.py <project_root> <spec_path>`: implements the spec's "The agent run" steps 1–6 exactly: validation (root dir, spec regular file with real path inside the real project root, `brd` on PATH, prompt file present), agent resolution through `omarchy-default-agent` (called by name via PATH; empty → "No default agent is set."; unsupported → "<agent> has no supported unattended mode."; not installed → "<agent> is not installed."), prompt = file contents + `## This run` section (spec path relative to the project, read it, apply the skill, create the cards with `brd` here, finish with `brd tree <milestone id>`), spawn with `subprocess.Popen(argv, cwd=root, stdin=DEVNULL, stdout=log, stderr=STDOUT, start_new_session=True)`, wait with a wall-clock limit (env `OPM_AGENT_TIMEOUT_SECONDS`, default 1800; tests use 1–2 s), SIGTERM/SIGINT handler and timeout → `os.killpg` (TERM then KILL after 5 s), log file in `${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/agent-logs/<UTC>-<project>.log` (dir 0700, file 0600), one JSON line `{"ok","agent","log","exit_code","error"}` and a matching exit code. Also a `--describe` mode: `run-setup-milestone.py --describe` prints `{"agent": "<name or empty>", "supported": bool, "restricted": bool, "note": str, "installed": bool}` so the UI can show which agent will run (no project arguments).
- Tests (hermetic, fakes on PATH): every validation error string; adapter argv per agent (exact lists); prompt passed as the last argv element containing the skill text and the relative spec path; cwd is the root; log 0600 / dir 0700; JSON on success/failure; SIGTERM kills a fake agent AND its grandchild (fake agent spawns `sleep 300`; assert both gone); timeout does the same; spec symlink escaping the project refused; `--describe` outputs; no shell involvement (a spec path with spaces and `;` works).
- [ ] RED, GREEN, full run, commit.

### Task 3: Domain module `core/domain/milestones.js`

**Files:** Create `core/domain/milestones.js`, `tests/core/domain/tst_milestones.qml`.

- `.pragma library`, imports only `results.js`/`text.js` as needed. Functions: `parseCreateResult(stdout, exitCode) -> {ok, id, error}`, `parseRunResult(stdout, exitCode) -> {ok, agent, log, exitCode, error}`, `parseDescribeResult(stdout, exitCode) -> {agent, supported, restricted, note, installed, error}` (all built on `Results.parseJsonLine`, same error-string conventions), `agentMessage(info) -> string` ("" when fine; otherwise the reason to show and disable OK: no agent / not installed / unsupported), `formatElapsed(ms) -> "m:ss"` (and "h:mm:ss" past an hour), `specChoices(docs) -> docs sorted with category "specs" first then the rest by path` (pure, keeps entries), `filterSpecChoices(list, query)` (title/path contains, case-insensitive, via `Text.matchesQuery`).
- Tests for each (edge cases: garbage output, non-zero exit with payload error, missing fields, empty query, ordering stability).
- [ ] RED, GREEN, full run, commit.

### Task 4: `MilestoneStore` and App wiring

**Files:** Create `core/stores/MilestoneStore.qml`, `tests/core/stores/tst_milestone_store.qml`; modify `core/stores/App.qml`.

- Root `Scope`; imports only Quickshell/Quickshell.Io/QtQml/`../domain/milestones.js` (+ `documents.js` only if needed). Properties: `project` (from App), `backendDir`, `cardCount` (a number handed in by App from the board store — add the binding in App: total cards known = `Object.keys(board.cardMap).length`), `dialogOpen`, `mode` ("manual"|"spec"), `title`, `description`, `selectedSpec` (relative path string), `agentInfo` (from `--describe`), `agentMessage` (derived), `dialogError`, `dialogBusy`, `jobState` ("idle"|"running"|"done"|"failed"), `jobAgent`, `jobStartedAt` (ms), `jobLog`, `jobError`, `cardsAtStart`, `cardsCreated` (= `cardCount - cardsAtStart`, clamped ≥ 0), `jobDismissed`. Runners: `manualRunner` (create-milestone.py), `specRunner` (run-setup-milestone.py), `describeRunner` (`--describe`). Commands: `openDialog()` (sets dialogOpen, refreshes `--describe`), `cancelDialog()` (blocked while `dialogBusy`), `createManual()` (validates title, runs manualRunner; on ok closes the dialog and emits `boardRefreshRequested()`), `startFromSpec()` (requires supported agent and a selected spec; runs specRunner, sets jobState running/jobStartedAt/cardsAtStart, closes the dialog), `cancelJob()` (`specRunner.cancel()`-style SIGTERM through the runner; ends in a terminal state "failed" with error "Cancelled."), `dismissResult()`. `guard` = project root on both runners (a project switch drops the result but the busy flag still clears on the newest exit: reuse HelperRunner's semantics). One job at a time (`startFromSpec` refuses while `jobState === "running"`). Signals: `boardRefreshRequested()`. Reset on project change via App's onSelected/onCleared handlers like the other stores (a running job for another project keeps running but is not shown for the new project; document the choice in a comment).
- Tests against the stub `Process` (see other store tests): state machine transitions, exact argv (`python3 <backendDir>milestones/create-milestone.py <root> --title T --description D`; `python3 …/run-setup-milestone.py <root> <spec>`), guard/stale exits, cancel → terminal state, one-job-at-a-time, `cardsCreated` follows `cardCount`, `agentMessage`, dialog cannot close while busy, `boardRefreshRequested` emitted on manual success and on job end.
- [ ] RED, GREEN, full run (+ tests/architecture), commit.

### Task 5: `NewMilestoneDialog` and `MilestoneJobIndicator`

**Files:** Create `ui/components/NewMilestoneDialog.qml`, `ui/components/MilestoneJobIndicator.qml`, tests `tests/ui/components/tst_new_milestone_dialog.qml`, `tst_milestone_job_indicator.qml`.

- `NewMilestoneDialog` (props/signals, no store import; look at `NewMemoryDialog.qml` and rebuild the same modal conventions on `ModalCard`): props `shown`, `busy`, `error`, `mode`, `title`, `description`, `specs` (array from `Milestones.specChoices`), `selectedSpec`, `agentMessage`, `agentName`, `agentNote`, `theme`; signals `modeChosen(string)`, `titleEdited(string)`, `descriptionEdited(string)`, `specChosen(string path)`, `submitRequested()`, `cancelRequested()`, `queryEdited`? (keep the spec search field's text inside the dialog). Layout: heading "New milestone"; mode switch as a `ChipRow` (Manual / From spec, objectNames `milestoneMode<id>`); manual: Title `TextField` (Enter submits), Description `TextAreaBox`; from spec: search field + scrollable list of rows (title + dim path + Specs badge via `Badge`, selected row marked, objectName `specRow<i>`, click → `specChosen`), and the line "Agent: <name>" + `agentNote` or the `agentMessage` in the urgent colour; buttons Cancel and OK (`ActionButton`; OK disabled when invalid: manual = empty title, spec = nothing selected or `agentMessage !== ""`); busy state disables everything; Escape cancels; objectNames `newMilestoneTitle`, `newMilestoneDescription`, `newMilestoneOk`, `newMilestoneCancel`, `newMilestoneError`. Shared components only (ModalCard, ChipRow, ActionButton, ThemedText, Badge, TextAreaBox); no new font.family.
- `MilestoneJobIndicator`: props `state` ("running"|"done"|"failed"), `label`, `elapsed` (string), `detail` (e.g. "3 cards created" / error text), `logPath`, `theme`; signals `cancelRequested()`, `dismissRequested()`. Running: bordered icon-only `ActionButton` with `iconText` (a Nerd-Font-covered glyph, e.g. U+F021 with `iconSpinning: true`), label "Creating milestone…", elapsed, detail, and a Cancel `ActionButton`; done/failed: a coloured status text (statusColor conventions), detail, and a Dismiss `ActionButton`. objectNames `milestoneIndicator`, `milestoneCancel`, `milestoneDismiss`.
- Tests: rendering per state, validity rules for OK in both modes, signals, spec list search/selection, error/agent message display, busy behaviour, spinning flag, icon glyph guard passes.
- [ ] RED, GREEN, full run, commit.

### Task 6: Panel integration, docs, agent verification

**Files:** Modify `ui/Panel.qml` (and `ui/Navigator.qml`/`ui/screens` only if needed), `README.md`, `docs/architecture.md`; tests under `tests/ui/`.

- Toolbar: a bordered `＋ New milestone` `ActionButton` (objectName `newMilestoneButton`) visible in the Board list view when a project is selected and `milestones.jobState !== "running"`; while a job exists (running/done/failed and not dismissed) the `MilestoneJobIndicator` takes its place. Clicking opens the dialog (`milestones.openDialog()`); in spec mode opening ensures the docs store has fetched (call the docs store's fetch if `docs.docs` is empty). Dialog bound to the store (`specs` via `Milestones.specChoices(docs)` filtered by the dialog's query). Elapsed time via a `Timer` in Panel (1 s) formatting `Milestones.formatElapsed`. `boardRefreshRequested` → `app.board.fetchBoard()`. The dialog is a modal like the others: global shortcuts blocked and focus routed while open (extend Panel `focusItem` and Shortcuts' guard the same way `newMemoryOpen` is handled).
- Docs: README (Board section: New milestone, the two modes, agent run, permissions, log location, limits) and `docs/architecture.md` (new store, backend domain, components).
- Tests: Panel-level wiring (button visibility in Board only and hidden while running, indicator swap, dialog open/close/focus, shortcut blocking, refresh on completion) against the real App with stub processes.
- [ ] RED, GREEN, full run, `omarchy plugin validate .`, commit.
