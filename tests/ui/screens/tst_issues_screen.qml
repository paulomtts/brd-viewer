// tests/ui/screens/tst_issues_screen.qml
// ui/screens/IssuesScreen.qml on its own: the rows it renders from the extras
// store, the status chips it toggles, and the click/hover it forwards.
// REAL core/stores App and REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest
import "../../helpers/find.js" as H

TestCase {
  id: tc
  name: "IssuesScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property string exportLine: JSON.stringify({ ok: true, data: { refs: [],
    comments: [{ id: "k", entity_id: "i1", author: "p", body: "b", created_at: "2026-09-24T09:00:00+00:00" }],
    issues: [
      { id: "i1", title: "Broken build", body: "It fails.", status: "open", close_reason: null,
        blocks: ["m1"], created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-24T10:00:00+00:00" },
      { id: "i2", title: "Old bug", body: "", status: "closed", close_reason: "resolved", blocks: [],
        created_at: "2026-09-10T10:00:00+00:00", updated_at: "2026-09-11T10:00:00+00:00" }] } })

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var appC = Qt.createComponent("../../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(host, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA])
    var navC = Qt.createComponent("../../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    var flick = flickC.createObject(host)
    var nav = navC.createObject(host, { app: app, flick: flick, actions: ({
      focusForView: function() {}, scrollToTop: function() { flick.contentY = 0 },
      scrollBy: function(px) { flick.contentY = flick.contentY + px },
      centerOnGraphNode: function(id) {} }) })
    var sC = Qt.createComponent("../../../ui/screens/IssuesScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: nav })
    app.nav.viewMode = "issues"
    // Selecting the project fires the board fetch, and with it a real `brd
    // export` that cannot run here. It is stopped, its late reply is disarmed
    // with a stale guard (it would otherwise wipe the store in the middle of a
    // synthetic click, which spins the event loop), and the loading flag is put
    // back, so every test starts from a settled store.
    app.extras.exportProc.running = false
    app.extras.exportProc.launchGuard = "stale"
    app.extras.extrasLoading = false
    return { app: app, screen: screen, nav: nav }
  }

  function test_the_rows_show_status_title_blocks_and_comment_count() {
    var s = make(); if (!s) return
    s.app.extras.applyExportResult(exportLine, 0)
    compare(H.find(s.screen, "issueRowBadge0").text, "Open")
    compare(H.find(s.screen, "issueRowBlocks0").text, "blocks 1 card")
    compare(H.find(s.screen, "issueRowComments0").text, "1 comment")
    compare(H.find(s.screen, "issueRowBadge1").text, "Closed")
    compare(H.find(s.screen, "issueRowBlocks1").visible, false)
    compare(H.find(s.screen, "issueRowComments1").visible, false)
  }

  function test_the_chips_carry_the_counts_and_toggle_the_filter() {
    var s = make(); if (!s) return
    s.app.extras.applyExportResult(exportLine, 0)
    wait(50)
    var chip = H.find(s.screen, "issueChipclosed")
    verify(chip, "the Closed chip")
    compare(chip.text, "Closed 1")
    mouseClick(chip)
    compare(s.app.extras.issueStatus, "closed")
    compare(s.app.extras.filteredIssues.length, 1)
    compare(H.find(s.screen, "issueRow1"), null, "the filtered-out row is gone")
  }

  function test_clicking_a_row_opens_that_issue() {
    var s = make(); if (!s) return
    s.app.extras.applyExportResult(exportLine, 0)
    wait(50)
    mouseClick(H.find(s.screen, "issueRow0"))
    compare(s.app.nav.viewMode, "issue")
    compare(s.app.extras.selectedIssueId, "i1")
  }

  function test_hovering_a_row_moves_the_cursor_through_the_navigator() {
    var s = make(); if (!s) return
    s.app.extras.applyExportResult(exportLine, 0)
    wait(50)
    var row = H.find(s.screen, "issueRow1")
    mouseMove(row, row.width / 2, row.height / 2)
    compare(s.app.nav.cursorIndex, 1)
  }

  function test_the_empty_and_filtered_wordings() {
    var s = make(); if (!s) return
    compare(H.find(s.screen, "issuesMessage").text, "No issues in this project.")
    s.app.extras.applyExportResult(exportLine, 0)
    s.app.nav.searchQuery = "zzz"
    compare(H.find(s.screen, "issuesMessage").text, "No issues match “zzz”.")
    s.app.nav.searchQuery = ""
    s.app.extras.toggleIssueStatus("closed")
    s.app.extras.applyExportResult(JSON.stringify({ ok: true, data: { issues: [
      { id: "i1", title: "Only open", status: "open", blocks: [] }], comments: [], refs: [] } }), 0)
    compare(H.find(s.screen, "issuesMessage").text, "No Closed issues.")
  }

  function test_the_screen_is_hidden_outside_its_section() {
    var s = make(); if (!s) return
    compare(s.screen.visible, true)
    s.app.nav.viewMode = "board"
    compare(s.screen.visible, false)
  }
}
