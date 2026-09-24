import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "ListRow"
  when: windowShown
  visible: true
  width: 400; height: 300

  T.Theme { id: tcTheme; foreground: "#00ff00" }

  Component {
    id: rowC
    UI.ListRow {
      width: 300
      theme: tcTheme
      UI.ThemedText { objectName: "rowLabel"; theme: tcTheme; width: parent.width; text: "a row" }
    }
  }

  SignalSpy { id: hoverSpy; signalName: "hovered" }
  SignalSpy { id: activateSpy; signalName: "activated" }
  SignalSpy { id: revealSpy; signalName: "revealRequested" }

  function make() {
    var row = createTemporaryObject(rowC, tc)
    var spies = [hoverSpy, activateSpy, revealSpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = row; spies[i].clear() }
    return row
  }

  function test_the_declared_children_are_the_rows_content() {
    var row = make()
    var label = H.find(row, "rowLabel")
    verify(label)
    compare(label.text, "a row")
    verify(row.implicitHeight > label.implicitHeight)
    compare(row.implicitHeight, label.implicitHeight + Style.spacing.rowPaddingX)
  }

  function test_the_cursor_is_on_the_row_whose_index_matches() {
    var row = make()
    row.index = 2
    compare(row.hasCursor, false)
    row.cursorIndex = 2
    compare(row.hasCursor, true)
    row.cursorIndex = 1
    compare(row.hasCursor, false)
  }

  function test_a_row_without_an_index_never_has_the_cursor() {
    var row = make()
    row.index = -1
    row.cursorIndex = -1
    compare(row.hasCursor, false)
  }

  function test_only_a_keyboard_move_asks_for_a_reveal() {
    var row = make()
    row.index = 1
    row.scrollOnCursor = false
    row.cursorIndex = 1
    compare(revealSpy.count, 0)
    row.cursorIndex = 0
    row.scrollOnCursor = true
    row.cursorIndex = 1
    compare(revealSpy.count, 1)
    compare(revealSpy.signalArguments[0][0], row)
  }

  function test_hovering_reports_the_index_and_clicking_activates() {
    var row = make()
    row.index = 3
    mouseMove(row, row.width / 2, row.height / 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 3)
    mouseClick(row, row.width / 2, row.height / 2)
    compare(activateSpy.count, 1)
  }

  function test_a_row_without_an_index_reports_no_hover() {
    var row = make()
    row.index = -1
    mouseMove(row, row.width / 2, row.height / 2)
    compare(hoverSpy.count, 0)
    mouseClick(row, row.width / 2, row.height / 2)
    compare(activateSpy.count, 1)
  }

  function test_the_content_is_inset_by_the_content_margin() {
    var row = make()
    var label = H.find(row, "rowLabel")
    compare(label.parent.x, Style.space(10))
    row.contentMargin = Style.space(6)
    compare(label.parent.x, Style.space(6))
  }

  function test_it_draws_with_the_themes_foreground() {
    var row = make()
    compare(row.foreground, Qt.color("#00ff00"))
  }
}
