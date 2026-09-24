// tests/core/stores/tst_documents_store.qml
// The documents listing, the category filter, the open document (its live text
// and its type tag) -- driven through App so the wiring to the project and
// navigation stores is exercised too. Scrolling, focus and the view mode stay
// in the panel and are tested in tests/ui/tst_documents_flow.qml.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresDocumentsStore"

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "README.md", "title": "Readme", "size": 100},' +
    '{"path": "docs/specs/Design Doc.md", "title": "Design", "size": 200},' +
    '{"path": "docs/huge.md", "title": "Huge", "size": 2000000}], "truncated": false}'
  property string catList: '{"ok": true, "docs": [' +
    '{"path": "docs/architecture/a.md", "title": "Arch", "size": 1, "category": "architecture"},' +
    '{"path": "docs/specs/s.md", "title": "Spec One", "size": 1, "category": "specs"},' +
    '{"path": "docs/superpowers/specs/t.md", "title": "Spec Two", "size": 1, "category": "specs"},' +
    '{"path": "docs/audits/u.md", "title": "Audit", "size": 1, "category": "audits"}], "truncated": false}'

  function make() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var app = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    return app
  }
  // What the panel does around the store when the Documents section opens.
  function showDocuments(app) { app.nav.viewMode = "documents"; app.docs.fetchDocs() }
  function open(app, path) { if (app.docs.openDoc(path)) app.nav.viewMode = "document" }
  function paths(list) { return list.map(function(d) { return d.path }).join(",") }

  function test_the_listing_runs_the_helper_for_the_selected_project() {
    var app = make(); if (!app) return
    verify(!app.docs.lister.current, "no listing before the section opens")
    showDocuments(app)
    var proc = app.docs.lister.current
    verify(proc, "a listing process")
    compare(app.docs.docsLoading, true)
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("list-docs.py"))
    compare(proc.command[2], "/home/u/my proj")
    compare(proc.running, true)
  }

  function test_the_result_fills_the_list_and_filtering_works() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(docList, 0)
    compare(app.docs.docsLoading, false)
    compare(paths(app.docs.docs), "README.md,docs/specs/Design Doc.md,docs/huge.md")
    app.nav.searchQuery = "design"
    compare(paths(app.docs.filteredDocs), "docs/specs/Design Doc.md")
  }

  function test_a_normal_single_run_fills_the_list() {
    var app = make(); if (!app) return
    showDocuments(app)
    var proc = app.docs.lister.current
    compare(proc.command[2], "/home/u/my proj")
    proc.outText = docList
    proc.exited(0)
    compare(app.docs.docs.length, 3)
    compare(app.docs.docsLoading, false)
    compare(app.docs.docsError, "")
  }

  function test_a_stale_exit_before_the_newer_run_completes_is_ignored() {
    var app = make(); if (!app) return
    showDocuments(app)
    var first = app.docs.lister.current
    app.docs.fetchDocs()
    var second = app.docs.lister.current
    verify(first !== second, "each launch has its own process")
    compare(first.running, false)
    first.outText = ""
    first.exited(1)
    compare(app.docs.docsError, "")
    compare(app.docs.docsLoading, true)
    second.outText = docList
    second.exited(0)
    compare(app.docs.docs.length, 3)
  }

  function test_a_stale_exit_after_the_newer_run_finished_keeps_the_good_list() {
    var app = make(); if (!app) return
    showDocuments(app)
    var first = app.docs.lister.current
    app.docs.fetchDocs()
    var second = app.docs.lister.current
    second.outText = docList
    second.exited(0)
    compare(app.docs.docs.length, 3)
    first.outText = ""
    first.exited(1)
    compare(app.docs.docs.length, 3)
    compare(app.docs.docsError, "")
    compare(app.docs.docsLoading, false)
  }

  function test_a_late_exit_from_the_previous_project_is_ignored() {
    var app = make(); if (!app) return
    showDocuments(app)
    var first = app.docs.lister.current
    compare(first.command[2], "/home/u/my proj")
    app.projects.chooseProject(pB)
    showDocuments(app)
    var second = app.docs.lister.current
    compare(second.command[2], "/home/u/b")
    second.outText = docList
    second.exited(0)
    compare(app.docs.docs.length, 3)
    first.outText = '{"ok": false, "error": "old"}'
    first.exited(1)
    compare(app.docs.docs.length, 3)
    compare(app.docs.docsError, "")
  }

  function test_a_late_exit_after_leaving_the_project_before_any_refetch_is_ignored() {
    var app = make(); if (!app) return
    showDocuments(app)
    var first = app.docs.lister.current
    app.projects.chooseProject(pB)
    first.outText = docList
    first.exited(0)
    compare(app.docs.docs.length, 0)
  }

  function test_opening_a_document_points_the_file_view_at_its_absolute_path() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(docList, 0)
    open(app, "docs/specs/Design Doc.md")
    compare(app.docs.selectedDocPath, "docs/specs/Design Doc.md")
    var fv = app.docs.docFile
    verify(fv, "docFile")
    compare(fv.path, "/home/u/my proj/docs/specs/Design Doc.md")
    compare(fv.watchChanges, true)
    fv.stubText = "# Design\n\nbody"
    fv.loaded()
    compare(app.docs.docText, "# Design\n\nbody")
  }

  function test_a_file_change_reloads_the_text() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(docList, 0)
    open(app, "README.md")
    var fv = app.docs.docFile
    fv.stubText = "one"; fv.loaded(); compare(app.docs.docText, "one")
    fv.stubText = "two"; fv.loaded(); compare(app.docs.docText, "two")
  }

  function test_a_document_over_one_megabyte_is_not_loaded() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(docList, 0)
    open(app, "docs/huge.md")
    compare(app.docs.docTooLargeFlag, true)
    compare(app.docs.docFile.path, "")
  }

  function test_a_read_failure_while_in_the_list_does_not_set_an_error() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(docList, 0)
    compare(app.docs.docFile.path, "")
    app.docs.docFile.loadFailed(1)
    compare(app.docs.docError, "")
  }

  function test_a_stale_read_failure_does_not_poison_the_next_document() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(docList, 0)
    open(app, "README.md")
    app.docs.restoreDocumentsList()
    app.nav.viewMode = "documents"
    open(app, "docs/specs/Design Doc.md")
    app.docs.docFile.loadFailed(1)
    compare(app.docs.docError, "Could not read this document.")
  }

  function test_toggling_a_category_filters_and_toggling_again_clears() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(catList, 0)
    compare(app.docs.filteredDocs.length, 4)
    app.docs.toggleDocCategory("specs")
    compare(app.docs.docCategory, "specs")
    compare(paths(app.docs.filteredDocs), "docs/specs/s.md,docs/superpowers/specs/t.md")
    app.docs.toggleDocCategory("audits")
    compare(paths(app.docs.filteredDocs), "docs/audits/u.md")
    app.docs.toggleDocCategory("audits")
    compare(app.docs.docCategory, "")
    compare(app.docs.filteredDocs.length, 4)
  }

  function test_the_category_combines_with_the_search_query() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(catList, 0)
    app.docs.toggleDocCategory("specs")
    app.nav.searchQuery = "two"
    compare(paths(app.docs.filteredDocs), "docs/superpowers/specs/t.md")
    app.nav.searchQuery = "audit"
    compare(app.docs.filteredDocs.length, 0)
  }

  // The cursor reset is the panel's: the store only says the category changed.
  function test_toggling_a_category_announces_it_and_resets_the_cursor() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(catList, 0)
    var spy = Qt.createQmlObject('import QtTest; SignalSpy {}', tc)
    spy.target = app.docs
    spy.signalName = "categoryToggled"
    app.nav.cursorIndex = 3
    app.nav.scrollOnCursor = true
    app.docs.toggleDocCategory("specs")
    compare(spy.count, 1)
    compare(app.nav.cursorIndex, 0)
    compare(app.nav.scrollOnCursor, false)
  }

  function test_switching_project_clears_the_category() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(catList, 0)
    app.docs.toggleDocCategory("audits")
    app.projects.selectProject(pB)
    compare(app.docs.docCategory, "")
  }

  // A project change clears every document the old project left behind.
  function test_switching_project_clears_the_documents_state() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(docList, 0)
    open(app, "docs/specs/Design Doc.md")
    app.docs.docText = "body"
    app.docs.docError = "boom"
    app.docs.docTagError = "nope"
    app.projects.chooseProject(pB)
    compare(app.docs.docs.length, 0)
    compare(app.docs.docsError, "")
    compare(app.docs.docsLoading, false)
    compare(app.docs.selectedDocPath, "")
    compare(app.docs.docText, "")
    compare(app.docs.docError, "")
    compare(app.docs.docTagError, "")
    compare(app.docs.docTooLargeFlag, false)
  }

  function tagFixture() {
    var app = make(); if (!app) return null
    showDocuments(app)
    app.docs.applyDocsResult(catList, 0)
    open(app, "docs/specs/s.md")
    return app
  }

  function test_choosing_a_type_runs_the_helper_for_the_open_document() {
    var app = tagFixture(); if (!app) return
    compare(app.docs.selectedDocCategory, "specs")
    app.docs.setDocTag("audits")
    var proc = app.docs.tagger.current
    verify(proc, "a tagging process")
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("set-doc-tag.py"))
    compare(proc.command[2], "/home/u/my proj")
    compare(proc.command[3], "docs/specs/s.md")
    compare(proc.command[4], "audits")
    compare(proc.running, true)
    compare(app.docs.docTagBusy, true)
  }

  function test_a_successful_change_refreshes_the_list() {
    var app = tagFixture(); if (!app) return
    app.docs.setDocTag("audits")
    app.docs.applyDocTagResult('{"ok": true, "changed": true}', 0)
    compare(app.docs.docTagBusy, false)
    compare(app.docs.docTagError, "")
    compare(app.docs.docsLoading, true)
    verify(app.docs.lister.current, "list re-fetched")
    app.docs.applyDocsResult(catList.replace('"path": "docs/specs/s.md", "title": "Spec One", "size": 1, "category": "specs"',
      '"path": "docs/specs/s.md", "title": "Spec One", "size": 1, "category": "audits"'), 0)
    compare(app.docs.selectedDocCategory, "audits")
  }

  function test_a_failed_change_shows_the_error_and_keeps_the_document() {
    var app = tagFixture(); if (!app) return
    app.docs.setDocTag("standards")
    app.docs.applyDocTagResult('{"ok": false, "error": "Could not write the document: Permission denied"}', 1)
    compare(app.docs.docTagBusy, false)
    compare(app.docs.docTagError, "Could not write the document: Permission denied")
    compare(app.docs.selectedDocPath, "docs/specs/s.md")
    app.docs.setDocTag("standards")
    compare(app.docs.docTagError, "")
  }

  function test_only_valid_types_and_one_change_at_a_time() {
    var app = tagFixture(); if (!app) return
    app.docs.setDocTag("banana")
    compare(app.docs.docTagBusy, false)
    app.docs.setDocTag("audits")
    var proc = app.docs.tagger.current
    app.docs.setDocTag("standards")
    compare(proc.command[4], "audits")
    compare(app.docs.tagger.current, proc)
  }

  function test_choosing_a_type_outside_a_document_does_nothing() {
    var app = make(); if (!app) return
    showDocuments(app)
    app.docs.applyDocsResult(catList, 0)
    app.docs.setDocTag("audits")
    compare(app.docs.docTagBusy, false)
    verify(!app.docs.tagger.current, "no tagging process")
  }

  // A late answer from the project the user has left must not touch the new one.
  function test_a_late_tag_exit_from_the_previous_project_is_ignored() {
    var app = tagFixture(); if (!app) return
    app.docs.setDocTag("audits")
    var proc = app.docs.tagger.current
    app.projects.chooseProject(pB)
    proc.outText = '{"ok": false, "error": "old"}'
    proc.exited(1)
    compare(app.docs.docTagError, "")
    compare(app.docs.docTagBusy, false, "the abandoned change must not hold the lock")
  }

  // Leaving a project while a change is in flight must not lock the picker for
  // the rest of the session: the next project can still change a type.
  function test_a_tag_change_abandoned_by_a_project_switch_does_not_lock_the_picker() {
    var app = tagFixture(); if (!app) return
    app.docs.setDocTag("audits")
    var abandoned = app.docs.tagger.current
    app.projects.selectProject(pB)
    abandoned.outText = '{"ok": true, "changed": true}'
    abandoned.exited(0)
    compare(app.docs.docTagBusy, false)
    showDocuments(app)
    app.docs.applyDocsResult(catList, 0)
    open(app, "docs/specs/s.md")
    app.docs.setDocTag("audits")
    compare(app.docs.docTagBusy, true)
    var proc = app.docs.tagger.current
    verify(proc, "a tagging process for the new project")
    compare(proc.command[2], "/home/u/b")
    compare(proc.command[3], "docs/specs/s.md")
    compare(proc.command[4], "audits")
  }

  // Staying in the project and only leaving the document: the helper's own exit
  // still releases the lock.
  function test_leaving_the_document_still_releases_the_lock_when_the_helper_exits() {
    var app = tagFixture(); if (!app) return
    app.docs.setDocTag("audits")
    var proc = app.docs.tagger.current
    app.docs.restoreDocumentsList()
    app.nav.viewMode = "documents"
    compare(app.docs.docTagBusy, true, "the change is still in flight")
    proc.outText = '{"ok": true, "changed": true}'
    proc.exited(0)
    compare(app.docs.docTagBusy, false)
  }

  function test_leaving_the_document_clears_the_tag_error() {
    var app = tagFixture(); if (!app) return
    app.docs.setDocTag("audits")
    app.docs.applyDocTagResult('{"ok": false, "error": "x"}', 1)
    app.docs.restoreDocumentsList()
    compare(app.docs.docTagError, "")
  }
}
