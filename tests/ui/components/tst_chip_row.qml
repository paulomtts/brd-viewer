import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "ChipRow"
  when: windowShown
  visible: true
  width: 400; height: 200

  property var counted: [
    { id: "specs", label: "Specs", count: 2, tint: "#00ff00" },
    { id: "audits", label: "Audits", count: 1, tint: "#ff00ff" }
  ]
  property var plain: [{ id: "default", label: "Folder default", tint: "#00ff00" }]

  Component { id: rowC; UI.ChipRow { width: 380; chipPrefix: "tagChip" } }
  SignalSpy { id: chosen; signalName: "chosen" }

  function make(model) {
    var row = createTemporaryObject(rowC, tc)
    row.model = model
    chosen.target = row
    chosen.clear()
    wait(20)
    return row
  }

  function test_each_entry_becomes_a_prefixed_chip() {
    var row = make(counted)
    verify(H.find(row, "tagChipspecs"))
    verify(H.find(row, "tagChipaudits"))
    verify(!H.find(row, "tagChipother"))
  }

  function test_a_count_is_appended_to_the_label() {
    var row = make(counted)
    compare(H.find(row, "tagChipspecs").text, "Specs 2")
    var bare = make(plain)
    compare(H.find(bare, "tagChipdefault").text, "Folder default")
  }

  function test_the_active_id_marks_its_chip() {
    var row = make(counted)
    row.active = "audits"
    compare(H.find(row, "tagChipaudits").active, true)
    compare(H.find(row, "tagChipspecs").active, false)
  }

  function test_clicking_a_chip_reports_its_id() {
    var row = make(counted)
    var chip = H.find(row, "tagChipaudits")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0], "audits")
  }

  function test_busy_reaches_the_chips_and_suppresses_clicks() {
    var row = make(counted)
    row.busy = true
    var chip = H.find(row, "tagChipspecs")
    compare(chip.busy, true)
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(chosen.count, 0)
  }
}
