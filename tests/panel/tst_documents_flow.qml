import QtQuick
import QtTest
TestCase {
  id: tc
  name: "DocumentsFlow"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "README.md", "title": "Readme", "size": 100},' +
    '{"path": "docs/specs/Design Doc.md", "title": "Design", "size": 200},' +
    '{"path": "docs/huge.md", "title": "Huge", "size": 2000000}], "truncated": false}'

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("Panel.qml")
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
  function paths(list) { return list.map(function(d) { return d.path }).join(",") }

  function test_documents_are_enabled_and_fetched_when_the_section_opens() {
    var p = make(); if (!p) return
    compare(p.documentsEnabled, true)
    verify(!p.docsProc, "no listing before the section opens")
    p.showSection("documents")
    var proc = p.docsProc
    verify(proc, "listDocsProc")
    compare(proc.objectName, "listDocsProc")
    compare(p.viewMode, "documents")
    compare(p.section, "documents")
    compare(p.docsLoading, true)
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("list-docs.py"))
    compare(proc.command[2], "/home/u/my proj")
    compare(proc.running, true)
  }

  function test_the_result_fills_the_list_and_filtering_works() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    compare(p.docsLoading, false)
    compare(paths(p.docs), "README.md,docs/specs/Design Doc.md,docs/huge.md")
    p.searchQuery = "design"
    compare(paths(p.filteredDocs), "docs/specs/Design Doc.md")
    compare(paths(p.currentList()), "docs/specs/Design Doc.md")
  }

  function test_a_failed_listing_shows_the_error_and_keeps_the_board_usable() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult('{"ok": false, "error": "nope"}', 1)
    compare(p.docsError, "nope")
    compare(p.docs.length, 0)
    p.showSection("board")
    compare(p.viewMode, "board")
  }

  function test_opening_a_document_points_the_file_view_at_its_absolute_path() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.cursorIndex = 1
    p.activateCursor()
    compare(p.viewMode, "document")
    compare(p.section, "documents")
    compare(p.selectedDocPath, "docs/specs/Design Doc.md")
    var fv = named(p, "docFile")
    verify(fv, "docFile")
    compare(fv.path, "/home/u/my proj/docs/specs/Design Doc.md")
    compare(fv.watchChanges, true)
    fv.stubText = "# Design\n\nbody"
    fv.loaded()
    compare(p.docText, "# Design\n\nbody")
  }

  function test_a_file_change_reloads_the_text() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.cursorIndex = 0; p.activateCursor()
    var fv = named(p, "docFile")
    fv.stubText = "one"; fv.loaded(); compare(p.docText, "one")
    fv.stubText = "two"; fv.loaded(); compare(p.docText, "two")
  }

  function test_a_document_over_one_megabyte_is_not_loaded() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.cursorIndex = 2; p.activateCursor()
    compare(p.viewMode, "document")
    compare(p.docTooLargeFlag, true)
    compare(named(p, "docFile").path, "")
  }

  function test_a_read_failure_is_shown_with_back_available() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.cursorIndex = 0; p.activateCursor()
    named(p, "docFile").loadFailed(1)
    compare(p.docError, "Could not read this document.")
    p.goBack()
    compare(p.viewMode, "documents")
  }

  function test_back_restores_the_list_position() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.cursorIndex = 1
    p.activateCursor()
    p.goBack()
    compare(p.viewMode, "documents")
    compare(p.cursorIndex, 1)
    compare(p.selectedDocPath, "")
  }

  function test_escape_from_the_documents_list_is_left_to_the_close_handler() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.goBack()
    compare(p.viewMode, "documents")
  }

  function test_switching_project_reloads_the_documents_list() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.chooseProject(pB)
    compare(p.viewMode, "board")
    p.showSection("documents")
    compare(p.docsProc.command[2], "/home/u/b")
    compare(p.docs.length, 0)
    compare(p.docsLoading, true)
  }

  function test_ctrl_1_leaves_an_open_document() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.cursorIndex = 0; p.activateCursor()
    compare(p.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_1 }), true)
    compare(p.viewMode, "board")
  }

  function test_a_normal_single_run_fills_the_list() {
    var p = make(); if (!p) return
    p.showSection("documents")
    var proc = p.docsProc
    compare(proc.forRoot, "/home/u/my proj")
    proc.outText = docList
    proc.exited(0)
    compare(p.docs.length, 3)
    compare(p.docsLoading, false)
    compare(p.docsError, "")
  }

  function test_a_stale_exit_before_the_newer_run_completes_is_ignored() {
    var p = make(); if (!p) return
    p.showSection("documents")
    var first = p.docsProc
    p.fetchDocs()
    var second = p.docsProc
    verify(first !== second, "each launch has its own process")
    compare(first.running, false)
    first.outText = ""
    first.exited(1)
    compare(p.docsError, "")
    compare(p.docsLoading, true)
    second.outText = docList
    second.exited(0)
    compare(p.docs.length, 3)
  }

  function test_a_stale_exit_after_the_newer_run_finished_keeps_the_good_list() {
    var p = make(); if (!p) return
    p.showSection("documents")
    var first = p.docsProc
    p.fetchDocs()
    var second = p.docsProc
    second.outText = docList
    second.exited(0)
    compare(p.docs.length, 3)
    first.outText = ""
    first.exited(1)
    compare(p.docs.length, 3)
    compare(p.docsError, "")
    compare(p.docsLoading, false)
  }

  function test_a_late_exit_from_the_previous_project_is_ignored() {
    var p = make(); if (!p) return
    p.showSection("documents")
    var first = p.docsProc
    compare(first.forRoot, "/home/u/my proj")
    p.chooseProject(pB)
    p.showSection("documents")
    var second = p.docsProc
    compare(second.forRoot, "/home/u/b")
    second.outText = docList
    second.exited(0)
    compare(p.docs.length, 3)
    first.outText = '{"ok": false, "error": "old"}'
    first.exited(1)
    compare(p.docs.length, 3)
    compare(p.docsError, "")
  }

  function test_a_late_exit_after_leaving_the_project_before_any_refetch_is_ignored() {
    var p = make(); if (!p) return
    p.showSection("documents")
    var first = p.docsProc
    p.chooseProject(pB)
    first.outText = docList
    first.exited(0)
    compare(p.docs.length, 0)
  }

  function test_a_read_failure_while_in_the_list_does_not_set_an_error() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    compare(named(p, "docFile").path, "")
    named(p, "docFile").loadFailed(1)
    compare(p.docError, "")
  }

  function test_a_stale_read_failure_does_not_poison_the_next_document() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.cursorIndex = 0; p.activateCursor()
    p.goBack()
    p.cursorIndex = 1; p.activateCursor()
    named(p, "docFile").loadFailed(1)
    compare(p.docError, "Could not read this document.")
  }
}
