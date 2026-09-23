import QtQuick
import QtTest
TestCase {
  id: tc
  name: "DocumentsView"
  when: windowShown
  visible: true
  width: 400; height: 500

  Component { id: viewC; DocumentsView { width: 360 } }
  SignalSpy { id: chosen; signalName: "docChosen" }
  SignalSpy { id: hoverSpy; signalName: "hovered" }
  SignalSpy { id: revealSpy; signalName: "revealRequested" }

  property var docs: [
    { path: "README.md", title: "Readme", size: 10 },
    { path: "docs/plan.md", title: "Plan", size: 20 }
  ]

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function make() {
    var v = createTemporaryObject(viewC, tc)
    var spies = [chosen, hoverSpy, revealSpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = v; spies[i].clear() }
    return v
  }

  function test_rows_render_and_choose_by_path() {
    var v = make()
    v.docs = docs
    wait(20)
    verify(find(v, "docRow1"))
    verify(!find(v, "docRow2"))
    var row = find(v, "docRow1")
    mouseClick(row, row.width / 2, row.height / 2)
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0], "docs/plan.md")
  }

  function test_hover_reports_the_index() {
    var v = make()
    v.docs = docs
    wait(20)
    var row = find(v, "docRow1")
    mouseMove(row, row.width / 2, row.height / 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 1)
  }

  function test_cursor_row_requests_a_reveal_only_for_keyboard_moves() {
    var v = make()
    v.docs = docs
    wait(20)
    v.scrollOnCursor = false
    v.cursorIndex = 1
    compare(revealSpy.count, 0)
    v.scrollOnCursor = true
    v.cursorIndex = 0
    compare(revealSpy.count, 1)
  }

  function test_messages() {
    var v = make()
    v.loading = true
    compare(find(v, "docsMessage").text, "Loading documents…")
    v.loading = false
    compare(find(v, "docsMessage").text, "No Markdown documents found in this project.")
    v.query = "zz"
    compare(find(v, "docsMessage").text, "No documents match “zz”.")
    v.error = "boom"
    compare(find(v, "docsMessage").text, "boom")
    v.error = ""
    v.docs = docs
    compare(find(v, "docsMessage").visible, false)
  }

  function test_truncated_note() {
    var v = make()
    v.docs = docs
    v.truncated = true
    compare(find(v, "docsTruncated").visible, true)
    v.truncated = false
    compare(find(v, "docsTruncated").visible, false)
  }
}
