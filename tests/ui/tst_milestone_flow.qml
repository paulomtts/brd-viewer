// tests/ui/tst_milestone_flow.qml
// What the panel does around MilestoneStore: the ＋ New milestone button in the
// Board toolbar, the running job's indicator taking its place (and its clock),
// the dialog hosted over the panel -- focus, Escape, blocked shortcuts -- and
// the documents listing the spec picker needs. The state machine itself is
// tested in tests/core/stores/tst_milestone_store.qml, the dialog's looks in
// tests/ui/components/tst_new_milestone_dialog.qml.
import QtQuick
import QtTest
import "../helpers/find.js" as H

TestCase {
  id: tc
  name: "MilestoneFlow"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string agentOk: '{"agent": "claude", "supported": true, "restricted": true, "note": "reads and brd only", "installed": true}'
  property string agentNone: '{"agent": "", "supported": false, "restricted": false, "note": "", "installed": false}'
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "docs/architecture/a.md", "title": "Arch", "size": 1, "category": "architecture"},' +
    '{"path": "docs/specs/s.md", "title": "Spec", "size": 1, "category": "specs"}], "truncated": false}'

  function makePanel(projects) {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList(projects)
    wait(50)
    return p
  }

  function make() { return makePanel([pA]) }

  function card(id) { return { id: id, title: "c" + id, status: "todo", children: [] } }
  function cards(n) {
    var out = []
    for (var i = 0; i < n; i++) out.push(card("c" + i))
    return out
  }

  // The dialog with the agent already answered for, ready to start a run.
  function specReady(p) {
    p.app.milestones.openDialog()
    var d = p.app.milestones.describeRunner.current
    verify(d, "the agent check ran")
    d.outText = agentOk
    d.exited(0)
    p.app.docs.applyDocsResult(docList, 0)
    wait(50)
    return p
  }

  function runningJob() {
    var p = make(); if (!p) return null
    specReady(p)
    p.app.milestones.selectedSpec = "docs/specs/s.md"
    p.app.milestones.startFromSpec()
    wait(50)
    return p
  }

  // ---- the toolbar button

  function test_the_board_toolbar_offers_a_new_milestone_button_that_opens_the_dialog() {
    var p = make(); if (!p) return
    var button = H.find(p, "newMilestoneButton")
    verify(button, "the New milestone button")
    compare(button.visible, true)
    compare(button.bordered, true)
    compare(String(button.text), "＋ New milestone")
    mouseClick(button, button.width / 2, button.height / 2)
    compare(p.app.milestones.dialogOpen, true)
    var dialog = H.find(p, "newMilestoneDialog")
    verify(dialog, "the dialog")
    compare(dialog.visible, true)
  }

  function test_the_new_milestone_button_only_shows_in_the_board_list_with_a_project() {
    var empty = makePanel([]); if (!empty) return
    compare(H.find(empty, "newMilestoneButton").visible, false, "no project, no button")
    var p = make(); if (!p) return
    compare(H.find(p, "newMilestoneButton").visible, true)
    p.navigator.showSection("memories")
    wait(50)
    compare(H.find(p, "newMilestoneButton").visible, false, "memories is not the board")
    p.navigator.showSection("board")
    wait(50)
    compare(H.find(p, "newMilestoneButton").visible, true)
    p.app.nav.viewMode = "entry"
    wait(50)
    compare(H.find(p, "newMilestoneButton").visible, false, "an open card is not the board list")
  }

  // ---- the job indicator

  function test_a_running_job_takes_the_buttons_place_and_can_be_cancelled() {
    var p = runningJob(); if (!p) return
    compare(p.app.milestones.jobState, "running")
    compare(H.find(p, "newMilestoneButton").visible, false, "the button steps aside")
    var indicator = H.find(p, "milestoneIndicator")
    verify(indicator, "the job indicator")
    compare(indicator.visible, true)
    compare(String(indicator.state), "running")
    compare(String(H.find(p, "milestoneStatus").text), "Creating milestone…")
    var cancel = H.find(p, "milestoneCancel")
    compare(cancel.visible, true)
    // The toolbar row is wider than the offscreen popup here, so the buttons
    // are driven by their signal (as the other panel flow tests do); the click
    // itself is covered in tests/ui/components/tst_milestone_job_indicator.qml.
    indicator.cancelRequested()
    compare(p.app.milestones.jobState, "failed")
    compare(p.app.milestones.jobError, "Cancelled.")
  }

  function test_the_indicator_clock_counts_the_run_up() {
    var p = runningJob(); if (!p) return
    var elapsed = H.find(p, "milestoneElapsed")
    verify(elapsed, "the elapsed time")
    compare(String(elapsed.text), "0:00", "it starts at zero")
    p.app.milestones.jobStartedAt = Date.now() - 65000
    tryCompare(elapsed, "text", "1:05", 3000)
  }

  function test_a_finished_job_reports_its_cards_and_refreshes_the_board() {
    var p = runningJob(); if (!p) return
    p.app.board.treeProc.running = false
    p.app.board.applyTreeData(cards(3))
    p.app.milestones.applyRunResult('{"ok": true, "agent": "claude", "log": "/l/agent.log", "exit_code": 0, "error": ""}',
      0, pA.root_path)
    wait(50)
    compare(p.app.milestones.jobState, "done")
    compare(String(H.find(p, "milestoneStatus").text), "Done")
    compare(String(H.find(p, "milestoneDetail").text), "3 cards created")
    compare(String(H.find(p, "milestoneLog").text), "/l/agent.log")
    compare(p.app.board.treeProc.running, true, "the board is refetched")
    compare(H.find(p, "milestoneElapsed").visible, false, "the clock stops mattering")
    compare(H.find(p, "milestoneDismiss").visible, true)
    H.find(p, "milestoneIndicator").dismissRequested()
    wait(50)
    compare(H.find(p, "milestoneIndicator").visible, false)
    compare(H.find(p, "newMilestoneButton").visible, true, "the button comes back")
  }

  function test_a_failed_job_shows_why() {
    var p = runningJob(); if (!p) return
    p.app.milestones.applyRunResult('{"ok": false, "agent": "claude", "log": "/l/a.log", "exit_code": 1, "error": "claude is not installed."}',
      1, pA.root_path)
    wait(50)
    compare(String(H.find(p, "milestoneStatus").text), "Failed")
    compare(String(H.find(p, "milestoneDetail").text), "claude is not installed.")
  }

  // The stub KeyboardPanel is a fixed-size Item; widening it is how a test
  // gets a realistic panel width. 200 sidebar + 12 margin = the toolbar's
  // left inset.
  function widen(p, contentWidth) {
    H.find(p, "mainPanel").width = contentWidth + 212
    wait(50)
    return H.find(p, "panelToolbar")
  }

  function fits(toolbar, name) {
    var item = H.find(toolbar, name)
    verify(item, name)
    compare(item.visible, true, name + " is on screen")
    var right = item.mapToItem(toolbar, 0, 0).x + item.width
    verify(right <= toolbar.width + 1, name + " ends at " + right + " within " + toolbar.width)
  }

  // A 512 px panel is the narrow end of what the shell gives us: the trail must
  // still be readable and nothing may hang off the edge.
  function test_the_toolbar_fits_a_narrow_panel() {
    var p = runningJob(); if (!p) return
    var toolbar = widen(p, 512)
    compare(toolbar.width, 512)
    var crumb = H.find(p, "crumb0")
    verify(crumb.width > 0, "the breadcrumb keeps a width (" + crumb.width + ")")
    fits(toolbar, "crumb0")
    fits(toolbar, "refreshButton")
    fits(toolbar, "milestoneIndicator")
    fits(toolbar, "milestoneCancel")
    var indicator = H.find(p, "milestoneIndicator")
    verify(indicator.mapToItem(toolbar, 0, 0).y >= crumb.mapToItem(toolbar, 0, 0).y + crumb.height,
      "the indicator has a row of its own under the trail")
    // The result state carries the longest text: a failure and its log path.
    p.app.milestones.applyRunResult('{"ok": false, "agent": "claude", "log": "/home/u/.local/state/omarchy-project-manager/agent-logs/20260924T101500Z-my-proj.log",' +
      ' "exit_code": 1, "error": "the agent exited with 1 before it finished writing the milestone; see the log for what it did"}',
      1, pA.root_path)
    wait(50)
    fits(toolbar, "milestoneDetail")
    fits(toolbar, "milestoneLog")
    fits(toolbar, "milestoneDismiss")
    fits(toolbar, "milestoneIndicator")
  }

  // Without a job the button shares the row with the trail and the refresh.
  function test_the_new_milestone_button_fits_a_narrow_panel() {
    var p = make(); if (!p) return
    var toolbar = widen(p, 512)
    verify(H.find(p, "crumb0").width > 0, "the breadcrumb keeps a width")
    fits(toolbar, "newMilestoneButton")
    fits(toolbar, "refreshButton")
  }

  // ---- the dialog over the panel

  // Every milestone comes from a spec, so opening the dialog is what needs the
  // listing -- and the agent check with it.
  function test_opening_the_dialog_fetches_the_documents_once() {
    var p = make(); if (!p) return
    p.app.milestones.openDialog()
    wait(50)
    compare(p.app.docs.docsLoading, true, "the documents listing is on its way")
    verify(p.app.milestones.describeRunner.current, "and the agent check ran")
    var lister = p.app.docs.lister.current
    p.app.docs.applyDocsResult(docList, 0)
    wait(50)
    p.app.milestones.cancelDialog()
    p.app.milestones.openDialog()
    wait(50)
    compare(p.app.docs.lister.current, lister, "documents already in hand are not fetched again")
  }

  function test_the_spec_list_offers_the_projects_documents_specs_first() {
    var p = make(); if (!p) return
    specReady(p)
    compare(String(H.find(p, "specRowTitle0").text), "Spec", "specs lead the list")
    var row = H.find(p, "specRow0")
    mouseClick(row, row.width / 2, 5)
    compare(p.app.milestones.selectedSpec, "docs/specs/s.md")
  }

  function test_ok_waits_for_the_agent_check_before_starting_a_run() {
    var p = make(); if (!p) return
    p.app.milestones.openDialog()
    p.app.docs.applyDocsResult(docList, 0)
    p.app.milestones.selectedSpec = "docs/specs/s.md"
    wait(50)
    var ok = H.find(p, "newMilestoneOk")
    compare(ok.enabled, false, "nothing is known about the agent yet")
    var describe = p.app.milestones.describeRunner.current
    describe.outText = agentOk
    describe.exited(0)
    wait(50)
    compare(ok.enabled, true)
    compare(String(H.find(p, "newMilestoneAgent").text), "Agent: claude")
    mouseClick(ok, ok.width / 2, ok.height / 2)
    compare(p.app.milestones.jobState, "running")
    compare(p.app.milestones.dialogOpen, false)
  }

  function test_an_agent_that_cannot_run_unattended_blocks_ok_and_says_so() {
    var p = make(); if (!p) return
    p.app.milestones.openDialog()
    var describe = p.app.milestones.describeRunner.current
    describe.outText = agentNone
    describe.exited(0)
    p.app.docs.applyDocsResult(docList, 0)
    p.app.milestones.selectedSpec = "docs/specs/s.md"
    wait(50)
    compare(H.find(p, "newMilestoneOk").enabled, false)
    compare(String(H.find(p, "newMilestoneAgentMessage").text), "No default agent is set.")
  }

  // The job runs for another project, so its indicator is nowhere in sight:
  // the dialog has to be the one to explain why Start is dead.
  function test_a_run_for_another_project_blocks_start_and_says_why() {
    var p = makePanel([pA, pB]); if (!p) return
    specReady(p)
    p.app.milestones.selectedSpec = "docs/specs/s.md"
    p.app.milestones.startFromSpec()
    p.navigator.chooseProject(pB)
    wait(50)
    compare(H.find(p, "milestoneIndicator").visible, false, "not this project's job")
    p.app.milestones.openDialog()
    var describe = p.app.milestones.describeRunner.current
    describe.outText = agentOk
    describe.exited(0)
    p.app.docs.applyDocsResult(docList, 0)
    p.app.milestones.selectedSpec = "docs/specs/s.md"
    wait(50)
    compare(String(H.find(p, "newMilestoneJobRunning").text), "A milestone run is already in progress.")
    compare(H.find(p, "newMilestoneJobRunning").visible, true)
    compare(H.find(p, "newMilestoneOk").enabled, false)
  }

  function test_the_dialog_takes_the_focus_and_blocks_the_global_shortcuts() {
    var p = make(); if (!p) return
    p.app.milestones.openDialog()
    wait(50)
    compare(p.focusItem.objectName, "newMilestoneSearch")
    compare(p.shortcuts.handleGlobalKey({ key: Qt.Key_4, modifiers: Qt.ControlModifier, accepted: false }), false)
    compare(p.app.nav.viewMode, "board", "the section shortcut did not fire")
    p.navigator.showSection("memories")
    compare(p.app.nav.viewMode, "board", "and neither does the navigator")
  }

  function test_escape_closes_the_dialog_rather_than_the_panel() {
    var p = make(); if (!p) return
    p.app.milestones.openDialog()
    wait(50)
    p.shortcuts.closeRequested()
    compare(p.app.milestones.dialogOpen, false)
    compare(p.opened, true, "the panel stays open")
  }
}
