// tests/ui/tst_memories_flow.qml
// What the panel still does around MemoriesStore: the section shortcut, the
// navigation and cursor restore around an open note, the modals' focus, the
// views' wiring, and the dirty-draft guard on a project switch. The state
// itself is tested in tests/core/stores/tst_memories_store.qml.
import QtQuick
import QtTest
TestCase {
  id: tc
  name: "MemoriesFlow"
  when: windowShown
  visible: true
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-my-proj/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "data scientist", "type": "user", "size": 10, "indexed": true},' +
    '{"file": "feedback_a.md", "name": "Terse", "description": "no summaries", "type": "feedback", "size": 10, "indexed": true},' +
    '{"file": "feedback_b.md", "name": "Testing", "description": "real db", "type": "feedback", "size": 10, "indexed": true}]}'

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA, pB])
    return p
  }
  function loaded() {
    var p = make(); if (!p) return null
    p.showSection("memories")
    p.app.memories.applyMemoriesResult(memList, 0)
    return p
  }
  function findIn(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = findIn(kids[i], name); if (r) return r }
    return null
  }

  function test_ctrl_4_shows_memories() {
    var p = make(); if (!p) return
    compare(p.handleGlobalKey({ key: Qt.Key_4, modifiers: Qt.ControlModifier, accepted: false }), true)
    compare(p.app.nav.viewMode, "memories")
    compare(p.app.memories.memoriesLoading, true, "the section fetches the listing")
  }

  function test_opening_a_note_points_the_file_view_at_it_and_back_restores_the_list() {
    var p = loaded(); if (!p) return
    p.app.nav.cursorIndex = 1
    p.activateCursor()
    compare(p.app.nav.viewMode, "memory")
    compare(p.app.nav.section, "memories")
    compare(p.app.memories.selectedMemory, "feedback_a.md")
    compare(p.app.memories.selectedMemoryEntry.name, "Terse")
    var fv = p.app.memories.memoryFile
    verify(fv, "memoryFile")
    compare(fv.path, "/c/-home-u-my-proj/memory/feedback_a.md")
    fv.stubText = "---\nname: Terse\n---\nbody"
    fv.loaded()
    compare(p.app.memories.memoryText, "---\nname: Terse\n---\nbody")
    p.goBack()
    compare(p.app.nav.viewMode, "memories")
    compare(p.app.nav.cursorIndex, 1)
    compare(p.app.memories.memoryFile.path, "")
  }

  function test_modals_block_global_shortcuts_and_take_focus() {
    var p = loaded(); if (!p) return
    p.openMemory("user_role.md")
    p.app.memories.requestMemoryDelete()
    compare(p.handleGlobalKey({ key: Qt.Key_1, modifiers: Qt.ControlModifier, accepted: false }), false)
    compare(p.app.nav.viewMode, "memory")
    compare(p.focusItem.objectName, "confirmTyped")
    p.app.memories.cancelMemoryDelete()
    p.app.memories.setMemoryText("t")
    p.app.memories.startMemoryEdit()
    compare(p.focusItem.objectName, "memoryEditor")
    p.app.memories.cancelMemoryEdit()
    p.goBack()
    p.app.memories.openNewMemory()
    compare(p.focusItem.objectName, "newMemoryName")
  }

  function test_the_views_are_wired_and_the_note_view_reports_actions() {
    var p = loaded(); if (!p) return
    var host = p.parent
    var list = findIn(host, "memoriesView")
    verify(list, "memoriesView")
    compare(list.notes.length, 3)
    list.typeToggled("user")
    compare(p.app.memories.memoryType, "user")
    p.app.memories.toggleMemoryType("user")
    list.noteChosen("feedback_b.md")
    compare(p.app.memories.selectedMemory, "feedback_b.md")
    var note = findIn(host, "memoryNoteView")
    verify(note, "memoryNoteView")
    compare(note.entry.name, "Testing")
    p.app.memories.setMemoryText("t")
    note.editRequested()
    compare(p.app.memories.memoryEditing, true)
  }

  function test_the_sidebar_offers_memories() {
    var p = make(); if (!p) return
    verify(findIn(p.parent, "navMemories"), "navMemories")
  }

  function test_switching_project_is_blocked_while_an_edit_has_unsaved_changes() {
    var p = loaded(); if (!p) return
    p.openMemory("feedback_a.md")
    p.app.memories.setMemoryText("t")
    p.app.memories.startMemoryEdit()
    p.app.memories.memoryDraft = "unsaved"
    p.chooseProject(pB)
    compare(p.app.projects.selectedProject.root_path, pA.root_path)
    compare(p.app.memories.memoryDraft, "unsaved")
    verify(p.app.memories.memoryOpError !== "")
    p.app.memories.cancelMemoryEdit()
    p.chooseProject(pB)
    compare(p.app.projects.selectedProject.root_path, pB.root_path)
  }

  // A dirty draft also holds the section shortcuts, so an edit cannot be lost
  // by hopping to another section.
  function test_switching_section_is_blocked_while_an_edit_has_unsaved_changes() {
    var p = loaded(); if (!p) return
    p.openMemory("feedback_a.md")
    p.app.memories.setMemoryText("t")
    p.app.memories.startMemoryEdit()
    p.app.memories.memoryDraft = "unsaved"
    p.showSection("board")
    compare(p.app.nav.viewMode, "memory")
    p.app.memories.cancelMemoryEdit()
    p.showSection("board")
    compare(p.app.nav.viewMode, "board")
  }
}
