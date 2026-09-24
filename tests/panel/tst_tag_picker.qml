import QtQuick
import QtTest
TestCase {
  id: tc
  name: "TagPicker"
  when: windowShown
  visible: true
  width: 500; height: 200

  Component { id: pickerC; TagPicker { width: 460 } }
  SignalSpy { id: chosen; signalName: "tagChosen" }

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    return null
  }
  function make() {
    var v = createTemporaryObject(pickerC, tc)
    chosen.target = v
    chosen.clear()
    return v
  }

  function test_it_offers_the_four_types_and_the_folder_default() {
    var v = make()
    var ids = ["architecture", "specs", "standards", "audits", "default"]
    for (var i = 0; i < ids.length; i++) verify(find(v, "tagChip" + ids[i]), ids[i])
    compare(find(v, "tagChipspecs").text, "Specs")
    compare(find(v, "tagChipdefault").text, "Folder default")
  }

  function test_clicking_a_chip_reports_its_id() {
    var v = make()
    var chip = find(v, "tagChipaudits")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0], "audits")
  }

  function test_the_current_type_is_marked() {
    var v = make()
    v.current = "standards"
    compare(find(v, "tagChipstandards").active, true)
    compare(find(v, "tagChipaudits").active, false)
    v.current = "other"
    compare(find(v, "tagChipstandards").active, false)
  }

  function test_it_ignores_clicks_while_busy_and_shows_an_error() {
    var v = make()
    v.busy = true
    var chip = find(v, "tagChipaudits")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(chosen.count, 0)
    v.busy = false
    compare(find(v, "tagError").visible, false)
    v.error = "boom"
    compare(find(v, "tagError").visible, true)
    compare(find(v, "tagError").text, "boom")
  }
}
