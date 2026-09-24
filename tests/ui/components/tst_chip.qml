import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "Chip"
  when: windowShown
  visible: true
  width: 300; height: 120

  Component { id: chipC; UI.Chip { objectName: "chip"; text: "Specs 2"; tint: "#00ff00" } }
  SignalSpy { id: clicks; signalName: "clicked" }

  function make() {
    var chip = createTemporaryObject(chipC, tc)
    clicks.target = chip
    clicks.clear()
    return chip
  }

  function test_it_renders_the_text_in_a_bordered_pill() {
    var chip = make()
    compare(chip.text, "Specs 2")
    compare(chip.radius, chip.height / 2)
    compare(chip.border.width, 1)
    verify(chip.width > 0)
  }

  function test_the_active_chip_is_filled_and_bold() {
    var chip = make()
    var label = chip.children[0]
    compare(chip.active, false)
    compare(label.font.bold, false)
    compare(chip.color, Qt.alpha(Qt.color("#00ff00"), 0.12))
    chip.active = true
    compare(label.font.bold, true)
    compare(chip.color, Qt.alpha(Qt.color("#00ff00"), 0.35))
    compare(chip.border.color, Qt.color("#00ff00"))
  }

  function test_a_click_is_reported() {
    var chip = make()
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(clicks.count, 1)
  }

  function test_a_busy_chip_is_dimmed_and_ignores_clicks() {
    var chip = make()
    chip.busy = true
    compare(chip.opacity, 0.5)
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(clicks.count, 0)
  }
}
