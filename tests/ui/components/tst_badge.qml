import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "Badge"
  when: windowShown
  visible: true
  width: 300; height: 120

  Component { id: badgeC; UI.Badge { text: "Specs"; tint: "#00ff00"; textObjectName: "badgeLabel" } }

  function make() { return createTemporaryObject(badgeC, tc) }

  function test_it_shows_the_text_in_the_tint_colour() {
    var badge = make()
    var label = H.find(badge, "badgeLabel")
    verify(label)
    compare(label.text, "Specs")
    compare(label.color, Qt.color("#00ff00"))
  }

  function test_the_pill_is_fully_rounded_and_filled_with_the_faded_tint() {
    var badge = make()
    compare(badge.radius, badge.height / 2)
    compare(badge.color, Qt.alpha(Qt.color("#00ff00"), 0.18))
    verify(badge.width > 0)
  }

  function test_the_text_uses_the_theme_caption_font() {
    var badge = make()
    var label = H.find(badge, "badgeLabel")
    compare(label.font.family, Style.font.family)
    compare(label.font.pixelSize, Style.font.caption)
  }
}
