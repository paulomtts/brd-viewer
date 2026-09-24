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
  SignalSpy { id: categorySpy; signalName: "categoryToggled" }

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
    var spies = [chosen, hoverSpy, revealSpy, categorySpy]
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

  property var catDocs: [
    { path: "docs/architecture/a.md", title: "Arch", size: 1, category: "architecture" },
    { path: "docs/specs/s.md", title: "Spec", size: 1, category: "specs" }
  ]
  property var catCounts: [
    { id: "architecture", label: "Architecture", count: 1 },
    { id: "specs", label: "Specs", count: 2 }
  ]

  function test_category_chips_show_labels_and_counts() {
    var v = make()
    v.docs = catDocs
    v.categories = catCounts
    wait(20)
    compare(find(v, "docChips").visible, true)
    compare(find(v, "docChiparchitecture").text, "Architecture 1")
    compare(find(v, "docChipspecs").text, "Specs 2")
    verify(!find(v, "docChipaudits"))
  }

  function test_clicking_a_chip_asks_to_toggle_its_category() {
    var v = make()
    v.docs = catDocs
    v.categories = catCounts
    wait(20)
    var chip = find(v, "docChipspecs")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(categorySpy.count, 1)
    compare(categorySpy.signalArguments[0][0], "specs")
  }

  function test_the_active_chip_is_marked() {
    var v = make()
    v.docs = catDocs
    v.categories = catCounts
    v.activeCategory = "specs"
    wait(20)
    compare(find(v, "docChipspecs").active, true)
    compare(find(v, "docChiparchitecture").active, false)
    v.activeCategory = ""
    compare(find(v, "docChipspecs").active, false)
  }

  function test_chips_are_hidden_without_categories_and_while_loading_or_failed() {
    var v = make()
    compare(find(v, "docChips").visible, false)
    v.categories = catCounts
    v.docs = catDocs
    wait(20)
    compare(find(v, "docChips").visible, true)
    v.loading = true
    compare(find(v, "docChips").visible, false)
    v.loading = false
    v.error = "boom"
    compare(find(v, "docChips").visible, false)
  }

  function test_rows_carry_their_category_badge() {
    var v = make()
    v.docs = catDocs
    wait(20)
    compare(find(v, "docRowBadge0").text, "Architecture")
    compare(find(v, "docRowBadge1").text, "Specs")
    v.docs = [{ path: "x.md", title: "X", size: 1 }]
    wait(20)
    compare(find(v, "docRowBadge0").visible, false)
  }

  function test_the_empty_message_names_the_active_category() {
    var v = make()
    v.categories = catCounts
    v.activeCategory = "specs"
    compare(find(v, "docsMessage").text, "No Specs documents.")
    v.query = "zz"
    compare(find(v, "docsMessage").text, "No documents match “zz”.")
    v.query = ""
    v.activeCategory = ""
    compare(find(v, "docsMessage").text, "No Markdown documents found in this project.")
  }
}
