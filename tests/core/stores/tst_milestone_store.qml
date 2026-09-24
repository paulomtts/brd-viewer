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

  // The dialog, with the default agent already checked and usable.
  function specFixture(app) {
    app.milestones.openDialog()
    var d = app.milestones.describeRunner.current
    d.outText = agentOk
    d.exited(0)
    app.milestones.mode = "spec"
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

  function test_opening_the_dialog_clears_it_and_checks_the_default_agent() {
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
    var proc = app.milestones.describeRunner.current
    verify(proc, "the agent check runs")
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/milestones/run-setup-milestone.py")
    compare(proc.command[2], "--describe")
    compare(proc.command.length, 3)
  }

  function test_the_agent_check_becomes_the_agent_message() {
    var app = make(); if (!app) return
    app.milestones.openDialog()
    var proc = app.milestones.describeRunner.current
    proc.outText = agentOk
    proc.exited(0)
    compare(app.milestones.agentInfo.agent, "claude")
    compare(app.milestones.agentMessage, "")
    app.milestones.openDialog()
    proc = app.milestones.describeRunner.current
    proc.outText = agentNone
    proc.exited(0)
    compare(app.milestones.agentMessage, "No default agent is set.")
    app.milestones.openDialog()
    proc = app.milestones.describeRunner.current
    proc.outText = agentMissing
    proc.exited(0)
    compare(app.milestones.agentMessage, "codex is not installed.")
  }

  // The answer belongs to the project it was asked for: after a switch it must
  // not fill in the agent for the project the user is looking at now, even when
  // it is the only check that has ever run.
  function test_an_agent_check_from_the_previous_project_is_ignored() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    var stale = app.milestones.describeRunner.current
    app.projects.chooseProject(pB)
    stale.outText = agentOk
    stale.exited(0)
    compare(app.milestones.agentInfo, null, "the old project's answer is dropped")
    compare(app.milestones.agentMessage, "No default agent is set.")
    app.milestones.mode = "spec"
    app.milestones.selectedSpec = "docs/specs/one.md"
    app.milestones.startFromSpec()
    verify(!app.milestones.specRunner.current, "and it cannot start a run for the new project")
  }

  // A check the user is still waiting for is not stale: coming back to the
  // project it was asked for still fills the agent in.
  function test_an_agent_check_survives_a_round_trip_through_another_project() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    app.milestones.openDialog()
    var proc = app.milestones.describeRunner.current
    app.projects.chooseProject(pB)
    app.projects.chooseProject(pA)
    proc.outText = agentOk
    proc.exited(0)
    compare(app.milestones.agentMessage, "")
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
    var d = app.milestones.describeRunner.current
    d.outText = agentMissing
    d.exited(0)
    app.milestones.mode = "spec"
    app.milestones.selectedSpec = "docs/specs/one.md"
    app.milestones.startFromSpec()
    verify(!app.milestones.specRunner.current, "nothing was run")
    compare(app.milestones.jobState, "idle")
    compare(app.milestones.dialogOpen, true)
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
  // ends the job, even when its result is dropped because the project changed.
  function test_a_run_that_ends_after_a_project_switch_never_leaves_the_job_stuck() {
    var app = make(); if (!app) return
    app.projects.chooseProject(pA)
    specFixture(app)
    app.milestones.startFromSpec()
    var proc = app.milestones.specRunner.current
    app.projects.chooseProject(pB)
    proc.outText = '{"ok": true, "agent": "claude", "log": "/l/x.log", "exit_code": 0}'
    proc.exited(0)
    verify(app.milestones.jobState !== "running", "the job must not stay running")
    compare(app.milestones.jobState, "failed", "a lost result is not a success")
    compare(app.milestones.specRunner.busy, false)
    compare(app.milestones.jobVisible, false, "and it is still not this project's job")
    // and the new project can start its own job right away
    specFixture(app)
    app.milestones.startFromSpec()
    compare(app.milestones.jobState, "running")
    compare(app.milestones.specRunner.current.command[2], "/home/u/b")
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
