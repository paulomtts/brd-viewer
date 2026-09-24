import QtQuick
import QtTest
import qs.Commons
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "ActionButton"
  when: windowShown
  visible: true
  width: 300; height: 120

  T.Theme { id: tcTheme; foreground: "#00ff00"; urgent: "#ff0000" }

  Component { id: normalC; UI.ActionButton { theme: tcTheme; text: "Save" } }
  Component { id: dangerC; UI.ActionButton { theme: tcTheme; text: "Delete"; tone: "danger" } }
  SignalSpy { id: clicks; signalName: "clicked" }

  function make(component) {
    var button = createTemporaryObject(component, tc)
    clicks.target = button
    clicks.clear()
    return button
  }

  function test_it_carries_the_shared_button_style() {
    var button = make(normalC)
    compare(button.text, "Save")
    compare(button.bordered, true)
    compare(button.foreground, Qt.color("#00ff00"))
    compare(button.fontFamily, Style.font.family)
    compare(button.fontSize, Style.font.bodySmall)
    compare(button.verticalPadding, Style.spacing.controlPaddingY)
  }

  function test_the_danger_tone_uses_the_urgent_colour() {
    var button = make(dangerC)
    compare(button.tone, "danger")
    compare(button.foreground, Qt.color("#ff0000"))
  }

  function test_a_disabled_button_is_dimmed() {
    var button = make(normalC)
    compare(button.opacity, 1)
    button.enabled = false
    compare(button.opacity, 0.5)
  }

  function test_it_reports_clicks() {
    var button = make(normalC)
    mouseClick(button, button.width / 2, button.height / 2)
    compare(clicks.count, 1)
  }
}
