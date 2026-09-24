// tests/ui/tst_documents_flow.qml
// What the panel still does around the documents store: the section change, the
// cursor, the view mode, going back and the type picker. The listing, the
// filters and the open document's state are tested in
// tests/core/stores/tst_documents_store.qml.
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
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA, pB])
    return p
  }
  function paths(list) { return list.map(function(d) { return d.path }).join(",") }

  function test_documents_are_enabled_and_fetched_when_the_section_opens() {
    var p = make(); if (!p) return
    compare(p.documentsEnabled, true)
    verify(!p.app.docs.lister.current, "no listing before the section opens")
    p.navigator.showSection("documents")
    var proc = p.app.docs.lister.current
    verify(proc, "a listing process")
    compare(p.app.nav.viewMode, "documents")
    compare(p.app.nav.section, "documents")
    compare(p.app.docs.docsLoading, true)
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("list-docs.py"))
    compare(proc.command[2], "/home/u/my proj")
    compare(proc.running, true)
  }

  function test_a_failed_listing_shows_the_error_and_keeps_the_board_usable() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult('{"ok": false, "error": "nope"}', 1)
    compare(p.app.docs.docsError, "nope")
    compare(p.app.docs.docs.length, 0)
    p.navigator.showSection("board")
    compare(p.app.nav.viewMode, "board")
  }

  // The keyboard list the panel walks is the filtered one the store computes.
  function test_the_current_list_follows_the_filtered_documents() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(docList, 0)
    compare(paths(p.navigator.currentList()), "README.md,docs/specs/Design Doc.md,docs/huge.md")
    p.app.nav.searchQuery = "design"
    compare(paths(p.navigator.currentList()), "docs/specs/Design Doc.md")
  }

  function test_a_read_failure_is_shown_with_back_available() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(docList, 0)
    p.app.nav.cursorIndex = 0; p.navigator.activateCursor()
    p.app.docs.docFile.loadFailed(1)
    compare(p.app.docs.docError, "Could not read this document.")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "documents")
  }

  function test_back_restores_the_list_position() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(docList, 0)
    p.app.nav.cursorIndex = 1
    p.navigator.activateCursor()
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "documents")
    compare(p.app.nav.cursorIndex, 1)
    compare(p.app.docs.selectedDocPath, "")
  }

  function test_escape_from_the_documents_list_is_left_to_the_close_handler() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "documents")
  }

  function test_switching_project_reloads_the_documents_list() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(docList, 0)
    p.navigator.chooseProject(pB)
    compare(p.app.nav.viewMode, "board")
    p.navigator.showSection("documents")
    compare(p.app.docs.lister.current.command[2], "/home/u/b")
    compare(p.app.docs.docs.length, 0)
    compare(p.app.docs.docsLoading, true)
  }

  function test_ctrl_1_leaves_an_open_document() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(docList, 0)
    p.app.nav.cursorIndex = 0; p.navigator.activateCursor()
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_1 }), true)
    compare(p.app.nav.viewMode, "board")
  }

  property string catList: '{"ok": true, "docs": [' +
    '{"path": "docs/architecture/a.md", "title": "Arch", "size": 1, "category": "architecture"},' +
    '{"path": "docs/specs/s.md", "title": "Spec One", "size": 1, "category": "specs"},' +
    '{"path": "docs/superpowers/specs/t.md", "title": "Spec Two", "size": 1, "category": "specs"},' +
    '{"path": "docs/audits/u.md", "title": "Audit", "size": 1, "category": "audits"}], "truncated": false}'

  function test_toggling_a_category_resets_the_cursor_to_the_first_row() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(catList, 0)
    p.app.nav.cursorIndex = 3
    p.app.docs.toggleDocCategory("specs")
    compare(p.app.nav.cursorIndex, 0)
    compare(paths(p.navigator.currentList()), "docs/specs/s.md,docs/superpowers/specs/t.md")
  }

  function test_hover_caused_by_keyboard_scrolling_does_not_steal_the_cursor() {
    var p = make(); if (!p) return
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(catList, 0)
    p.navigator.moveCursor(1)
    compare(p.app.nav.cursorIndex, 1)
    p.navigator.hoverCursor(0)
    compare(p.app.nav.cursorIndex, 1)
    wait(400)
    p.navigator.hoverCursor(0)
    compare(p.app.nav.cursorIndex, 0)
  }

  function tagFixture() {
    var p = make(); if (!p) return null
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(catList, 0)
    p.app.nav.cursorIndex = 1
    p.navigator.activateCursor()
    return p
  }

  function test_the_picker_shows_the_current_type_and_reports_choices() {
    var p = tagFixture(); if (!p) return
    compare(p.app.nav.viewMode, "document")
    p.app.docs.setDocTag("nope")
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
    compare(p.app.docs.tagger.current.command[4], "standards")
  }
}
