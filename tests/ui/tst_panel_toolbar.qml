// tests/ui/tst_panel_toolbar.qml
// The fixed toolbar of ui/Panel.qml: the refresh and New icon/action buttons
// (their look, their order in the row and what they call), and the Documents
// pieces that live in the toolbar instead of the scrolling content.
import QtQuick
import QtTest
import "../helpers/find.js" as H

TestCase {
  id: tc
  name: "PanelToolbar"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-my-proj/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "d", "type": "user", "size": 10, "indexed": true}]}'
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "docs/architecture/a.md", "title": "Arch", "size": 1, "category": "architecture"},' +
    '{"path": "docs/specs/s.md", "title": "Spec", "size": 1, "category": "specs"}], "truncated": false}'

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA])
    return p
  }

  function inMemories() {
    var p = make(); if (!p) return null
    p.navigator.showSection("memories")
    p.app.memories.applyMemoriesResult(memList, 0)
    wait(50)
    return p
  }

  function inDocuments() {
    var p = make(); if (!p) return null
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(docList, 0)
    wait(50)
    return p
  }

  // Walks up from `item`: is it inside the item named `name`?
  function isUnder(item, name) {
    var node = item
    while (node) {
      if (node.objectName === name) return true
      node = node.parent
    }
    return false
  }

  // ---- the refresh and New buttons

  function test_the_refresh_button_is_a_bordered_icon_button() {
    var p = inMemories(); if (!p) return
    var refresh = H.find(p, "refreshButton")
    verify(refresh, "the refresh button")
    verify(String(refresh.iconText) !== "", "it draws a glyph")
    compare(String(refresh.text), "")
    compare(refresh.bordered, true)
    compare(String(refresh.tooltipText), "Refresh")
  }

  function test_the_refresh_button_is_square_and_as_tall_as_the_new_button() {
    var p = inMemories(); if (!p) return
    var refresh = H.find(p, "refreshButton")
    var newButton = H.find(p, "newMemoryButton")
    verify(refresh && newButton, "both toolbar buttons")
    compare(newButton.visible, true)
    compare(refresh.width, refresh.height)
    compare(refresh.height, newButton.height)
  }

  function test_the_refresh_button_sits_left_of_the_new_button() {
    var p = inMemories(); if (!p) return
    var refresh = H.find(p, "refreshButton")
    var newButton = H.find(p, "newMemoryButton")
    verify(refresh && newButton, "both toolbar buttons")
    compare(refresh.visible, true)
    compare(newButton.visible, true)
    var rx = refresh.mapToItem(p, 0, 0).x
    var nx = newButton.mapToItem(p, 0, 0).x
    verify(rx < nx, "refresh at " + rx + " is left of New at " + nx)
  }

  function test_the_new_button_is_a_bordered_button_that_opens_the_dialog() {
    var p = inMemories(); if (!p) return
    var newButton = H.find(p, "newMemoryButton")
    verify(newButton, "the New button")
    compare(newButton.bordered, true)
    verify(String(newButton.text) !== "", "it keeps its label")
    mouseClick(newButton, newButton.width / 2, newButton.height / 2)
    compare(p.app.memories.newMemoryOpen, true)
  }

  function test_the_refresh_button_refetches_the_open_section() {
    var p = inMemories(); if (!p) return
    var refresh = H.find(p, "refreshButton")
    mouseClick(refresh, refresh.width / 2, refresh.height / 2)
    compare(p.app.memories.memoriesLoading, true)
    p.navigator.showSection("board")
    wait(50)
    p.app.board.treeProc.running = false
    refresh = H.find(p, "refreshButton")
    compare(refresh.visible, true)
    mouseClick(refresh, refresh.width / 2, refresh.height / 2)
    compare(p.app.board.treeProc.running, true)
  }

  function test_the_refresh_button_is_hidden_outside_board_graph_and_memories() {
    var p = inDocuments(); if (!p) return
    compare(H.find(p, "refreshButton").visible, false)
    p.navigator.showSection("graph")
    wait(50)
    compare(H.find(p, "refreshButton").visible, true)
  }

}
