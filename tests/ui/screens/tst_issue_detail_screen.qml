// tests/ui/screens/tst_issue_detail_screen.qml
// ui/screens/IssueDetailScreen.qml on its own: the body, the close reason, the
// navigable blocks/refs rows and the comments. REAL App and REAL Navigator.
import QtQuick
import QtTest
import "../../helpers/find.js" as H

TestCase {
  id: tc
  name: "IssueDetailScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  // The real `brd export` shape: an exported issue carries no `blocks` and no
  // `kind`, and the issue->card blocking relation survives only as `blocked_by`
  // on the nested `cards[]` tree (Task 1's finding). `ghost` is a card of the
  // export that this board does not hold, so i1 blocks a card that cannot be
  // opened.
  property string exportLine: JSON.stringify({ ok: true, data: {
    cards: [{ id: "m1", title: "Milestone", status: "blocked", blocked_by: ["i1"], children: [
                { id: "ghost", title: "Ghost", status: "todo", blocked_by: ["i1"], children: [] }] }],
    issues: [
      { id: "i1", title: "Broken build", body: "It **fails**.", status: "open", close_reason: null,
        created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-24T10:00:00+00:00" },
      { id: "i2", title: "Old bug", body: "", status: "closed", close_reason: "resolved",
        created_at: "2026-09-10T10:00:00+00:00", updated_at: "2026-09-11T10:00:00+00:00" }],
    comments: [{ id: "k", entity_id: "i1", author: "paulo", body: "looking", created_at: "2026-09-24T09:00:00+00:00" }],
    refs: [{ src_id: "i1", dst_id: "i2", origin: "explicit" },
           { src_id: "m1", dst_id: "i1", origin: "explicit" }] } })

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var appC = Qt.createComponent("../../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(host, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA])
    app.board.applyTreeData([{ id: "m1", title: "Milestone", status: "blocked", description: "d",
                               blocked_by: ["i1"], children: [] }])
    app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" },
                              { id: "i2", title: "Old bug", status: "closed" }])
    var navC = Qt.createComponent("../../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    var flick = flickC.createObject(host)
    var nav = navC.createObject(host, { app: app, flick: flick, actions: ({
      focusForView: function() {}, scrollToTop: function() { flick.contentY = 0 },
      scrollBy: function(px) { flick.contentY = flick.contentY + px },
      centerOnGraphNode: function(id) {} }) })
    var sC = Qt.createComponent("../../../ui/screens/IssueDetailScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: nav })
    // Selecting the project fires the board fetch, and with it a real `brd
    // export` that cannot run here. It is stopped, its late reply is disarmed
    // with a stale guard (it would otherwise wipe the store in the middle of a
    // synthetic click, which spins the event loop), and the loading flag is put
    // back, so every test starts from a settled store.
    if (app.extras.exportProc) {
      app.extras.exportProc.running = false
      app.extras.exportProc.launchGuard = "stale"
    }
    app.extras.extrasLoading = false
    app.extras.applyExportResult(exportLine, 0)
    return { app: app, screen: screen, nav: nav }
  }

  function open(s, id) { s.app.extras.openIssue(id); s.app.nav.viewMode = "issue" }

  function test_the_header_body_and_comments_are_shown() {
    var s = make(); if (!s) return
    open(s, "i1")
    compare(s.screen.visible, true)
    compare(H.find(s.screen, "issueDetailTitle").text, "Broken build")
    compare(H.find(s.screen, "issueDetailStatus").text, "Open")
    compare(H.find(s.screen, "issueDetailBlocksLabel").text, "blocks 2 cards")
    compare(H.find(s.screen, "issueDetailReason").visible, false)
    compare(H.find(s.screen, "issueDetailBody").text, "It **fails**.")
    compare(H.find(s.screen, "issueComments").comments.length, 1)
    compare(H.find(s.screen, "commentBody0").text, "looking")
  }

  function test_a_closed_issue_shows_its_reason_and_an_empty_body_message() {
    var s = make(); if (!s) return
    open(s, "i2")
    compare(H.find(s.screen, "issueDetailStatus").text, "Closed")
    compare(H.find(s.screen, "issueDetailReason").visible, true)
    compare(H.find(s.screen, "issueDetailReason").text, "Closed: resolved")
    compare(H.find(s.screen, "issueDetailBody").text, "No description.")
    compare(H.find(s.screen, "issueDetailBlocksLabel").visible, false)
  }

  function test_blocked_cards_are_listed_and_navigable_dangling_ones_are_not() {
    var s = make(); if (!s) return
    open(s, "i1")
    wait(50)
    compare(H.find(s.screen, "issueDetailBlocks0").visible, true)
    compare(H.find(s.screen, "issueDetailBlocks1"), null, "an id that is not in this board is left out")
    mouseClick(H.find(s.screen, "issueDetailBlocks0"))
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "m1")
  }

  function test_refs_and_referenced_by_open_cards_and_issues() {
    var s = make(); if (!s) return
    open(s, "i1")
    wait(50)
    mouseClick(H.find(s.screen, "issueDetailRef0"))
    compare(s.app.extras.selectedIssueId, "i2", "a ref to an issue opens that issue")
    open(s, "i1")
    wait(50)
    mouseClick(H.find(s.screen, "issueDetailReferencedBy0"))
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "m1")
  }

  function test_hovering_a_link_moves_the_cursor_through_the_navigator() {
    var s = make(); if (!s) return
    open(s, "i1")
    wait(50)
    var link = H.find(s.screen, "issueDetailRef0")
    mouseMove(link, link.width / 2, link.height / 2)
    compare(s.app.nav.cursorIndex, s.app.extras.linkIndex("ref", "i2"))
  }

  function test_the_screen_is_hidden_without_an_open_issue() {
    var s = make(); if (!s) return
    compare(s.screen.visible, false)
    open(s, "i1")
    s.app.extras.applyExportResult(JSON.stringify({ ok: true, data: { issues: [], comments: [], refs: [] } }), 0)
    compare(s.screen.visible, false)
  }
}
