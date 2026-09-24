import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "FilterableList"
  when: windowShown
  visible: true
  width: 400; height: 500

  T.Theme { id: tcTheme; foreground: "#00ff00" }

  Component {
    id: listC
    UI.FilterableList {
      width: 360
      theme: tcTheme
      chipsObjectName: "myChips"
      chipPrefix: "myChip"
      statusObjectName: "myStatus"
      loadingText: "Loading things…"
      emptyText: "Nothing here."
      filteredText: "Nothing matches."
      rowDelegate: Component {
        UI.ListRow {
          required property var modelData
          required index
          objectName: "myRow" + index
          width: 360
          theme: tcTheme
          UI.ThemedText { objectName: "myRowLabel" + parent.parent.index; theme: tcTheme; text: parent.parent.modelData.label }
        }
      }
    }
  }

  SignalSpy { id: chipSpy; signalName: "chipToggled" }

  property var rows: [{ label: "one" }, { label: "two" }]
  property var chips: [{ id: "a", label: "Alpha", count: 1 }, { id: "b", label: "Beta", count: 2 }]

  function make() {
    var list = createTemporaryObject(listC, tc)
    chipSpy.target = list
    chipSpy.clear()
    return list
  }

  function test_the_chips_carry_the_prefix_the_label_and_the_count() {
    var list = make()
    list.chips = chips
    wait(20)
    compare(H.find(list, "myChips").visible, true)
    compare(H.find(list, "myChipa").text, "Alpha 1")
    compare(H.find(list, "myChipb").text, "Beta 2")
  }

  function test_clicking_a_chip_reports_its_id() {
    var list = make()
    list.chips = chips
    wait(20)
    var chip = H.find(list, "myChipb")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(chipSpy.count, 1)
    compare(chipSpy.signalArguments[0][0], "b")
  }

  function test_the_active_chip_is_marked() {
    var list = make()
    list.chips = chips
    list.activeChip = "b"
    wait(20)
    compare(H.find(list, "myChipb").active, true)
    compare(H.find(list, "myChipa").active, false)
  }

  function test_the_chips_are_hidden_without_chips_and_while_loading_or_failed() {
    var list = make()
    compare(H.find(list, "myChips").visible, false)
    list.chips = chips
    wait(20)
    compare(H.find(list, "myChips").visible, true)
    list.loading = true
    compare(H.find(list, "myChips").visible, false)
    list.loading = false
    list.error = "boom"
    compare(H.find(list, "myChips").visible, false)
  }

  function test_the_rows_come_from_the_model_through_the_row_delegate() {
    var list = make()
    list.model = rows
    wait(20)
    verify(H.find(list, "myRow0"))
    verify(H.find(list, "myRow1"))
    verify(!H.find(list, "myRow2"))
    compare(H.find(list, "myRowLabel1").text, "two")
  }

  function test_no_rows_are_shown_while_loading_or_after_an_error() {
    var list = make()
    list.model = rows
    wait(20)
    verify(H.find(list, "myRow0"))
    list.loading = true
    wait(20)
    verify(!H.find(list, "myRow0"))
    list.loading = false
    list.error = "boom"
    wait(20)
    verify(!H.find(list, "myRow0"))
  }

  function test_the_status_line_follows_the_lists_state() {
    var list = make()
    list.loading = true
    compare(H.find(list, "myStatus").text, "Loading things…")
    list.loading = false
    list.empty = true
    compare(H.find(list, "myStatus").text, "Nothing here.")
    list.filtered = true
    compare(H.find(list, "myStatus").text, "Nothing matches.")
    list.error = "boom"
    compare(H.find(list, "myStatus").text, "boom")
    list.error = ""
    list.empty = false
    compare(H.find(list, "myStatus").visible, false)
  }
}
