// tests/ui/screens/tst_memories_screen.qml
// ui/screens/MemoriesScreen.qml on its own: the rows it renders from the
// memories store, the type chip it toggles, and the click/hover/reveal it
// forwards to the navigator.
// REAL core/stores App and REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "MemoriesScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var reveals: []
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-a/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "d", "type": "user", "size": 10, "indexed": true},' +
    '{"file": "feedback_a.md", "name": "Terse", "description": "d", "type": "feedback", "size": 10, "indexed": true}]}'

  function make() {
    tc.reveals = []
    var host = createTemporaryObject(hostC, tc)
    var appC = Qt.createComponent("../../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(host, { backendDir: "/plugin/core/backend/" })
    var navC = Qt.createComponent("../../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    var flick = flickC.createObject(host)
    var nav = navC.createObject(host, { app: app, flick: flick, documentsEnabled: true, actions: ({
      focusForView: function() {},
      scrollToTop: function() { flick.contentY = 0 },
      scrollBy: function(px) { flick.contentY = flick.contentY + px },
      centerOnGraphNode: function(id) {}
    }) })
    var sC = Qt.createComponent("../../../ui/screens/MemoriesScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 500 })
    s.revealRequested.connect(function(item) { tc.reveals.push(item) })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    return s
  }

  function loaded() {
    var s = make(); if (!s) return null
    s.navigator.showSection("memories")
    s.app.memories.applyMemoriesResult(memList, 0)
    return s
  }

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    return null
  }

  function test_the_memories_screen_shows_only_in_the_memories_view_with_a_project() {
    var s = make(); if (!s) return
    compare(s.visible, false)
    s.navigator.showSection("memories")
    compare(s.visible, true)
    s.app.projects.selectedProject = null
    compare(s.visible, false)
  }

  function test_the_rows_come_from_the_filtered_memories_of_the_store() {
    var s = loaded(); if (!s) return
    wait(50)
    verify(find(s, "memoriesView"), "the shared MemoriesView is inside the screen")
    compare(find(s, "memoryRowTitle0").text, "Role")
    compare(find(s, "memoryRowTitle1").text, "Terse")
    s.app.nav.searchQuery = "Terse"
    wait(50)
    compare(s.app.memories.filteredMemories.length, 1)
    compare(find(s, "memoryRowTitle0").text, "Terse")
  }

  function test_clicking_a_row_opens_that_note_through_the_navigator() {
    var s = loaded(); if (!s) return
    wait(50)
    mouseClick(find(s, "memoryRow1"))
    compare(s.app.memories.selectedMemory, "feedback_a.md")
    compare(s.app.nav.viewMode, "memory")
  }

  function test_hovering_a_row_moves_the_cursor_through_the_navigator() {
    var s = loaded(); if (!s) return
    wait(50)
    compare(s.app.nav.cursorIndex, 0)
    var row = find(s, "memoryRow1")
    mouseMove(row, row.width / 2, row.height / 2)
    compare(s.app.nav.cursorIndex, 1)
  }

  function test_a_type_chip_toggles_the_store_memory_type() {
    var s = loaded(); if (!s) return
    wait(50)
    var chip = find(s, "memoryChipfeedback")
    verify(chip, "the feedback type chip")
    mouseClick(chip)
    compare(s.app.memories.memoryType, "feedback")
    wait(50)
    mouseClick(find(s, "memoryChipfeedback"))
    compare(s.app.memories.memoryType, "")
  }

  function test_a_keyboard_cursor_move_asks_the_panel_to_reveal_the_row() {
    var s = loaded(); if (!s) return
    wait(50)
    s.app.nav.moveCursor(1, s.app.memories.filteredMemories.length)
    wait(50)
    verify(tc.reveals.length > 0, "the screen forwarded a reveal request")
  }
}
