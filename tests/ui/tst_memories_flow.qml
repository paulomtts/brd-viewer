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
    var comp = Qt.createComponent("../../Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.stateLoaded = true
    p.applyProjectsList([pA, pB])
    return p
  }
  function named(p, name) {
    for (var i = 0; i < p.data.length; i++) if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }
  function files(list) { return list.map(function(n) { return n.file }).join(",") }
  function loaded() {
    var p = make(); if (!p) return null
    p.showSection("memories")
    p.applyMemoriesResult(memList, 0)
    return p
  }
  function findIn(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = findIn(kids[i], name); if (r) return r }
    return null
  }

  function test_the_section_fetches_and_lists_the_memories() {
    var p = make(); if (!p) return
    p.showSection("memories")
    compare(p.app.nav.viewMode, "memories")
    compare(p.app.nav.section, "memories")
    compare(p.app.nav.sectionTitle, "Memories")
    compare(p.memoriesLoading, true)
    var proc = p.memoriesProc
    verify(proc, "memoriesProc")
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("list-memories.py"))
    compare(proc.command[2], "/home/u/my proj")
    p.applyMemoriesResult(memList, 0)
    compare(p.memoriesLoading, false)
    compare(p.memoryDir, "/c/-home-u-my-proj/memory")
    compare(p.memoriesFound, true)
    compare(files(p.memories), "user_role.md,feedback_a.md,feedback_b.md")
    compare(p.memoryTypes.length, 2)
  }

  function test_ctrl_4_shows_memories() {
    var p = make(); if (!p) return
    compare(p.handleGlobalKey({ key: Qt.Key_4, modifiers: Qt.ControlModifier, accepted: false }), true)
    compare(p.app.nav.viewMode, "memories")
  }

  function test_type_filter_and_search_combine_and_reset_the_cursor() {
    var p = loaded(); if (!p) return
    p.app.nav.cursorIndex = 2
    p.toggleMemoryType("feedback")
    compare(p.memoryType, "feedback")
    compare(p.app.nav.cursorIndex, 0)
    compare(files(p.filteredMemories), "feedback_a.md,feedback_b.md")
    p.app.nav.searchQuery = "real"
    compare(files(p.filteredMemories), "feedback_b.md")
    compare(files(p.currentList()), "feedback_b.md")
    p.app.nav.searchQuery = ""
    p.toggleMemoryType("feedback")
    compare(p.memoryType, "")
    compare(p.filteredMemories.length, 3)
  }

  function test_a_failed_listing_shows_the_error() {
    var p = make(); if (!p) return
    p.showSection("memories")
    p.applyMemoriesResult('{"ok": false, "error": "nope"}', 1)
    compare(p.memoriesError, "nope")
    compare(p.memories.length, 0)
    p.showSection("board")
    compare(p.app.nav.viewMode, "board")
  }

  function test_opening_a_note_points_the_file_view_at_it_and_back_restores_the_list() {
    var p = loaded(); if (!p) return
    p.app.nav.cursorIndex = 1
    p.activateCursor()
    compare(p.app.nav.viewMode, "memory")
    compare(p.app.nav.section, "memories")
    compare(p.selectedMemory, "feedback_a.md")
    compare(p.selectedMemoryEntry.name, "Terse")
    var fv = named(p, "memoryFile")
    verify(fv, "memoryFile")
    compare(fv.path, "/c/-home-u-my-proj/memory/feedback_a.md")
    fv.stubText = "---\nname: Terse\n---\nbody"
    fv.loaded()
    compare(p.memoryText, "---\nname: Terse\n---\nbody")
    p.goBack()
    compare(p.app.nav.viewMode, "memories")
    compare(p.app.nav.cursorIndex, 1)
    compare(named(p, "memoryFile").path, "")
  }

  function test_editing_a_note_saves_through_the_helper_and_refreshes() {
    var p = loaded(); if (!p) return
    p.openMemory("feedback_a.md")
    p.setMemoryText("old text")
    p.startMemoryEdit()
    compare(p.memoryEditing, true)
    compare(p.memoryDraft, "old text")
    p.memoryDraft = "new text"
    p.saveMemory()
    var proc = named(p, "memoryOpProc")
    verify(proc, "memoryOpProc")
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("memory-op.py"))
    compare(proc.command[2], "save")
    compare(proc.command[3], "/c/-home-u-my-proj/memory")
    compare(proc.command[4], "feedback_a.md")
    compare(proc.command[5], "new text")
    compare(p.memoryBusy, true)
    p.saveMemory()
    compare(proc.command[5], "new text")
    p.applyMemoryOpResult('{"ok": true, "backup": "/b"}', 0)
    compare(p.memoryBusy, false)
    compare(p.memoryEditing, false)
    compare(p.memoryText, "new text")
    compare(p.memoriesLoading, true)
  }

  function test_a_failed_save_keeps_the_draft_and_shows_the_error() {
    var p = loaded(); if (!p) return
    p.openMemory("feedback_a.md")
    p.setMemoryText("old")
    p.startMemoryEdit()
    p.memoryDraft = "changed"
    p.saveMemory()
    p.applyMemoryOpResult('{"ok": false, "error": "Could not write the memory: Permission denied"}', 1)
    compare(p.memoryBusy, false)
    compare(p.memoryEditing, true)
    compare(p.memoryDraft, "changed")
    compare(p.memoryOpError, "Could not write the memory: Permission denied")
  }

  function test_escape_leaves_a_clean_editor_but_not_unsaved_changes() {
    var p = loaded(); if (!p) return
    p.openMemory("feedback_a.md")
    p.setMemoryText("t")
    p.startMemoryEdit()
    p.memoryEscape()
    compare(p.memoryEditing, false)
    p.startMemoryEdit()
    p.memoryDraft = "t!"
    p.memoryEscape()
    compare(p.memoryEditing, true)
    p.cancelMemoryEdit()
    compare(p.memoryEditing, false)
    compare(p.memoryDraft, "")
  }

  function test_creating_a_note_composes_the_file_and_opens_it_afterwards() {
    var p = loaded(); if (!p) return
    p.openNewMemory()
    compare(p.newMemoryOpen, true)
    p.createMemory("Terse replies", "feedback", "no summaries", "Keep it short.")
    var proc = named(p, "memoryOpProc")
    compare(proc.command[2], "create")
    compare(proc.command[3], "/c/-home-u-my-proj/memory")
    compare(proc.command[4], "feedback_terse-replies.md")
    compare(proc.command[5], "---\nname: Terse replies\ndescription: no summaries\nmetadata:\n  type: feedback\n---\n\nKeep it short.")
    compare(p.memoryBusy, true)
    p.applyMemoryOpResult('{"ok": true, "backup": ""}', 0)
    compare(p.newMemoryOpen, false)
    compare(p.memoriesLoading, true)
    p.applyMemoriesResult(memList.replace('"notes": [', '"notes": [{"file": "feedback_terse-replies.md", "name": "Terse replies", "description": "no summaries", "type": "feedback", "size": 1, "indexed": true},'), 0)
    compare(p.app.nav.viewMode, "memory")
    compare(p.selectedMemory, "feedback_terse-replies.md")
  }

  function test_a_new_note_never_reuses_an_existing_file_name() {
    var p = loaded(); if (!p) return
    p.createMemory("Terse", "feedback", "", "")
    compare(named(p, "memoryOpProc").command[4], "feedback_terse.md")
    p.applyMemoryOpResult('{"ok": false, "error": "exists"}', 1)
    p.createMemory("A", "feedback", "", "")
    p.applyMemoryOpResult('{"ok": true, "backup": ""}', 0)
    p.applyMemoriesResult(memList, 0)
    p.createMemory("a", "feedback", "", "")
    compare(named(p, "memoryOpProc").command[4], "feedback_a-2.md")
  }

  function test_a_failed_create_keeps_the_dialog_with_the_error() {
    var p = loaded(); if (!p) return
    p.openNewMemory()
    p.createMemory("X", "user", "", "")
    p.applyMemoryOpResult('{"ok": false, "error": "Memory file already exists."}', 1)
    compare(p.newMemoryOpen, true)
    compare(p.newMemoryError, "Memory file already exists.")
    compare(p.memoryBusy, false)
  }

  function test_creating_needs_a_place_for_the_memory_to_live() {
    var p = make(); if (!p) return
    p.showSection("memories")
    p.applyMemoriesResult('{"ok": true, "found": false, "memory_dir": "", "notes": []}', 0)
    compare(p.canCreateMemory, false)
    p.openNewMemory()
    compare(p.newMemoryOpen, false)
    p.applyMemoriesResult('{"ok": true, "found": false, "memory_dir": "/c/-x/memory", "notes": []}', 0)
    compare(p.canCreateMemory, true)
  }

  function test_deleting_a_note_is_confirmed_then_runs_the_helper() {
    var p = loaded(); if (!p) return
    p.openMemory("user_role.md")
    p.requestMemoryDelete()
    compare(p.memoryDeleteOpen, true)
    compare(named(p, "memoryOpProc") === null || !named(p, "memoryOpProc").running, true)
    p.cancelMemoryDelete()
    compare(p.memoryDeleteOpen, false)
    p.requestMemoryDelete()
    p.performMemoryDelete()
    var proc = named(p, "memoryOpProc")
    compare(proc.command[2], "delete")
    compare(proc.command[4], "user_role.md")
    compare(p.memoryBusy, true)
    p.applyMemoryOpResult('{"ok": true, "backup": "/b"}', 0)
    compare(p.memoryDeleteOpen, false)
    compare(p.app.nav.viewMode, "memories")
    compare(p.memoriesLoading, true)
  }

  function test_a_failed_delete_shows_the_error_in_the_dialog() {
    var p = loaded(); if (!p) return
    p.openMemory("user_role.md")
    p.requestMemoryDelete()
    p.performMemoryDelete()
    p.applyMemoryOpResult('{"ok": false, "error": "nope"}', 1)
    compare(p.memoryDeleteOpen, true)
    compare(p.memoryDeleteError, "nope")
  }

  function test_modals_block_global_shortcuts_and_take_focus() {
    var p = loaded(); if (!p) return
    p.openMemory("user_role.md")
    p.requestMemoryDelete()
    compare(p.handleGlobalKey({ key: Qt.Key_1, modifiers: Qt.ControlModifier, accepted: false }), false)
    compare(p.app.nav.viewMode, "memory")
    compare(p.focusItem.objectName, "confirmTyped")
    p.cancelMemoryDelete()
    p.setMemoryText("t")
    p.startMemoryEdit()
    compare(p.focusItem.objectName, "memoryEditor")
    p.cancelMemoryEdit()
    p.goBack()
    p.openNewMemory()
    compare(p.focusItem.objectName, "newMemoryName")
  }

  function test_switching_project_clears_the_memory_state() {
    var p = loaded(); if (!p) return
    p.toggleMemoryType("user")
    p.openMemory("user_role.md")
    p.selectProject(pB)
    compare(p.memories.length, 0)
    compare(p.memoryType, "")
    compare(p.selectedMemory, "")
    compare(p.memoryDir, "")
    compare(p.app.nav.viewMode, "board")
  }

  function test_the_views_are_wired_and_the_note_view_reports_actions() {
    var p = loaded(); if (!p) return
    var host = p.parent
    var list = findIn(host, "memoriesView")
    verify(list, "memoriesView")
    compare(list.notes.length, 3)
    list.typeToggled("user")
    compare(p.memoryType, "user")
    p.toggleMemoryType("user")
    list.noteChosen("feedback_b.md")
    compare(p.selectedMemory, "feedback_b.md")
    var note = findIn(host, "memoryNoteView")
    verify(note, "memoryNoteView")
    compare(note.entry.name, "Testing")
    p.setMemoryText("t")
    note.editRequested()
    compare(p.memoryEditing, true)
  }

  function test_the_sidebar_offers_memories() {
    var p = make(); if (!p) return
    verify(findIn(p.parent, "navMemories"), "navMemories")
  }

  function test_save_passes_the_text_it_was_opened_with_so_outside_edits_are_caught() {
    var p = loaded(); if (!p) return
    p.openMemory("feedback_a.md")
    p.setMemoryText("opened text")
    p.startMemoryEdit()
    p.setMemoryText("someone else changed it")
    p.memoryDraft = "my edit"
    p.saveMemory()
    compare(named(p, "memoryOpProc").command[5], "my edit")
    compare(named(p, "memoryOpProc").command[6], "opened text")
  }

  function test_a_late_list_does_not_pull_you_into_a_new_note() {
    var p = loaded(); if (!p) return
    p.createMemory("Late", "user", "", "")
    p.applyMemoryOpResult('{"ok": true, "backup": ""}', 0)
    p.showSection("board")
    p.applyMemoriesResult(memList.replace('"notes": [', '"notes": [{"file": "user_late.md", "name": "Late", "description": "", "type": "user", "size": 1, "indexed": true},'), 0)
    compare(p.app.nav.viewMode, "board")
    compare(p.selectedMemory, "")
  }

  function test_a_failed_refresh_keeps_the_memory_folder_so_saving_still_works() {
    var p = loaded(); if (!p) return
    p.openMemory("feedback_a.md")
    p.setMemoryText("t")
    p.startMemoryEdit()
    p.memoryDraft = "t2"
    p.applyMemoriesResult('{"ok": false, "error": "boom"}', 1)
    compare(p.memoryDir, "/c/-home-u-my-proj/memory")
    p.saveMemory()
    compare(p.memoryBusy, true)
  }

  function test_switching_project_is_blocked_while_an_edit_has_unsaved_changes() {
    var p = loaded(); if (!p) return
    p.openMemory("feedback_a.md")
    p.setMemoryText("t")
    p.startMemoryEdit()
    p.memoryDraft = "unsaved"
    p.chooseProject(pB)
    compare(p.selectedProject.root_path, pA.root_path)
    compare(p.memoryDraft, "unsaved")
    verify(p.memoryOpError !== "")
    p.cancelMemoryEdit()
    p.chooseProject(pB)
    compare(p.selectedProject.root_path, pB.root_path)
  }
}
