// tests/ui/tst_navigator.qml
// ui/Navigator.qml on its own: the return-stack bookkeeping (cursor AND scroll
// position) around an open card, document and memory note, and the unsaved-draft
// guards on a section switch and a project switch. The panel-level flows keep
// their own tests; this one drives the navigator directly, with a real App and a
// real Flickable, and with Panel's UI-only effects supplied as plain functions.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "Navigator"
  when: windowShown
  width: 400; height: 700

  Component { id: flickC; Flickable { width: 200; height: 100; contentWidth: 200; contentHeight: 1000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "README.md", "title": "Readme", "size": 100},' +
    '{"path": "docs/specs/Design Doc.md", "title": "Design", "size": 200}], "truncated": false}'
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-a/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "d", "type": "user", "size": 10, "indexed": true},' +
    '{"file": "feedback_a.md", "name": "Terse", "description": "d", "type": "feedback", "size": 10, "indexed": true}]}'

  property var calls: []
  property var flick: null

  function card(id, title, status, children) {
    return { id: id, title: title, status: status, description: "d", blocked_by: [], children: children || [] }
  }

  // The effects Panel owns, reproduced here so the scroll bookkeeping is real.
  function makeActions() {
    return {
      focusForView: function() { tc.calls.push("focus") },
      scrollToTop: function() { tc.calls.push("top"); if (tc.flick) tc.flick.contentY = 0 },
      scrollBy: function(px) {
        tc.calls.push("by:" + px)
        if (tc.flick) tc.flick.contentY = Math.max(0, Math.min(tc.flick.contentY + px,
          Math.max(0, tc.flick.contentHeight - tc.flick.height)))
      },
      centerOnGraphNode: function(id) { tc.calls.push("center:" + id) }
    }
  }

  function make() {
    tc.calls = []
    var appC = Qt.createComponent("../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var navC = Qt.createComponent("../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    tc.flick = createTemporaryObject(flickC, tc)
    var n = navC.createObject(tc, { app: app, flick: tc.flick, actions: makeActions() })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA, pB])
    return n
  }

  function test_leaving_a_card_restores_the_board_cursor_and_the_scroll_position() {
    var n = make(); if (!n) return
    n.app.board.applyTreeData([card("m1", "Milestone", "todo"), card("b1", "Blk", "blocked")])
    wait(50)
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 150
    n.openCard("b1")
    compare(n.app.nav.viewMode, "entry")
    compare(n.app.nav.cursorIndex, 0)
    wait(0)
    compare(tc.flick.contentY, 0)
    n.restoreListView()
    compare(n.app.nav.viewMode, "board")
    compare(n.app.nav.cursorIndex, 1)
    wait(0)
    compare(tc.flick.contentY, 150)
  }

  function test_leaving_a_document_restores_the_list_cursor_and_the_scroll_position() {
    var n = make(); if (!n) return
    n.showSection("documents")
    n.app.docs.applyDocsResult(docList, 0)
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 220
    n.openDoc("docs/specs/Design Doc.md")
    compare(n.app.nav.viewMode, "document")
    compare(n.app.nav.cursorIndex, 0)
    wait(0)
    compare(tc.flick.contentY, 0)
    n.restoreDocumentsList()
    compare(n.app.nav.viewMode, "documents")
    compare(n.app.nav.cursorIndex, 1)
    compare(n.app.docs.selectedDocPath, "")
    wait(0)
    compare(tc.flick.contentY, 220)
  }

  function test_leaving_a_memory_note_restores_the_list_cursor_and_the_scroll_position() {
    var n = make(); if (!n) return
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 90
    n.openMemory("feedback_a.md")
    compare(n.app.nav.viewMode, "memory")
    compare(n.app.nav.cursorIndex, 0)
    wait(0)
    compare(tc.flick.contentY, 0)
    n.restoreMemoriesList()
    compare(n.app.nav.viewMode, "memories")
    compare(n.app.nav.cursorIndex, 1)
    compare(n.app.memories.selectedMemory, "")
    wait(0)
    compare(tc.flick.contentY, 90)
  }

  function test_an_unsaved_draft_blocks_a_section_switch() {
    var n = make(); if (!n) return
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.openMemory("user_role.md")
    n.app.memories.setMemoryText("body")
    n.app.memories.startMemoryEdit()
    n.app.memories.memoryDraft = "body plus more"
    n.showSection("board")
    compare(n.app.nav.viewMode, "memory")
    n.app.memories.memoryDraft = "body"
    n.showSection("board")
    compare(n.app.nav.viewMode, "board")
  }

  function test_an_unsaved_draft_blocks_a_project_switch_with_a_message() {
    var n = make(); if (!n) return
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.openMemory("user_role.md")
    n.app.memories.setMemoryText("body")
    n.app.memories.startMemoryEdit()
    n.app.memories.memoryDraft = "body plus more"
    var before = n.app.projects.selectedProject.root_path
    n.chooseProject(pB)
    compare(n.app.projects.selectedProject.root_path, before)
    compare(n.app.memories.memoryOpError,
      "You have unsaved changes. Save them, or choose Cancel to discard, before switching project.")
  }

  function test_the_graph_cursor_move_asks_the_panel_to_centre_on_the_new_node() {
    var n = make(); if (!n) return
    n.app.board.applyTreeData([card("m1", "Milestone", "todo", [card("s1", "Story", "todo")])])
    wait(50)
    n.showSection("graph")
    compare(n.app.nav.viewMode, "graph")
    var start = n.app.graph.graphCursor
    verify(start !== "", "the graph starts on a node")
    tc.calls = []
    n.moveGraph("down")
    var centred = tc.calls.filter(function(c) { return c.indexOf("center:") === 0 })
    compare(centred.join(","), "center:" + n.app.graph.graphCursor)
  }

  function test_a_graph_move_with_no_graph_centres_on_nothing() {
    var n = make(); if (!n) return
    n.showSection("graph")
    tc.calls = []
    n.moveGraph("down")
    compare(tc.calls.filter(function(c) { return c.indexOf("center:") === 0 }).join(","), "")
  }

  function test_the_dropdown_stays_shut_while_a_delete_is_being_confirmed() {
    var n = make(); if (!n) return
    n.app.deleter.openDelete(n.app.projects.selectedProject)
    n.toggleDropdown()
    compare(n.app.nav.dropdownOpen, false)
  }
}
