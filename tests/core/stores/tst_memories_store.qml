// tests/core/stores/tst_memories_store.qml
// The project's memory notes: the listing, the type filter, the open note with
// its live text, and the save/create/delete operations -- driven through App so
// the wiring to the project and navigation stores is exercised too. Scrolling,
// focus, the view mode and the dirty-draft guards stay in the panel and are
// tested in tests/ui/tst_memories_flow.qml.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresMemoriesStore"

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-my-proj/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "data scientist", "type": "user", "size": 10, "indexed": true},' +
    '{"file": "feedback_a.md", "name": "Terse", "description": "no summaries", "type": "feedback", "size": 10, "indexed": true},' +
    '{"file": "feedback_b.md", "name": "Testing", "description": "real db", "type": "feedback", "size": 10, "indexed": true}]}'
  property string memListB: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-b/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "", "type": "user", "size": 10, "indexed": true}]}'

  function make() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var app = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    // What the panel does with the store's two navigation requests.
    app.memories.noteOpenRequested.connect(function(file) { tc.open(app, file) })
    app.memories.listRestoreRequested.connect(function() {
      app.memories.restoreMemoriesList()
      app.nav.viewMode = "memories"
    })
    return app
  }
  // What the panel does around the store when the Memories section opens.
  function showMemories(app) { app.nav.viewMode = "memories"; app.memories.fetchMemories() }
  function open(app, file) { if (app.memories.openMemory(file)) app.nav.viewMode = "memory" }
  function loaded() {
    var app = make(); if (!app) return null
    showMemories(app)
    app.memories.applyMemoriesResult(memList, 0)
    return app
  }
  function files(list) { return list.map(function(n) { return n.file }).join(",") }
  function opProc(app) { return app.memories.operator.current }
  // memory-op.py answering: the helper's own exit, so `memoryBusy` is released
  // by the same path the real one takes.
  function finishOp(app, json, exitCode) {
    var proc = app.memories.operator.current
    verify(proc, "an operation is in flight")
    proc.outText = json
    proc.exited(exitCode)
  }

  function test_the_section_fetches_and_lists_the_memories() {
    var app = make(); if (!app) return
    showMemories(app)
    compare(app.nav.viewMode, "memories")
    compare(app.nav.section, "memories")
    compare(app.nav.sectionTitle, "Memories")
    compare(app.memories.memoriesLoading, true)
    var proc = app.memories.lister.current
    verify(proc, "a listing process")
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("list-memories.py"))
    compare(proc.command[2], "/home/u/my proj")
    compare(app.memories.lister.guard, "/home/u/my proj", "the listing is guarded by the project it was launched for")
    app.memories.applyMemoriesResult(memList, 0)
    compare(app.memories.memoriesLoading, false)
    compare(app.memories.memoryDir, "/c/-home-u-my-proj/memory")
    compare(app.memories.memoriesFound, true)
    compare(files(app.memories.memories), "user_role.md,feedback_a.md,feedback_b.md")
    compare(app.memories.memoryTypes.length, 2)
  }

  function test_type_filter_and_search_combine_and_reset_the_cursor() {
    var app = loaded(); if (!app) return
    app.nav.cursorIndex = 2
    app.memories.toggleMemoryType("feedback")
    compare(app.memories.memoryType, "feedback")
    compare(app.nav.cursorIndex, 0)
    compare(app.nav.scrollOnCursor, false)
    compare(files(app.memories.filteredMemories), "feedback_a.md,feedback_b.md")
    app.nav.searchQuery = "real"
    compare(files(app.memories.filteredMemories), "feedback_b.md")
    app.nav.searchQuery = ""
    app.memories.toggleMemoryType("feedback")
    compare(app.memories.memoryType, "")
    compare(app.memories.filteredMemories.length, 3)
  }

  function test_a_failed_listing_shows_the_error() {
    var app = make(); if (!app) return
    showMemories(app)
    app.memories.applyMemoriesResult('{"ok": false, "error": "nope"}', 1)
    compare(app.memories.memoriesError, "nope")
    compare(app.memories.memories.length, 0)
    compare(app.memories.memoriesLoading, false)
  }

  function test_opening_a_note_points_the_file_view_at_it() {
    var app = loaded(); if (!app) return
    open(app, "feedback_a.md")
    compare(app.memories.selectedMemory, "feedback_a.md")
    compare(app.memories.selectedMemoryEntry.name, "Terse")
    var fv = app.memories.memoryFile
    verify(fv, "memoryFile")
    compare(fv.path, "/c/-home-u-my-proj/memory/feedback_a.md")
    compare(fv.watchChanges, true)
    fv.stubText = "---\nname: Terse\n---\nbody"
    fv.loaded()
    compare(app.memories.memoryText, "---\nname: Terse\n---\nbody")
    app.memories.restoreMemoriesList()
    app.nav.viewMode = "memories"
    compare(app.memories.memoryFile.path, "")
  }

  function test_an_unknown_note_is_not_opened() {
    var app = loaded(); if (!app) return
    compare(app.memories.openMemory("nope.md"), false)
    compare(app.memories.selectedMemory, "")
    compare(app.memories.openMemory("feedback_a.md"), true)
  }

  function test_editing_a_note_saves_through_the_helper_and_refreshes() {
    var app = loaded(); if (!app) return
    open(app, "feedback_a.md")
    app.memories.setMemoryText("old text")
    app.memories.startMemoryEdit()
    compare(app.memories.memoryEditing, true)
    compare(app.memories.memoryDraft, "old text")
    app.memories.memoryDraft = "new text"
    app.memories.saveMemory()
    var proc = opProc(app)
    verify(proc, "an operation process")
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("memory-op.py"))
    compare(proc.command[2], "save")
    compare(proc.command[3], "/c/-home-u-my-proj/memory")
    compare(proc.command[4], "feedback_a.md")
    compare(proc.command[5], "new text")
    compare(app.memories.operator.guard, "/home/u/my proj", "the operation is guarded by the project it was launched for")
    compare(app.memories.memoryBusy, true)
    app.memories.saveMemory()
    compare(opProc(app), proc, "a second save cannot start while one is in flight")
    compare(proc.command[5], "new text")
    finishOp(app, '{"ok": true, "backup": "/b"}', 0)
    compare(app.memories.memoryBusy, false)
    compare(app.memories.memoryEditing, false)
    compare(app.memories.memoryText, "new text")
    compare(app.memories.memoriesLoading, true)
  }

  function test_a_failed_save_keeps_the_draft_and_shows_the_error() {
    var app = loaded(); if (!app) return
    open(app, "feedback_a.md")
    app.memories.setMemoryText("old")
    app.memories.startMemoryEdit()
    app.memories.memoryDraft = "changed"
    app.memories.saveMemory()
    finishOp(app, '{"ok": false, "error": "Could not write the memory: Permission denied"}', 1)
    compare(app.memories.memoryBusy, false)
    compare(app.memories.memoryEditing, true)
    compare(app.memories.memoryDraft, "changed")
    compare(app.memories.memoryOpError, "Could not write the memory: Permission denied")
  }

  function test_save_passes_the_text_it_was_opened_with_so_outside_edits_are_caught() {
    var app = loaded(); if (!app) return
    open(app, "feedback_a.md")
    app.memories.setMemoryText("opened text")
    app.memories.startMemoryEdit()
    app.memories.setMemoryText("someone else changed it")
    app.memories.memoryDraft = "my edit"
    app.memories.saveMemory()
    compare(opProc(app).command[5], "my edit")
    compare(opProc(app).command[6], "opened text")
  }

  function test_escape_leaves_a_clean_editor_but_not_unsaved_changes() {
    var app = loaded(); if (!app) return
    open(app, "feedback_a.md")
    app.memories.setMemoryText("t")
    app.memories.startMemoryEdit()
    app.memories.memoryEscape()
    compare(app.memories.memoryEditing, false)
    app.memories.startMemoryEdit()
    app.memories.memoryDraft = "t!"
    app.memories.memoryEscape()
    compare(app.memories.memoryEditing, true)
    verify(app.memories.memoryOpError !== "")
    app.memories.cancelMemoryEdit()
    compare(app.memories.memoryEditing, false)
    compare(app.memories.memoryDraft, "")
  }

  function test_creating_a_note_composes_the_file_and_opens_it_afterwards() {
    var app = loaded(); if (!app) return
    app.memories.openNewMemory()
    compare(app.memories.newMemoryOpen, true)
    app.memories.createMemory("Terse replies", "feedback", "no summaries", "Keep it short.")
    var proc = opProc(app)
    compare(proc.command[2], "create")
    compare(proc.command[3], "/c/-home-u-my-proj/memory")
    compare(proc.command[4], "feedback_terse-replies.md")
    compare(proc.command[5], "---\nname: Terse replies\ndescription: no summaries\nmetadata:\n  type: feedback\n---\n\nKeep it short.")
    compare(app.memories.memoryBusy, true)
    finishOp(app, '{"ok": true, "backup": ""}', 0)
    compare(app.memories.newMemoryOpen, false)
    compare(app.memories.memoriesLoading, true)
    app.memories.applyMemoriesResult(memList.replace('"notes": [', '"notes": [{"file": "feedback_terse-replies.md", "name": "Terse replies", "description": "no summaries", "type": "feedback", "size": 1, "indexed": true},'), 0)
    compare(app.nav.viewMode, "memory")
    compare(app.memories.selectedMemory, "feedback_terse-replies.md")
  }

  function test_a_new_note_never_reuses_an_existing_file_name() {
    var app = loaded(); if (!app) return
    app.memories.createMemory("Terse", "feedback", "", "")
    compare(opProc(app).command[4], "feedback_terse.md")
    finishOp(app, '{"ok": false, "error": "exists"}', 1)
    app.memories.createMemory("A", "feedback", "", "")
    finishOp(app, '{"ok": true, "backup": ""}', 0)
    app.memories.applyMemoriesResult(memList, 0)
    app.memories.createMemory("a", "feedback", "", "")
    compare(opProc(app).command[4], "feedback_a-2.md")
  }

  function test_a_failed_create_keeps_the_dialog_with_the_error() {
    var app = loaded(); if (!app) return
    app.memories.openNewMemory()
    app.memories.createMemory("X", "user", "", "")
    finishOp(app, '{"ok": false, "error": "Memory file already exists."}', 1)
    compare(app.memories.newMemoryOpen, true)
    compare(app.memories.newMemoryError, "Memory file already exists.")
    compare(app.memories.memoryBusy, false)
  }

  function test_creating_needs_a_place_for_the_memory_to_live() {
    var app = make(); if (!app) return
    showMemories(app)
    app.memories.applyMemoriesResult('{"ok": true, "found": false, "memory_dir": "", "notes": []}', 0)
    compare(app.memories.canCreateMemory, false)
    app.memories.openNewMemory()
    compare(app.memories.newMemoryOpen, false)
    app.memories.applyMemoriesResult('{"ok": true, "found": false, "memory_dir": "/c/-x/memory", "notes": []}', 0)
    compare(app.memories.canCreateMemory, true)
  }

  function test_deleting_a_note_is_confirmed_then_runs_the_helper() {
    var app = loaded(); if (!app) return
    open(app, "user_role.md")
    app.memories.requestMemoryDelete()
    compare(app.memories.memoryDeleteOpen, true)
    compare(opProc(app) === null || !opProc(app).running, true)
    app.memories.cancelMemoryDelete()
    compare(app.memories.memoryDeleteOpen, false)
    app.memories.requestMemoryDelete()
    app.memories.performMemoryDelete()
    var proc = opProc(app)
    compare(proc.command[2], "delete")
    compare(proc.command[4], "user_role.md")
    compare(app.memories.memoryBusy, true)
    finishOp(app, '{"ok": true, "backup": "/b"}', 0)
    compare(app.memories.memoryDeleteOpen, false)
    compare(app.memories.selectedMemory, "")
    compare(app.nav.viewMode, "memories")
    compare(app.memories.memoriesLoading, true)
  }

  function test_a_failed_delete_shows_the_error_in_the_dialog() {
    var app = loaded(); if (!app) return
    open(app, "user_role.md")
    app.memories.requestMemoryDelete()
    app.memories.performMemoryDelete()
    finishOp(app, '{"ok": false, "error": "nope"}', 1)
    compare(app.memories.memoryDeleteOpen, true)
    compare(app.memories.memoryDeleteError, "nope")
  }

  function test_a_late_list_does_not_pull_you_into_a_new_note() {
    var app = loaded(); if (!app) return
    app.memories.createMemory("Late", "user", "", "")
    finishOp(app, '{"ok": true, "backup": ""}', 0)
    app.nav.viewMode = "board"
    app.memories.applyMemoriesResult(memList.replace('"notes": [', '"notes": [{"file": "user_late.md", "name": "Late", "description": "", "type": "user", "size": 1, "indexed": true},'), 0)
    compare(app.nav.viewMode, "board")
    compare(app.memories.selectedMemory, "")
  }

  function test_a_failed_refresh_keeps_the_memory_folder_so_saving_still_works() {
    var app = loaded(); if (!app) return
    open(app, "feedback_a.md")
    app.memories.setMemoryText("t")
    app.memories.startMemoryEdit()
    app.memories.memoryDraft = "t2"
    app.memories.applyMemoriesResult('{"ok": false, "error": "boom"}', 1)
    compare(app.memories.memoryDir, "/c/-home-u-my-proj/memory")
    app.memories.saveMemory()
    compare(app.memories.memoryBusy, true)
  }

  function test_switching_project_clears_the_memory_state() {
    var app = loaded(); if (!app) return
    app.memories.toggleMemoryType("user")
    open(app, "user_role.md")
    app.projects.selectProject(pB)
    compare(app.memories.memories.length, 0)
    compare(app.memories.memoryType, "")
    compare(app.memories.selectedMemory, "")
    compare(app.memories.memoryDir, "")
    compare(app.memories.memoriesError, "")
    compare(app.memories.memoriesLoading, false)
    compare(app.memories.memoryEditing, false)
    compare(app.memories.newMemoryOpen, false)
    compare(app.memories.memoryDeleteOpen, false)
    compare(app.nav.viewMode, "board")
  }

  // A listing launched for a project the user has since left can never be
  // applied on top of the new one.
  function test_a_late_list_exit_from_the_previous_project_is_ignored() {
    var app = make(); if (!app) return
    showMemories(app)
    var first = app.memories.lister.current
    compare(first.command[2], "/home/u/my proj")
    app.projects.chooseProject(pB)
    showMemories(app)
    var second = app.memories.lister.current
    compare(second.command[2], "/home/u/b")
    second.outText = memListB
    second.exited(0)
    compare(app.memories.memories.length, 1)
    first.outText = memList
    first.exited(0)
    compare(app.memories.memoryDir, "/c/-home-u-b/memory")
    compare(app.memories.memories.length, 1)
  }

  function test_a_stale_list_exit_after_the_newer_run_finished_keeps_the_good_list() {
    var app = make(); if (!app) return
    showMemories(app)
    var first = app.memories.lister.current
    app.memories.fetchMemories()
    var second = app.memories.lister.current
    verify(first !== second, "each launch has its own process")
    second.outText = memList
    second.exited(0)
    compare(app.memories.memories.length, 3)
    first.outText = '{"ok": false, "error": "old"}'
    first.exited(1)
    compare(app.memories.memories.length, 3)
    compare(app.memories.memoriesError, "")
    compare(app.memories.memoriesLoading, false)
  }

  // The second half of the belt and braces: even an answer that reached the
  // store must not touch a project the user has left.
  function test_an_operation_result_for_a_project_the_user_left_is_dropped() {
    var app = loaded(); if (!app) return
    open(app, "feedback_a.md")
    app.memories.setMemoryText("t")
    app.memories.startMemoryEdit()
    app.memories.memoryDraft = "t2"
    app.memories.saveMemory()
    app.projects.chooseProject(pB)
    app.memories.applyMemoryOpResult('{"ok": true, "backup": ""}', 0)
    compare(app.memories.memoryText, "")
    compare(app.memories.memoriesLoading, false, "no refresh for the abandoned project")
  }

  // Leaving a project with an operation in flight must not lock the editor for
  // the rest of the session: its abandoned exit still releases `memoryBusy`,
  // and the next project can run its own operation.
  function test_an_operation_abandoned_by_a_project_switch_does_not_lock_the_editor() {
    var app = loaded(); if (!app) return
    open(app, "feedback_a.md")
    app.memories.setMemoryText("t")
    app.memories.startMemoryEdit()
    app.memories.memoryDraft = "t2"
    app.memories.saveMemory()
    var abandoned = opProc(app)
    compare(app.memories.memoryBusy, true)
    app.projects.chooseProject(pB)
    abandoned.outText = '{"ok": true, "backup": ""}'
    abandoned.exited(0)
    compare(app.memories.memoryBusy, false)
    compare(app.memories.memoryText, "", "the abandoned save must not touch the new project")
    showMemories(app)
    app.memories.applyMemoriesResult(memListB, 0)
    app.memories.createMemory("New", "user", "", "")
    compare(app.memories.memoryBusy, true)
    var proc = opProc(app)
    verify(proc, "an operation process for the new project")
    compare(proc.command[2], "create")
    compare(proc.command[3], "/c/-home-u-b/memory")
  }
}
