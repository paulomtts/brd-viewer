// tests/ui/screens/tst_documents_toolbar.qml
// ui/screens/DocumentsToolbar.qml on its own: the category chips of the
// documents list and the path + type picker of an open document, which all
// live in the panel's fixed toolbar instead of the scrolling content.
// REAL core/stores App and REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest
import "../../helpers/find.js" as H

TestCase {
  id: tc
  name: "DocumentsToolbar"
  when: windowShown
  visible: true
  width: 500; height: 300

  Component { id: hostC; Item { width: 500; height: 300 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "docs/architecture/a.md", "title": "Arch", "size": 1, "category": "architecture"},' +
    '{"path": "docs/specs/s.md", "title": "Spec One", "size": 1, "category": "specs"},' +
    '{"path": "docs/superpowers/specs/t.md", "title": "Spec Two", "size": 1, "category": "specs"}], "truncated": false}'

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
    var tC = Qt.createComponent("../../../ui/screens/DocumentsToolbar.qml")
    if (tC.status !== Component.Ready) { fail(tC.errorString()); return null }
    var t = tC.createObject(host, { app: app, navigator: nav, width: 500 })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    return t
  }

  function listed() {
    var t = make(); if (!t) return null
    t.navigator.showSection("documents")
    t.app.docs.applyDocsResult(docList, 0)
    wait(20)
    return t
  }

  function opened() {
    var t = listed(); if (!t) return null
    t.navigator.openDoc("docs/specs/s.md")
    wait(20)
    return t
  }

  function test_the_toolbar_shows_only_in_the_documents_and_document_views() {
    var t = make(); if (!t) return
    compare(t.visible, false)
    t.navigator.showSection("documents")
    t.app.docs.applyDocsResult(docList, 0)
    compare(t.visible, true)
    t.navigator.openDoc("docs/specs/s.md")
    compare(t.app.nav.viewMode, "document")
    compare(t.visible, true)
    t.navigator.showSection("board")
    compare(t.visible, false)
  }

  // ---- the documents list

  function test_category_chips_show_labels_and_counts() {
    var t = listed(); if (!t) return
    compare(H.find(t, "docChips").visible, true)
    compare(String(H.find(t, "docChiparchitecture").text), "Architecture 1")
    compare(String(H.find(t, "docChipspecs").text), "Specs 2")
    verify(!H.find(t, "docChipaudits"), "no chip for a category without documents")
  }

  function test_clicking_a_chip_toggles_the_store_category() {
    var t = listed(); if (!t) return
    var chip = H.find(t, "docChipspecs")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(t.app.docs.docCategory, "specs")
    wait(20)
    mouseClick(H.find(t, "docChipspecs"), 5, 5)
    compare(t.app.docs.docCategory, "")
  }

  function test_the_active_chip_is_marked() {
    var t = listed(); if (!t) return
    t.app.docs.toggleDocCategory("specs")
    wait(20)
    compare(H.find(t, "docChipspecs").active, true)
    compare(H.find(t, "docChiparchitecture").active, false)
    t.app.docs.toggleDocCategory("specs")
    wait(20)
    compare(H.find(t, "docChipspecs").active, false)
  }

  function test_the_chips_are_hidden_without_documents_and_while_loading_or_failed() {
    var t = make(); if (!t) return
    t.navigator.showSection("documents")
    wait(20)
    compare(H.find(t, "docChips").visible, false, "nothing listed yet")
    t.app.docs.applyDocsResult(docList, 0)
    wait(20)
    compare(H.find(t, "docChips").visible, true)
    t.app.docs.docsLoading = true
    compare(H.find(t, "docChips").visible, false)
    t.app.docs.docsLoading = false
    t.app.docs.docsError = "boom"
    compare(H.find(t, "docChips").visible, false)
  }

  function test_the_chips_are_hidden_once_a_document_is_open() {
    var t = opened(); if (!t) return
    compare(H.find(t, "docChips").visible, false)
  }

  // ---- the open document

  function test_the_open_documents_path_is_shown_elided_in_the_middle() {
    var t = opened(); if (!t) return
    var path = H.find(t, "docPath")
    verify(path, "the path caption")
    compare(String(path.text), "docs/specs/s.md")
    compare(path.elide, Text.ElideMiddle)
    compare(path.visible, true)
  }

  function test_the_path_and_the_picker_are_hidden_in_the_list() {
    var t = listed(); if (!t) return
    compare(H.find(t, "docPath").visible, false)
    compare(H.find(t, "tagPicker").visible, false)
  }

  function test_the_tag_picker_shows_the_current_type_and_sets_a_new_one() {
    var t = opened(); if (!t) return
    var picker = H.find(t, "tagPicker")
    verify(picker, "the TagPicker is inside the toolbar")
    compare(picker.current, t.app.docs.selectedDocCategory)
    compare(picker.current, "specs")
    var chip = H.find(t, "tagChipaudits")
    verify(chip, "the audits chip")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    verify(t.app.docs.tagger.current, "the toolbar asked the store to set the tag")
    compare(t.app.docs.tagger.current.command[4], "audits")
    compare(t.app.docs.docTagBusy, true)
  }
}
