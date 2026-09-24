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
  function paths(list) { return list.map(function(d) { return d.path }).join(",") }

  function test_documents_are_enabled_and_fetched_when_the_section_opens() {
    var p = make(); if (!p) return
    compare(p.documentsEnabled, true)
    verify(!p.docsProc, "no listing before the section opens")
    p.showSection("documents")
    var proc = p.docsProc
    verify(proc, "listDocsProc")
    compare(proc.objectName, "listDocsProc")
    compare(p.app.nav.viewMode, "documents")
    compare(p.app.nav.section, "documents")
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
    p.app.nav.searchQuery = "design"
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
    compare(p.app.nav.viewMode, "board")
  }

  function test_opening_a_document_points_the_file_view_at_its_absolute_path() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.app.nav.cursorIndex = 1
    p.activateCursor()
    compare(p.app.nav.viewMode, "document")
    compare(p.app.nav.section, "documents")
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
    p.app.nav.cursorIndex = 0; p.activateCursor()
    var fv = named(p, "docFile")
    fv.stubText = "one"; fv.loaded(); compare(p.docText, "one")
    fv.stubText = "two"; fv.loaded(); compare(p.docText, "two")
  }

  function test_a_document_over_one_megabyte_is_not_loaded() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.app.nav.cursorIndex = 2; p.activateCursor()
    compare(p.app.nav.viewMode, "document")
    compare(p.docTooLargeFlag, true)
    compare(named(p, "docFile").path, "")
  }

  function test_a_read_failure_is_shown_with_back_available() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.app.nav.cursorIndex = 0; p.activateCursor()
    named(p, "docFile").loadFailed(1)
    compare(p.docError, "Could not read this document.")
    p.goBack()
    compare(p.app.nav.viewMode, "documents")
  }

  function test_back_restores_the_list_position() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.app.nav.cursorIndex = 1
    p.activateCursor()
    p.goBack()
    compare(p.app.nav.viewMode, "documents")
    compare(p.app.nav.cursorIndex, 1)
    compare(p.selectedDocPath, "")
  }

  function test_escape_from_the_documents_list_is_left_to_the_close_handler() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.goBack()
    compare(p.app.nav.viewMode, "documents")
  }

  function test_switching_project_reloads_the_documents_list() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.chooseProject(pB)
    compare(p.app.nav.viewMode, "board")
    p.showSection("documents")
    compare(p.docsProc.command[2], "/home/u/b")
    compare(p.docs.length, 0)
    compare(p.docsLoading, true)
  }

  function test_ctrl_1_leaves_an_open_document() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(docList, 0)
    p.app.nav.cursorIndex = 0; p.activateCursor()
    compare(p.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_1 }), true)
    compare(p.app.nav.viewMode, "board")
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
    p.app.nav.cursorIndex = 0; p.activateCursor()
    p.goBack()
    p.app.nav.cursorIndex = 1; p.activateCursor()
    named(p, "docFile").loadFailed(1)
    compare(p.docError, "Could not read this document.")
  }

  property string catList: '{"ok": true, "docs": [' +
    '{"path": "docs/architecture/a.md", "title": "Arch", "size": 1, "category": "architecture"},' +
    '{"path": "docs/specs/s.md", "title": "Spec One", "size": 1, "category": "specs"},' +
    '{"path": "docs/superpowers/specs/t.md", "title": "Spec Two", "size": 1, "category": "specs"},' +
    '{"path": "docs/audits/u.md", "title": "Audit", "size": 1, "category": "audits"}], "truncated": false}'

  function test_toggling_a_category_filters_and_toggling_again_clears() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(catList, 0)
    compare(p.filteredDocs.length, 4)
    p.toggleDocCategory("specs")
    compare(p.docCategory, "specs")
    compare(paths(p.filteredDocs), "docs/specs/s.md,docs/superpowers/specs/t.md")
    compare(paths(p.currentList()), "docs/specs/s.md,docs/superpowers/specs/t.md")
    p.toggleDocCategory("audits")
    compare(paths(p.filteredDocs), "docs/audits/u.md")
    p.toggleDocCategory("audits")
    compare(p.docCategory, "")
    compare(p.filteredDocs.length, 4)
  }

  function test_the_category_combines_with_the_search_query() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(catList, 0)
    p.toggleDocCategory("specs")
    p.app.nav.searchQuery = "two"
    compare(paths(p.filteredDocs), "docs/superpowers/specs/t.md")
    p.app.nav.searchQuery = "audit"
    compare(p.filteredDocs.length, 0)
  }

  function test_toggling_a_category_resets_the_cursor_to_the_first_row() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(catList, 0)
    p.app.nav.cursorIndex = 3
    p.toggleDocCategory("specs")
    compare(p.app.nav.cursorIndex, 0)
  }

  function test_switching_project_clears_the_category() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(catList, 0)
    p.toggleDocCategory("audits")
    p.selectProject(pB)
    compare(p.docCategory, "")
  }

  function test_hover_caused_by_keyboard_scrolling_does_not_steal_the_cursor() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(catList, 0)
    p.moveCursor(1)
    compare(p.app.nav.cursorIndex, 1)
    p.hoverCursor(0)
    compare(p.app.nav.cursorIndex, 1)
    wait(400)
    p.hoverCursor(0)
    compare(p.app.nav.cursorIndex, 0)
  }

  function tagFixture() {
    var p = make(); if (!p) return null
    p.showSection("documents")
    p.applyDocsResult(catList, 0)
    p.app.nav.cursorIndex = 1
    p.activateCursor()
    return p
  }

  function test_choosing_a_type_runs_the_helper_for_the_open_document() {
    var p = tagFixture(); if (!p) return
    compare(p.app.nav.viewMode, "document")
    compare(p.selectedDocCategory, "specs")
    p.setDocTag("audits")
    var proc = named(p, "setDocTagProc")
    verify(proc, "setDocTagProc")
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("set-doc-tag.py"))
    compare(proc.command[2], "/home/u/my proj")
    compare(proc.command[3], "docs/specs/s.md")
    compare(proc.command[4], "audits")
    compare(proc.running, true)
    compare(p.docTagBusy, true)
  }

  function test_a_successful_change_refreshes_the_list() {
    var p = tagFixture(); if (!p) return
    p.setDocTag("audits")
    p.applyDocTagResult('{"ok": true, "changed": true}', 0)
    compare(p.docTagBusy, false)
    compare(p.docTagError, "")
    compare(p.docsLoading, true)
    verify(p.docsProc, "list re-fetched")
    p.applyDocsResult(catList.replace('"path": "docs/specs/s.md", "title": "Spec One", "size": 1, "category": "specs"',
      '"path": "docs/specs/s.md", "title": "Spec One", "size": 1, "category": "audits"'), 0)
    compare(p.selectedDocCategory, "audits")
  }

  function test_a_failed_change_shows_the_error_and_keeps_the_document() {
    var p = tagFixture(); if (!p) return
    p.setDocTag("standards")
    p.applyDocTagResult('{"ok": false, "error": "Could not write the document: Permission denied"}', 1)
    compare(p.docTagBusy, false)
    compare(p.docTagError, "Could not write the document: Permission denied")
    compare(p.app.nav.viewMode, "document")
    p.setDocTag("standards")
    compare(p.docTagError, "")
  }

  function test_only_valid_types_and_one_change_at_a_time() {
    var p = tagFixture(); if (!p) return
    p.setDocTag("banana")
    compare(p.docTagBusy, false)
    p.setDocTag("audits")
    var proc = named(p, "setDocTagProc")
    var cmd = proc.command
    p.setDocTag("standards")
    compare(proc.command[4], "audits")
  }

  function test_choosing_a_type_outside_a_document_does_nothing() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(catList, 0)
    p.setDocTag("audits")
    compare(p.docTagBusy, false)
    verify(!named(p, "setDocTagProc") || !named(p, "setDocTagProc").running)
  }

  function test_the_picker_shows_the_current_type_and_reports_choices() {
    var p = tagFixture(); if (!p) return
    p.setDocTag("nope")
    var picker = null
    function walk(item) {
      if (item.objectName === "tagPicker") { picker = item; return }
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) if (!picker) walk(kids[i])
    }
    walk(p)
    verify(picker, "tagPicker")
    compare(picker.current, "specs")
    picker.tagChosen("standards")
    compare(named(p, "setDocTagProc").command[4], "standards")
  }

  function test_leaving_the_document_clears_the_tag_error() {
    var p = tagFixture(); if (!p) return
    p.setDocTag("audits")
    p.applyDocTagResult('{"ok": false, "error": "x"}', 1)
    p.goBack()
    compare(p.docTagError, "")
  }
}
