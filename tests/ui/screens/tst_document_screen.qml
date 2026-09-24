// tests/ui/screens/tst_document_screen.qml
// ui/screens/DocumentScreen.qml on its own: the open document's path, its type
// picker, the too-large and read-error messages, and the rendered body.
// REAL core/stores App -- no bespoke mocks.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "DocumentScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "README.md", "title": "Readme", "size": 100},' +
    '{"path": "docs/specs/Design Doc.md", "title": "Design", "size": 200},' +
    '{"path": "docs/huge.md", "title": "Huge", "size": 2000000}], "truncated": false}'

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
    var sC = Qt.createComponent("../../../ui/screens/DocumentScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 500 })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    app.nav.viewMode = "documents"
    app.docs.applyDocsResult(docList, 0)
    return s
  }

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    return null
  }

  function texts(item, out) {
    out = out || []
    if (item.visible === false) return out
    if (item.text !== undefined && String(item.text) !== "") out.push(String(item.text))
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) texts(kids[i], out)
    return out
  }

  function test_the_document_screen_shows_only_in_the_open_document_view() {
    var s = make(); if (!s) return
    compare(s.visible, false)
    s.navigator.openDoc("README.md")
    compare(s.app.nav.viewMode, "document")
    compare(s.visible, true)
  }

  function test_the_open_documents_path_is_shown_while_it_loads() {
    var s = make(); if (!s) return
    s.navigator.openDoc("docs/specs/Design Doc.md")
    wait(50)
    var t = texts(s)
    verify(t.indexOf("docs/specs/Design Doc.md") >= 0, t.join(" | "))
    verify(t.indexOf("Loading…") >= 0, t.join(" | "))
  }

  function test_the_body_is_rendered_once_it_arrives() {
    var s = make(); if (!s) return
    s.navigator.openDoc("README.md")
    s.app.docs.docFile.stubText = "# Title\n\nbody text"
    s.app.docs.docFile.loaded()
    wait(50)
    var t = texts(s)
    verify(t.join(" | ").indexOf("body text") >= 0, t.join(" | "))
    verify(t.indexOf("Loading…") < 0, "no loading placeholder once the text is in")
  }

  function test_a_document_that_is_too_large_says_so_instead_of_a_body() {
    var s = make(); if (!s) return
    s.navigator.openDoc("docs/huge.md")
    wait(50)
    compare(s.app.docs.docTooLargeFlag, true)
    verify(texts(s).indexOf("This document is too large to display.") >= 0, texts(s).join(" | "))
  }

  function test_a_read_error_is_shown_instead_of_a_body() {
    var s = make(); if (!s) return
    s.navigator.openDoc("README.md")
    s.app.docs.docFile.loadFailed(1)
    wait(50)
    compare(s.app.docs.docError, "Could not read this document.")
    var t = texts(s)
    verify(t.indexOf("Could not read this document.") >= 0, t.join(" | "))
    verify(t.indexOf("Loading…") < 0)
  }

  function test_the_tag_picker_shows_the_current_type_and_sets_a_new_one() {
    var s = make(); if (!s) return
    s.app.docs.applyDocsResult('{"ok": true, "docs": [' +
      '{"path": "docs/specs/Design Doc.md", "title": "Design", "size": 200, "category": "specs"}], "truncated": false}', 0)
    s.navigator.openDoc("docs/specs/Design Doc.md")
    wait(50)
    var picker = find(s, "tagPicker")
    verify(picker, "the TagPicker is inside the screen")
    compare(picker.current, s.app.docs.selectedDocCategory)
    var chip = find(s, "tagChipaudits")
    verify(chip, "the audits chip")
    mouseClick(chip)
    verify(s.app.docs.tagger.current, "the screen asked the store to set the tag")
    compare(s.app.docs.docTagBusy, true)
  }
}
