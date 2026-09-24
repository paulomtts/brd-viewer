// tests/ui/tst_issues_flow.qml
// What the panel does around the extras store: the section change, Ctrl+5, the
// cursor, the view mode, the breadcrumbs, following a blocks link and coming
// back. The parsing and the filters are tested in tests/core/stores/.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "IssuesFlow"
  when: windowShown
  visible: true
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property string exportLine: JSON.stringify({ ok: true, data: {
    issues: [{ id: "i1", title: "Broken build", body: "b", status: "open", close_reason: null,
               blocks: ["m1"], created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-24T10:00:00+00:00" }],
    comments: [], refs: [] } })

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA])
    p.app.board.applyTreeData([{ id: "m1", title: "Milestone", status: "blocked", description: "d",
                                 blocked_by: ["i1"], children: [] }])
    p.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    // Selecting the project fires the board fetch and with it a `brd export`
    // that must not run here: it is stopped, its late reply is disarmed with a
    // stale guard, and the loading flag is put back, so every test starts from
    // a settled store (the Task 4/5 fixture pattern).
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.extras.applyExportResult(exportLine, 0)
    return p
  }
  function labels(crumbs) { return crumbs.map(function(c) { return c.label }).join(" > ") }

  function test_ctrl_5_opens_the_issues_section() {
    var p = make(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_5 }), true)
    compare(p.app.nav.viewMode, "issues")
    compare(p.app.nav.section, "issues")
    compare(p.app.nav.sectionTitle, "Issues")
    compare(labels(p.navigator.crumbs), "Issues")
  }

  function test_the_section_does_not_refetch_the_export_by_itself() {
    var p = make(); if (!p) return
    p.app.extras.exportProc.running = false
    p.navigator.showSection("issues")
    compare(p.app.extras.exportProc.running, false, "the export follows the board, not the section")
  }

  function test_the_current_list_and_the_cursor_follow_the_filtered_issues() {
    var p = make(); if (!p) return
    p.navigator.showSection("issues")
    compare(p.navigator.currentList().length, 1)
    p.app.nav.cursorIndex = 0
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "issue")
    compare(p.app.extras.selectedIssueId, "i1")
    compare(labels(p.navigator.crumbs), "Issues > Broken build")
    compare(p.navigator.currentList().length, 1, "the detail's link rows are the cursor's list")
  }

  function test_following_a_blocked_card_and_coming_back() {
    var p = make(); if (!p) return
    p.navigator.showSection("issues")
    p.navigator.openIssue("i1")
    p.app.nav.cursorIndex = 0
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, "m1")
    compare(p.app.nav.section, "issues", "the card still belongs to the Issues section")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "issues", "a card opened from an issue returns to the Issues list")
  }

  function test_escape_and_the_left_arrow_leave_an_open_issue() {
    var p = make(); if (!p) return
    p.navigator.showSection("issues")
    p.navigator.openIssue("i1")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "issues")
    compare(p.app.extras.selectedIssueId, "")
    p.navigator.openIssue("i1")
    p.shortcuts.handleMove(-1, 0)
    compare(p.app.nav.viewMode, "issues")
  }

  function test_a_crumb_click_goes_back_to_the_list() {
    var p = make(); if (!p) return
    p.navigator.showSection("issues")
    p.navigator.openIssue("i1")
    p.navigator.activateCrumb(0)
    compare(p.app.nav.viewMode, "issues")
  }

  function test_an_open_issue_that_leaves_the_export_falls_back_to_the_list() {
    var p = make(); if (!p) return
    p.navigator.showSection("issues")
    p.navigator.openIssue("i1")
    p.app.extras.applyExportResult(JSON.stringify({ ok: true, data: { issues: [], comments: [], refs: [] } }), 0)
    compare(p.app.nav.viewMode, "issues")
    compare(p.app.extras.selectedIssueId, "")
  }

  function test_the_search_field_and_the_refresh_button_serve_the_section() {
    var p = make(); if (!p) return
    p.navigator.showSection("issues")
    p.app.nav.searchQuery = "broken"
    compare(p.navigator.currentList().length, 1)
    p.app.nav.searchQuery = "zzz"
    compare(p.navigator.currentList().length, 0)
    p.app.nav.searchQuery = ""
    p.app.board.treeProc.running = false
    p.app.board.fetchBoard()
    compare(p.app.extras.exportProc.running, true, "Refresh refetches the extras with the board")
  }

  function test_a_project_switch_leaves_the_issues_section_clean() {
    var p = make(); if (!p) return
    p.navigator.showSection("issues")
    p.navigator.openIssue("i1")
    p.app.projects.applyProjectsList([])
    compare(p.app.extras.issues.length, 0)
    compare(p.app.extras.selectedIssueId, "")
  }

  // The keyboard reaches the Issue detail like the card detail does, and the
  // section's modals still swallow the chords.
  function test_the_issue_detail_is_a_keyboard_view_and_the_modals_still_block() {
    var p = make(); if (!p) return
    p.navigator.showSection("issues")
    compare(p.focusItem.objectName, "searchField")
    p.navigator.openIssue("i1")
    compare(p.focusItem.objectName, "keyCatcher")
    p.app.milestones.openDialog()
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_5 }), false)
    compare(p.app.nav.viewMode, "issue", "the dialog swallows the chord")
    p.shortcuts.closeRequested()
    compare(p.app.milestones.dialogOpen, false)
    compare(p.app.nav.viewMode, "issue", "Escape closed the dialog, not the issue")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "issues")
  }
}
