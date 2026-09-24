// tests/core/stores/tst_milestone_store.qml
// The New-milestone dialog and the agent job: the state machine, the exact argv
// of the three helpers, the guard against results from a project the user has
// left, cancelling, and the one-job-at-a-time rule -- driven through App so the
// wiring to the project and board stores is exercised too. The dialog's looks,
// the spec picker and the running indicator live in the UI and are tested there.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresMilestoneStore"

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  property string agentOk: '{"agent": "claude", "supported": true, "restricted": true, "note": "", "installed": true}'
  property string agentNone: '{"agent": "", "supported": false, "restricted": false, "note": "", "installed": false}'
  property string agentMissing: '{"agent": "codex", "supported": true, "restricted": false, "note": "", "installed": false}'

  function make() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var app = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    return app
  }

  function spyOn(target, name) {
    var spy = Qt.createQmlObject('import QtTest; SignalSpy {}', tc)
    spy.target = target
    spy.signalName = name
    return spy
  }

  function card(id) { return { id: id, title: "c" + id, status: "todo", children: [] } }
  function cards(n) {
    var out = []
    for (var i = 0; i < n; i++) out.push(card("c" + i))
    return out
  }

  // The dialog in From-spec mode, with the default agent already checked and
  // usable. The check is skipped when this project's answer is already known.
  function specFixture(app) {
    app.milestones.openDialog()
    app.milestones.mode = "spec"
    var d = app.milestones.describeRunner.current
    if (d) { d.outText = agentOk; d.exited(0) }
    app.milestones.selectedSpec = "docs/specs/one.md"
    return app
  }

  function startedJob() {
    var app = make(); if (!app) return null
    specFixture(app)
    app.milestones.startFromSpec()
    return app
  }

  // ---- the dialog and the agent check

  // Manual mode needs no agent, so opening the dialog must not go looking for
  // one: nothing is said about the agent until the user asks for From-spec.
  function test_opening_the_dialog_clears_it_and_checks_nothing_yet() {
    var app = make(); if (!app) return
    compare(app.milestones.dialogOpen, false)
    app.milestones.title = "left over"
    app.milestones.dialogError = "old"
    app.milestones.openDialog()
    compare(app.milestones.dialogOpen, true)
    compare(app.milestones.mode, "manual")
    compare(app.milestones.title, "")
    compare(app.milestones.description, "")
    compare(app.milestones.selectedSpec, "")
    compare(app.milestones.dialogError, "")
    verify(!app.milestones.describeRunner.current, "no agent check yet")
    compare(app.milestones.agentChecking, false)
    compare(app.milestones.agentMessage, "", "and nothing to say about an agent nobody asked about")
  }

  function test_entering_spec_mode_checks_the_default_agent() {
    var app = make(); if (!app) return
    app.milestones.openDialog()
    app.milestones.mode = "spec"
    var proc = app.milestones.describeRunner.current
    verify(proc, "the agent check runs")
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/milestones/run-setup-milestone.py")
    compare(proc.command[2], "--describe")
    compare(proc.command.length, 3)
    compare(app.milestones.agentChecking, true)
    compare(app.milestones.agentMessage, "", "no verdict while the check is still running")
    proc.outText = agentOk
    proc.exited(0)
    compare(app.milestones.agentChecking, false)
    compare(app.milestones.agentInfo.agent, "claude")
    compare(app.milestones.agentMessage, "")
  }

  // The answer does not change while the user stays in the project: going back
  // and forth between the modes must not re-run the check every time.
  function test_the_agent_is_checked_once_per_project() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    specFixture(app)
    compare(app.milestones.describeRunner.seq, 1)
    app.milestones.mode = "manual"
    app.milestones.mode = "spec"
    compare(app.milestones.describeRunner.seq, 1, "the known answer is reused")
    app.projects.chooseProject(pB)
    app.milestones.openDialog()
    app.milestones.mode = "spec"
    compare(app.milestones.describeRunner.seq, 2, "the new project is checked again")
  }

  function test_the_agent_check_becomes_the_agent_message() {
    var app = make(); if (!app) return
    app.milestones.applyDescribeResult(agentNone, 0)
    compare(app.milestones.agentMessage, "No default agent is set.")
    app.milestones.applyDescribeResult(agentMissing, 0)
    compare(app.milestones.agentMessage, "codex is not installed.")
    app.milestones.applyDescribeResult(agentOk, 0)
    compare(app.milestones.agentMessage, "")
  }

  // A check that failed says so, instead of blaming a missing default agent.
  function test_a_failed_agent_check_is_reported_and_blocks_the_run() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.mode = "spec"
    var proc = app.milestones.describeRunner.current
    proc.outText = "boom"
    proc.exited(1)
    compare(app.milestones.agentChecking, false)
    verify(app.milestones.agentMessage !== "", "the reason is shown")
    verify(app.milestones.agentMessage !== "No default agent is set.")
    app.milestones.selectedSpec = "docs/specs/one.md"
    app.milestones.startFromSpec()
    verify(!app.milestones.specRunner.current, "nothing was run")
  }

  // The answer belongs to the project it was asked for: after a switch it must
  // not fill in the agent for the project the user is looking at now, even when
  // it is the only check that has ever run.
  function test_an_agent_check_from_the_previous_project_is_ignored() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.mode = "spec"
    var stale = app.milestones.describeRunner.current
    app.projects.chooseProject(pB)
    stale.outText = agentOk
    stale.exited(0)
    compare(app.milestones.agentInfo, null, "the old project's answer is dropped")
    compare(app.milestones.agentMessage, "")
    app.milestones.selectedSpec = "docs/specs/one.md"
    app.milestones.startFromSpec()
    verify(!app.milestones.specRunner.current, "and an unchecked agent can never start a run")
  }

  // A check the user is still waiting for is not stale: coming back to the
  // project it was asked for still fills the agent in.
  function test_an_agent_check_survives_a_round_trip_through_another_project() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.mode = "spec"
    var proc = app.milestones.describeRunner.current
    app.projects.chooseProject(pB)
    app.projects.chooseProject(pA)
    proc.outText = agentOk
    proc.exited(0)
    compare(app.milestones.agentMessage, "")
    compare(app.milestones.agentInfo.agent, "claude")
  }

  // ---- manual mode

  function test_creating_manually_runs_the_helper_with_the_title_and_description() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.title = "  Ship it  "
    app.milestones.description = "the why"
    app.milestones.createManual()
    var proc = app.milestones.manualRunner.current
    verify(proc, "a create process")
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/milestones/create-milestone.py")
    compare(proc.command[2], "/home/u/my proj")
    compare(proc.command[3], "--title")
    compare(proc.command[4], "Ship it")
    compare(proc.command[5], "--description")
    compare(proc.command[6], "the why")
    compare(proc.command.length, 7)
    compare(proc.running, true)
    compare(app.milestones.dialogBusy, true)
  }

  function test_an_empty_description_is_left_out_of_the_command() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.title = "Ship it"
    app.milestones.description = "   "
    app.milestones.createManual()
    var proc = app.milestones.manualRunner.current
    compare(proc.command.length, 5)
    compare(proc.command[4], "Ship it")
  }

  function test_a_blank_title_is_refused_before_anything_runs() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.title = "   "
    app.milestones.createManual()
    verify(!app.milestones.manualRunner.current, "nothing was run")
    compare(app.milestones.dialogBusy, false)
    compare(app.milestones.dialogOpen, true)
    verify(app.milestones.dialogError !== "", "the dialog says why")
  }

  function test_a_successful_create_closes_the_dialog_and_asks_for_a_board_refresh() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    var spy = spyOn(app.milestones, "boardRefreshRequested")
    app.milestones.openDialog()
    app.milestones.title = "Ship it"
    app.milestones.createManual()
    var proc = app.milestones.manualRunner.current
    proc.outText = '{"ok": true, "id": "42"}'
    proc.exited(0)
    compare(app.milestones.dialogOpen, false)
    compare(app.milestones.dialogBusy, false)
    compare(app.milestones.dialogError, "")
    compare(app.milestones.title, "")
    compare(spy.count, 1)
  }

  function test_a_failed_create_keeps_the_dialog_open_with_the_error() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    var spy = spyOn(app.milestones, "boardRefreshRequested")
    app.milestones.openDialog()
    app.milestones.title = "Ship it"
    app.milestones.createManual()
    var proc = app.milestones.manualRunner.current
    proc.outText = '{"ok": false, "error": "brd said no"}'
    proc.exited(1)
    compare(app.milestones.dialogOpen, true)
    compare(app.milestones.dialogBusy, false)
    compare(app.milestones.dialogError, "brd said no")
    compare(app.milestones.title, "Ship it")
    compare(spy.count, 0)
  }

  function test_the_dialog_cannot_be_closed_while_the_create_is_in_flight() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.title = "Ship it"
    app.milestones.createManual()
    app.milestones.cancelDialog()
    compare(app.milestones.dialogOpen, true, "the dialog stays while busy")
    var proc = app.milestones.manualRunner.current
    proc.outText = '{"ok": false, "error": "no"}'
    proc.exited(1)
    compare(app.milestones.dialogBusy, false)
    app.milestones.cancelDialog()
    compare(app.milestones.dialogOpen, false)
  }

  function test_only_one_create_at_a_time() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.title = "one"
    app.milestones.createManual()
    var proc = app.milestones.manualRunner.current
    app.milestones.title = "two"
    app.milestones.createManual()
    compare(app.milestones.manualRunner.current, proc, "the second attempt is refused")
    compare(proc.command[4], "one")
  }

  // The lock is the runner's own: leaving the project while a create is in
  // flight must not keep the dialog busy for the rest of the session.
  function test_a_create_abandoned_by_a_project_switch_releases_the_lock() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.title = "one"
    app.milestones.createManual()
    var abandoned = app.milestones.manualRunner.current
    app.projects.chooseProject(pB)
    compare(app.milestones.dialogOpen, false, "the dialog is cleared by the switch")
    abandoned.outText = '{"ok": true, "id": "42"}'
    abandoned.exited(0)
    compare(app.milestones.dialogBusy, false, "the abandoned create must not hold the lock")
    compare(app.milestones.dialogOpen, false, "and its result must not reopen anything")
    app.milestones.openDialog()
    app.milestones.title = "two"
    app.milestones.createManual()
    var proc = app.milestones.manualRunner.current
    compare(proc.command[2], "/home/u/b")
    compare(proc.command[4], "two")
  }

  // A create answered for a project the user has left can never close the
  // dialog of the one they are in now, nor refresh its board.
  function test_a_create_result_for_another_project_is_ignored() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    var spy = spyOn(app.milestones, "boardRefreshRequested")
    app.milestones.openDialog()
    app.milestones.title = "Ship it"
    app.milestones.createManual()
    app.milestones.applyCreateResult('{"ok": true, "id": "42"}', 0, "/home/u/elsewhere")
    compare(app.milestones.dialogOpen, true)
    compare(app.milestones.title, "Ship it")
    compare(spy.count, 0)
    app.milestones.applyCreateResult('{"ok": true, "id": "42"}', 0, "/home/u/my proj")
    compare(app.milestones.dialogOpen, false)
    compare(spy.count, 1)
  }

  // ---- starting the agent job

  function test_starting_from_a_spec_runs_the_runner_and_closes_the_dialog() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.board.applyTreeData(cards(3))
    specFixture(app)
    compare(app.milestones.cardCount, 3)
    app.milestones.startFromSpec()
    var proc = app.milestones.specRunner.current
    verify(proc, "a run process")
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/milestones/run-setup-milestone.py")
    compare(proc.command[2], "/home/u/my proj")
    compare(proc.command[3], "docs/specs/one.md")
    compare(proc.command.length, 4)
    compare(proc.running, true)
    compare(app.milestones.jobState, "running")
    compare(app.milestones.jobVisible, true)
    compare(app.milestones.cardsAtStart, 3)
    compare(app.milestones.cardsCreated, 0)
    compare(app.milestones.dialogOpen, false)
    verify(app.milestones.jobStartedAt > 0, "the clock started")
  }

  function test_starting_from_a_spec_is_refused_without_a_usable_agent() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.mode = "spec"
    var d = app.milestones.describeRunner.current
    d.outText = agentMissing
    d.exited(0)
    compare(app.milestones.agentMessage, "codex is not installed.")
    app.milestones.selectedSpec = "docs/specs/one.md"
    app.milestones.startFromSpec()
    verify(!app.milestones.specRunner.current, "nothing was run")
    compare(app.milestones.jobState, "idle")
    compare(app.milestones.dialogOpen, true)
  }

  // A check that has not answered yet is not a green light.
  function test_starting_from_a_spec_is_refused_while_the_agent_check_runs() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.mode = "spec"
    app.milestones.selectedSpec = "docs/specs/one.md"
    compare(app.milestones.agentChecking, true)
    compare(app.milestones.agentMessage, "")
    app.milestones.startFromSpec()
    verify(!app.milestones.specRunner.current, "nothing was run")
    compare(app.milestones.jobState, "idle")
  }

  function test_starting_from_a_spec_is_refused_without_a_selected_spec() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    specFixture(app)
    app.milestones.selectedSpec = ""
    app.milestones.startFromSpec()
    verify(!app.milestones.specRunner.current, "nothing was run")
    compare(app.milestones.jobState, "idle")
  }

  // One job per shell: a second start while one runs changes nothing at all.
  function test_only_one_job_at_a_time() {
    var app = startedJob(); if (!app) return
    var proc = app.milestones.specRunner.current
    var startedAt = app.milestones.jobStartedAt
    app.milestones.selectedSpec = "docs/specs/two.md"
    app.milestones.startFromSpec()
    compare(app.milestones.specRunner.current, proc, "the second start is refused")
    compare(proc.command[3], "docs/specs/one.md")
    compare(app.milestones.jobStartedAt, startedAt)
  }

  // Refusing silently would read as a broken button -- especially from another
  // project, where the running job is not even on screen.
  function test_a_second_run_is_refused_with_a_reason() {
    var app = startedJob(); if (!app) return
    app.projects.chooseProject(pB)
    specFixture(app)
    app.milestones.startFromSpec()
    compare(app.milestones.dialogError, "A milestone run is already in progress.")
    compare(app.milestones.dialogOpen, true, "the dialog stays up to show it")
    compare(app.milestones.jobProject, pA.root_path, "and the running job is untouched")
  }

  // ---- the job's end

  function test_a_finished_run_ends_the_job_and_asks_for_a_board_refresh() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.board.applyTreeData(cards(2))
    specFixture(app)
    var spy = spyOn(app.milestones, "boardRefreshRequested")
    app.milestones.startFromSpec()
    app.board.applyTreeData(cards(9))
    var proc = app.milestones.specRunner.current
    proc.outText = '{"ok": true, "agent": "claude", "log": "/l/x.log", "exit_code": 0}'
    proc.exited(0)
    compare(app.milestones.jobState, "done")
    compare(app.milestones.jobError, "")
    compare(app.milestones.jobAgent, "claude")
    compare(app.milestones.jobLog, "/l/x.log")
    compare(app.milestones.cardsCreated, 7)
    compare(app.milestones.jobVisible, true)
    compare(spy.count, 1)
    // The result is what the run created, not what the board does afterwards.
    app.board.applyTreeData(cards(20))
    compare(app.milestones.cardsCreated, 7, "the count is frozen when the job ends")
  }

  function test_a_failed_run_shows_the_reason_and_the_log() {
    var app = startedJob(); if (!app) return
    var proc = app.milestones.specRunner.current
    proc.outText = '{"ok": false, "agent": "claude", "log": "/l/x.log", "exit_code": 2, "error": "The agent exited 2."}'
    proc.exited(1)
    compare(app.milestones.jobState, "failed")
    compare(app.milestones.jobError, "The agent exited 2.")
    compare(app.milestones.jobLog, "/l/x.log")
  }

  // Cancel ends the job here and now: the runner's own exit is dropped, so
  // nothing else would ever move the job out of "running".
  function test_cancelling_the_job_ends_it_in_a_terminal_state() {
    var app = startedJob(); if (!app) return
    var proc = app.milestones.specRunner.current
    app.milestones.cancelJob()
    compare(app.milestones.jobState, "failed")
    compare(app.milestones.jobError, "Cancelled.")
    compare(proc.running, false, "the helper is stopped")
    compare(app.milestones.specRunner.busy, false)
    proc.outText = '{"ok": true, "agent": "claude", "log": "/l/x.log", "exit_code": 0}'
    proc.exited(0)
    compare(app.milestones.jobState, "failed", "the late exit changes nothing")
    compare(app.milestones.jobError, "Cancelled.")
  }

  function test_a_cancelled_job_can_be_followed_by_a_new_one() {
    var app = startedJob(); if (!app) return
    app.milestones.cancelJob()
    specFixture(app)
    app.milestones.startFromSpec()
    compare(app.milestones.jobState, "running")
    compare(app.milestones.jobError, "")
  }

  function test_cancelling_when_no_job_runs_does_nothing() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.cancelJob()
    compare(app.milestones.jobState, "idle")
    compare(app.milestones.jobError, "")
  }

  function test_dismissing_the_result_hides_it_and_leaves_the_store_ready() {
    var app = startedJob(); if (!app) return
    var proc = app.milestones.specRunner.current
    proc.outText = '{"ok": true, "agent": "claude", "log": "/l/x.log", "exit_code": 0}'
    proc.exited(0)
    compare(app.milestones.jobVisible, true)
    app.milestones.dismissResult()
    compare(app.milestones.jobVisible, false)
    specFixture(app)
    app.milestones.startFromSpec()
    compare(app.milestones.jobState, "running")
    compare(app.milestones.jobVisible, true)
  }

  function test_a_running_job_cannot_be_dismissed() {
    var app = startedJob(); if (!app) return
    app.milestones.dismissResult()
    compare(app.milestones.jobVisible, true)
    compare(app.milestones.jobState, "running")
  }

  // ---- project changes

  // The job belongs to the project it was started for; another project's panel
  // must not show it, and must not be able to end it either.
  function test_switching_project_hides_the_job_but_keeps_it_running() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    specFixture(app)
    app.milestones.startFromSpec()
    var proc = app.milestones.specRunner.current
    app.projects.chooseProject(pB)
    compare(app.milestones.jobState, "running", "the job is not cancelled")
    compare(proc.running, true, "the helper keeps running")
    compare(app.milestones.jobVisible, false, "but it is not this project's job")
    app.projects.chooseProject(pA)
    compare(app.milestones.jobVisible, true, "back where it belongs")
  }

  // The class of bug this store must never have: the newest run's exit always
  // ends the job -- and it ends it with the truth, whatever project the user
  // happens to be looking at. The board of a project the job is not about is
  // never refreshed for it.
  function test_a_run_that_ends_after_a_project_switch_is_recorded_truthfully() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.board.applyTreeData(cards(2))
    specFixture(app)
    app.milestones.startFromSpec()
    var proc = app.milestones.specRunner.current
    var spy = spyOn(app.milestones, "boardRefreshRequested")
    app.projects.chooseProject(pB)
    app.board.applyTreeData(cards(40))
    proc.outText = '{"ok": true, "agent": "claude", "log": "/l/x.log", "exit_code": 0}'
    proc.exited(0)
    verify(app.milestones.jobState !== "running", "the job must not stay running")
    compare(app.milestones.jobState, "done", "a run that succeeded is not a failure")
    compare(app.milestones.jobError, "")
    compare(app.milestones.jobLog, "/l/x.log")
    compare(app.milestones.specRunner.busy, false)
    compare(app.milestones.jobVisible, false, "but it is not this project's job")
    compare(spy.count, 0, "and this project's board is not refreshed for it")
    // The count could only be taken from another project's board, so the job
    // claims none -- and, being frozen, never starts counting one later.
    compare(app.milestones.cardsCountKnown, false)
    app.projects.chooseProject(pA)
    app.board.applyTreeData(cards(6))
    compare(app.milestones.jobVisible, true)
    compare(app.milestones.jobState, "done")
    compare(app.milestones.cardsCreated, 0, "no card count is invented for it")
    compare(app.milestones.cardsCountKnown, false)
  }

  // The defect this guards: a job that ended away from its own board used to
  // leave the count live, so every later board change inflated its result.
  function test_a_job_that_ended_elsewhere_never_counts_a_later_board() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.board.applyTreeData(cards(2))
    specFixture(app)
    app.milestones.startFromSpec()
    var proc = app.milestones.specRunner.current
    app.projects.chooseProject(pB)
    proc.outText = '{"ok": true, "agent": "claude", "log": "/l/x.log", "exit_code": 0}'
    proc.exited(0)
    app.projects.chooseProject(pA)
    app.board.applyTreeData(cards(30))
    compare(app.milestones.cardsCreated, 0, "a finished job's result never moves again")
    compare(app.milestones.cardsCountKnown, false)
  }

  // Ending on its own board is the normal case: the count is taken there and
  // frozen, and a later refetch cannot change it.
  function test_a_job_that_ended_at_home_freezes_the_count_it_took() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.board.applyTreeData(cards(2))
    specFixture(app)
    app.milestones.startFromSpec()
    app.board.applyTreeData(cards(5))
    var proc = app.milestones.specRunner.current
    proc.outText = '{"ok": true, "agent": "claude", "log": "/l/x.log", "exit_code": 0}'
    proc.exited(0)
    compare(app.milestones.cardsCountKnown, true)
    compare(app.milestones.cardsCreated, 3)
    app.board.applyTreeData(cards(12))
    compare(app.milestones.cardsCreated, 3, "later cards are not this job's")
  }

  // Nothing is stuck afterwards either: the next project can start its own job.
  function test_a_run_that_ended_elsewhere_does_not_block_the_next_job() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    specFixture(app)
    app.milestones.startFromSpec()
    var proc = app.milestones.specRunner.current
    app.projects.chooseProject(pB)
    proc.exited(0)
    specFixture(app)
    app.milestones.startFromSpec()
    compare(app.milestones.jobState, "running")
    compare(app.milestones.specRunner.current.command[2], "/home/u/b")
    compare(app.milestones.jobVisible, true)
  }

  // A run cancelled from another project's panel is impossible (the indicator
  // is not shown there), and the store refuses it all the same.
  function test_the_job_refresh_is_scoped_to_its_own_project_on_cancel() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    specFixture(app)
    app.milestones.startFromSpec()
    var spy = spyOn(app.milestones, "boardRefreshRequested")
    app.milestones.cancelJob()
    compare(spy.count, 1, "its own project's board is refreshed")
  }

  // Coming back before the run ends is not staleness: the result is the job's
  // own and is applied normally.
  function test_a_job_survives_a_round_trip_through_another_project() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    specFixture(app)
    app.milestones.startFromSpec()
    var proc = app.milestones.specRunner.current
    app.projects.chooseProject(pB)
    app.projects.chooseProject(pA)
    compare(app.milestones.jobState, "running")
    proc.outText = '{"ok": true, "agent": "claude", "log": "/l/x.log", "exit_code": 0}'
    proc.exited(0)
    compare(app.milestones.jobState, "done")
    compare(app.milestones.jobVisible, true)
  }

  function test_switching_project_clears_the_dialog_but_not_the_job() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    specFixture(app)
    app.milestones.title = "t"
    app.milestones.description = "d"
    app.milestones.dialogError = "boom"
    app.milestones.startFromSpec()
    app.milestones.openDialog()
    app.projects.chooseProject(pB)
    compare(app.milestones.dialogOpen, false)
    compare(app.milestones.mode, "manual")
    compare(app.milestones.title, "")
    compare(app.milestones.description, "")
    compare(app.milestones.selectedSpec, "")
    compare(app.milestones.dialogError, "")
    compare(app.milestones.jobState, "running")
  }

  function test_clearing_the_project_clears_the_dialog_too() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    app.milestones.title = "t"
    app.projects.clearSelection()
    compare(app.milestones.dialogOpen, false)
    compare(app.milestones.title, "")
  }

  // ---- the counter

  function test_the_created_card_count_follows_the_board_and_never_goes_negative() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.board.applyTreeData(cards(4))
    specFixture(app)
    app.milestones.startFromSpec()
    compare(app.milestones.cardsCreated, 0)
    app.board.applyTreeData(cards(6))
    compare(app.milestones.cardsCreated, 2)
    app.board.applyTreeData(cards(1))
    compare(app.milestones.cardsCreated, 0, "a shrinking board never shows a negative count")
  }

  // The board refresh App connects the store to: a manual create and the job's
  // end both ask for it.
  function test_app_refetches_the_board_when_the_store_asks() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    var spy = spyOn(app.board, "errored")
    var before = spy.count
    app.milestones.boardRefreshRequested()
    verify(spy.count > before, "App refetches the board")
  }
}
