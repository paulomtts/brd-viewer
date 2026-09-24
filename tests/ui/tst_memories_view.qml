import QtQuick
import QtTest
import "../.."
TestCase {
  id: tc
  name: "MemoriesView"
  when: windowShown
  visible: true
  width: 400; height: 500

  Component { id: viewC; MemoriesView { width: 360 } }
  SignalSpy { id: chosen; signalName: "noteChosen" }
  SignalSpy { id: hoverSpy; signalName: "hovered" }
  SignalSpy { id: revealSpy; signalName: "revealRequested" }
  SignalSpy { id: typeSpy; signalName: "typeToggled" }

  property var notes: [
    { file: "user_role.md", name: "Role", description: "data scientist", type: "user", size: 1, indexed: true },
    { file: "feedback_a.md", name: "Terse", description: "", type: "feedback", size: 1, indexed: false }
  ]
  property var counts: [{ id: "user", label: "User", count: 1 }, { id: "feedback", label: "Feedback", count: 1 }]

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function make() {
    var v = createTemporaryObject(viewC, tc)
    var spies = [chosen, hoverSpy, revealSpy, typeSpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = v; spies[i].clear() }
    return v
  }

  function test_rows_show_name_description_and_type_and_choose_by_file() {
    var v = make()
    v.notes = notes
    wait(20)
    compare(find(v, "memoryRowTitle0").text, "Role")
    compare(find(v, "memoryRowDescription0").text, "data scientist")
    compare(find(v, "memoryRowDescription1").visible, false)
    compare(find(v, "memoryRowBadge0").text, "User")
    compare(find(v, "memoryRowBadge1").text, "Feedback")
    var row = find(v, "memoryRow1")
    mouseClick(row, row.width / 2, row.height / 2)
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0], "feedback_a.md")
  }

  function test_hover_and_reveal() {
    var v = make()
    v.notes = notes
    wait(20)
    var row = find(v, "memoryRow1")
    mouseMove(row, row.width / 2, row.height / 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 1)
    v.scrollOnCursor = false
    v.cursorIndex = 1
    compare(revealSpy.count, 0)
    v.scrollOnCursor = true
    v.cursorIndex = 0
    compare(revealSpy.count, 1)
  }

  function test_type_chips_show_counts_toggle_and_mark_the_active_one() {
    var v = make()
    v.notes = notes
    v.types = counts
    wait(20)
    compare(find(v, "memoryChips").visible, true)
    compare(find(v, "memoryChipuser").text, "User 1")
    verify(!find(v, "memoryChipproject"))
    var chip = find(v, "memoryChipfeedback")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(typeSpy.signalArguments[0][0], "feedback")
    v.activeType = "feedback"
    compare(find(v, "memoryChipfeedback").active, true)
    compare(find(v, "memoryChipuser").active, false)
    v.loading = true
    compare(find(v, "memoryChips").visible, false)
  }

  function test_messages() {
    var v = make()
    v.loading = true
    compare(find(v, "memoriesMessage").text, "Loading memories…")
    v.loading = false
    v.found = false
    compare(find(v, "memoriesMessage").text, "Claude Code has no memory for this project yet.")
    v.found = true
    compare(find(v, "memoriesMessage").text, "No memories yet. Use ＋ New to add one.")
    v.activeType = "user"
    v.types = counts
    compare(find(v, "memoriesMessage").text, "No User memories.")
    v.query = "zz"
    compare(find(v, "memoriesMessage").text, "No memories match “zz”.")
    v.error = "boom"
    compare(find(v, "memoriesMessage").text, "boom")
    v.error = ""
    v.query = ""
    v.activeType = ""
    v.notes = notes
    compare(find(v, "memoriesMessage").visible, false)
  }
}
