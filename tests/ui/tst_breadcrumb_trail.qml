// tests/ui/tst_breadcrumb_trail.qml
// ui/Navigator.qml's breadcrumb trail: the crumbs every view shows, and what
// clicking one does (back to the list, or open an ancestor card).
// REAL core/stores App -- no bespoke mocks.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "BreadcrumbTrail"
  when: windowShown
  width: 400; height: 400

  Component { id: flickC; Flickable { width: 200; height: 100; contentWidth: 200; contentHeight: 1000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "docs/specs/Design Doc.md", "title": "Design", "size": 200, "category": "specs"},' +
    '{"path": "docs/untitled.md", "size": 10}], "truncated": false}'
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-a/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "d", "type": "user", "size": 10, "indexed": true}]}'
  // i1 blocks "m1", the board's top-level card, so a link row of the issue
  // detail opens a card whose ancestors the trail can list.
  property string exportLine: JSON.stringify({ ok: true, data: {
    issues: [{ id: "i1", title: "Broken build", body: "b", status: "open", close_reason: null,
               blocks: ["m1"], created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-24T10:00:00+00:00" }],
    comments: [], refs: [] } })

  function card(id, title, status, children) {
    return { id: id, title: title, status: status, description: "d", blocked_by: [], children: children || [] }
  }

  function make(withProject) {
    var appC = Qt.createComponent("../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var navC = Qt.createComponent("../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    var flick = createTemporaryObject(flickC, tc)
    var n = navC.createObject(tc, { app: app, flick: flick, documentsEnabled: true, actions: ({
      focusForView: function() {},
      scrollToTop: function() { flick.contentY = 0 },
      scrollBy: function(px) { flick.contentY = flick.contentY + px },
      centerOnGraphNode: function(id) {}
    }) })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    if (withProject !== false) app.projects.applyProjectsList([pA])
    return n
  }

  function boarded() {
    var n = make(); if (!n) return null
    n.app.board.applyTreeData([card("m1", "Milestone One", "todo", [card("s1", "Story One", "todo", [card("t1", "Subtask One", "todo")])])])
    wait(50)
    return n
  }

  function labels(n) {
    return n.crumbs.map(function(c) { return c.label }).join(" › ")
  }
  function clickable(n) {
    return n.crumbs.map(function(c) { return c.clickable ? "1" : "0" }).join("")
  }

  function test_without_a_project_the_trail_is_just_the_panels_name() {
    var n = make(false); if (!n) return
    compare(labels(n), "Project Manager")
    compare(clickable(n), "0")
  }

  function test_a_list_view_is_a_single_crumb_naming_its_section() {
    var n = boarded(); if (!n) return
    compare(labels(n), "Board")
    n.showSection("graph")
    compare(labels(n), "Graph")
    n.showSection("documents")
    compare(labels(n), "Documents")
    n.showSection("memories")
    compare(labels(n), "Memories")
    compare(clickable(n), "0")
  }

  function test_a_card_opened_from_the_board_lists_its_ancestors() {
    var n = boarded(); if (!n) return
    n.openCard("t1")
    compare(n.app.nav.viewMode, "entry")
    compare(labels(n), "Board › Milestone One › Story One › Subtask One")
    compare(clickable(n), "1110")
  }

  function test_a_top_level_card_has_only_its_section_before_it() {
    var n = boarded(); if (!n) return
    n.openCard("m1")
    compare(labels(n), "Board › Milestone One")
    compare(clickable(n), "10")
  }

  function test_a_card_opened_from_the_graph_starts_at_the_graph() {
    var n = boarded(); if (!n) return
    n.showSection("graph")
    n.openCard("s1")
    compare(labels(n), "Graph › Milestone One › Story One")
  }

  function test_an_open_document_shows_its_title_and_falls_back_to_the_file_name() {
    var n = boarded(); if (!n) return
    n.showSection("documents")
    n.app.docs.applyDocsResult(docList, 0)
    n.openDoc("docs/specs/Design Doc.md")
    compare(labels(n), "Documents › Design")
    compare(clickable(n), "10")
    n.goBack()
    n.openDoc("docs/untitled.md")
    compare(labels(n), "Documents › untitled.md")
  }

  function test_an_open_note_shows_its_name() {
    var n = boarded(); if (!n) return
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.openMemory("user_role.md")
    compare(labels(n), "Memories › Role")
    compare(clickable(n), "10")
  }

  function test_the_section_crumb_goes_back_the_way_the_back_action_did() {
    var n = boarded(); if (!n) return
    n.app.nav.cursorIndex = 0
    n.openCard("s1")
    n.activateCrumb(0)
    compare(n.app.nav.viewMode, "board")
    compare(n.app.nav.cursorIndex, 0)
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.openMemory("user_role.md")
    n.activateCrumb(0)
    compare(n.app.nav.viewMode, "memories")
  }

  function test_the_section_crumb_of_a_dirty_note_keeps_the_unsaved_draft() {
    var n = boarded(); if (!n) return
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.openMemory("user_role.md")
    n.app.memories.setMemoryText("body")
    n.app.memories.startMemoryEdit()
    n.app.memories.memoryDraft = "body and more"
    n.activateCrumb(0)
    compare(n.app.nav.viewMode, "memory", "the dirty draft keeps the note open")
    compare(n.app.memories.memoryEditing, true)
  }

  function test_an_ancestor_crumb_opens_that_card() {
    var n = boarded(); if (!n) return
    n.openCard("t1")
    n.activateCrumb(2)
    compare(n.app.board.selectedCardId, "s1")
    compare(n.app.nav.viewMode, "entry")
    compare(labels(n), "Board › Milestone One › Story One")
    n.activateCrumb(1)
    compare(n.app.board.selectedCardId, "m1")
  }

  function issued() {
    var n = boarded(); if (!n) return null
    n.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    if (n.app.extras.exportProc) {
      n.app.extras.exportProc.running = false
      n.app.extras.exportProc.launchGuard = "stale"
    }
    n.app.extras.extrasLoading = false
    n.app.extras.applyExportResult(exportLine, 0)
    n.showSection("issues")
    return n
  }

  function test_an_open_issue_shows_its_title_and_the_section_goes_back() {
    var n = issued(); if (!n) return
    compare(labels(n), "Issues")
    n.openIssue("i1")
    compare(labels(n), "Issues › Broken build")
    compare(clickable(n), "10")
    n.activateCrumb(0)
    compare(n.app.nav.viewMode, "issues")
  }

  // A card reached from an issue keeps the Issues trail, and Back returns to
  // the Issues list rather than the Board.
  function test_a_card_opened_from_an_issue_starts_at_the_issues_section() {
    var n = issued(); if (!n) return
    n.openIssue("i1")
    n.openIssueLink("m1")
    compare(n.app.nav.viewMode, "entry")
    compare(labels(n), "Issues › Milestone One")
    n.goBack()
    compare(n.app.nav.viewMode, "issues")
  }

  function test_the_current_crumb_does_nothing() {
    var n = boarded(); if (!n) return
    n.openCard("m1")
    n.activateCrumb(1)
    compare(n.app.nav.viewMode, "entry")
    compare(n.app.board.selectedCardId, "m1")
    n.activateCrumb(9)
    compare(n.app.nav.viewMode, "entry")
  }
}
