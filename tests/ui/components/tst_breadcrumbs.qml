// tests/ui/components/tst_breadcrumbs.qml
// ui/components/Breadcrumbs.qml on its own: the trail it renders from a plain
// [{ label, clickable }] list, which crumb is the current one, and the clicks
// it reports. It knows nothing about the panel's navigation.
import QtQuick
import QtTest
import "../../../ui/components" as UI
import "../../helpers/find.js" as H

TestCase {
  id: tc
  name: "Breadcrumbs"
  when: windowShown
  visible: true
  width: 500; height: 120

  Component { id: bcC; UI.Breadcrumbs { width: 460 } }
  SignalSpy { id: activated; signalName: "crumbActivated" }

  function make(crumbs) {
    var bc = createTemporaryObject(bcC, tc)
    bc.crumbs = crumbs
    activated.target = bc
    activated.clear()
    wait(20)
    return bc
  }

  property var trail: [
    { label: "Board", clickable: true },
    { label: "Milestone", clickable: true },
    { label: "The open card", clickable: false }
  ]

  function test_one_crumb_per_entry_with_the_last_one_as_the_heading() {
    var bc = make(trail)
    verify(H.find(bc, "crumb0"), "the section crumb")
    verify(H.find(bc, "crumb1"), "the ancestor crumb")
    verify(H.find(bc, "crumb2"), "the current crumb")
    verify(!H.find(bc, "crumb3"), "and nothing beyond the trail")
    compare(String(H.find(bc, "crumbText0").text), "Board")
    compare(String(H.find(bc, "crumbText1").text), "Milestone")
    var heading = H.find(bc, "projectHeading")
    verify(heading, "the last crumb keeps the heading's object name")
    compare(String(heading.text), "The open card")
    compare(heading.font.bold, true)
  }

  function test_only_the_crumbs_after_the_first_carry_a_separator() {
    var bc = make(trail)
    compare(H.find(bc, "crumbSeparator0").visible, false)
    compare(H.find(bc, "crumbSeparator1").visible, true)
    verify(String(H.find(bc, "crumbSeparator1").text) !== "", "the separator draws a glyph")
  }

  function test_a_single_crumb_is_just_the_heading() {
    var bc = make([{ label: "Documents", clickable: false }])
    compare(String(H.find(bc, "projectHeading").text), "Documents")
    compare(H.find(bc, "crumbSeparator0").visible, false)
    verify(!H.find(bc, "crumb1"))
  }

  function test_clicking_an_earlier_crumb_reports_its_index() {
    var bc = make(trail)
    var first = H.find(bc, "crumbText0")
    mouseClick(first, first.width / 2, first.height / 2)
    compare(activated.count, 1)
    compare(activated.signalArguments[0][0], 0)
    var second = H.find(bc, "crumbText1")
    mouseClick(second, second.width / 2, second.height / 2)
    compare(activated.count, 2)
    compare(activated.signalArguments[1][0], 1)
  }

  function test_the_current_crumb_is_not_clickable() {
    var bc = make(trail)
    var heading = H.find(bc, "projectHeading")
    mouseClick(heading, 2, heading.height / 2)
    compare(activated.count, 0)
  }

  function test_the_current_crumb_elides_when_the_row_is_too_narrow() {
    var bc = make([
      { label: "Memories", clickable: true },
      { label: "A very long memory note name that cannot possibly fit in here", clickable: false }
    ])
    bc.width = 160
    wait(20)
    var heading = H.find(bc, "projectHeading")
    compare(heading.elide, Text.ElideRight)
    verify(heading.width <= bc.width, "the heading stays inside the row")
    verify(H.find(bc, "crumbText0").width > 0, "the section crumb keeps its width")
  }
}
