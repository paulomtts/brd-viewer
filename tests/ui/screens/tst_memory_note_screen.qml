// tests/ui/screens/tst_memory_note_screen.qml
// ui/screens/MemoryNoteScreen.qml on its own: the note it renders from the
// memories store, the edit/save/cancel/delete buttons it forwards to the store,
// and the editor item Panel focuses while a note is being edited.
// REAL core/stores App and REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "MemoryNoteScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-a/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "how they work", "type": "user", "size": 10, "indexed": true},' +
    '{"file": "feedback_a.md", "name": "Terse", "description": "d", "type": "feedback", "size": 10, "indexed": true}]}'

  function make() {
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
    var sC = Qt.createComponent("../../../ui/screens/MemoryNoteScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 500 })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    return s
  }

  function opened() {
    var s = make(); if (!s) return null
    s.navigator.showSection("memories")
    s.app.memories.applyMemoriesResult(memList, 0)
    s.navigator.openMemory("user_role.md")
    s.app.memories.setMemoryText("the body")
    return s
  }

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    return null
  }

  function test_the_note_screen_shows_only_in_the_note_view_with_a_project() {
    var s = make(); if (!s) return
    compare(s.visible, false)
    var o = opened(); if (!o) return
    compare(o.visible, true)
    o.app.projects.selectedProject = null
    compare(o.visible, false)
  }

  function test_the_open_note_is_rendered_from_the_store() {
    var s = opened(); if (!s) return
    wait(50)
    verify(find(s, "memoryNoteView"), "the shared MemoryNoteView is inside the screen")
    compare(find(s, "memoryNoteName").text, "Role")
    compare(find(s, "memoryNoteDescription").text, "how they work")
    compare(find(s, "memoryNoteBody").text, "the body")
  }

  function test_a_read_error_is_shown_instead_of_the_body() {
    var s = opened(); if (!s) return
    s.app.memories.memoryReadError = "Could not read this note."
    wait(50)
    compare(find(s, "memoryNoteReadError").visible, true)
    compare(find(s, "memoryNoteReadError").text, "Could not read this note.")
  }

  function test_the_edit_button_starts_an_edit_and_cancel_ends_it() {
    var s = opened(); if (!s) return
    wait(50)
    mouseClick(find(s, "memoryEdit"))
    compare(s.app.memories.memoryEditing, true)
    compare(s.app.memories.memoryDraft, "the body")
    wait(50)
    mouseClick(find(s, "memoryCancelEdit"))
    compare(s.app.memories.memoryEditing, false)
  }

  function test_the_save_button_runs_the_save_with_the_edited_draft() {
    var s = opened(); if (!s) return
    wait(50)
    mouseClick(find(s, "memoryEdit"))
    s.app.memories.memoryDraft = "the body plus more"
    wait(50)
    mouseClick(find(s, "memorySave"))
    compare(s.app.memories.memoryBusy, true)
    verify(s.app.memories.operator.current, "the save helper was launched")
  }

  function test_the_delete_button_asks_the_store_to_confirm() {
    var s = opened(); if (!s) return
    wait(50)
    mouseClick(find(s, "memoryDelete"))
    compare(s.app.memories.memoryDeleteOpen, true)
  }

  function test_the_screen_exposes_the_editor_item_the_panel_focuses() {
    var s = opened(); if (!s) return
    s.app.memories.startMemoryEdit()
    wait(50)
    verify(s.editorItem, "the screen exposes the editor item")
    compare(s.editorItem, find(s, "memoryNoteView").editorItem)
  }
}
