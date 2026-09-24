// tests/core/stores/tst_filter_state.qml
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresFilterState"

  property int toggles: 0

  function make() {
    var comp = Qt.createComponent("../../../core/stores/FilterState.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var f = comp.createObject(tc)
    tc.toggles = 0
    f.toggled.connect(function() { tc.toggles += 1 })
    return f
  }

  function test_toggling_sets_the_active_filter() {
    var f = make(); if (!f) return
    compare(f.active, "")
    f.toggle("specs")
    compare(f.active, "specs")
    compare(tc.toggles, 1)
  }

  function test_toggling_the_active_filter_again_clears_it() {
    var f = make(); if (!f) return
    f.toggle("specs")
    f.toggle("specs")
    compare(f.active, "")
    compare(tc.toggles, 2)
  }

  function test_toggling_another_filter_replaces_the_active_one() {
    var f = make(); if (!f) return
    f.toggle("specs")
    f.toggle("audits")
    compare(f.active, "audits")
    compare(tc.toggles, 2)
  }

  function test_clear_resets_the_active_filter_without_signalling() {
    var f = make(); if (!f) return
    f.toggle("specs")
    f.clear()
    compare(f.active, "")
    compare(tc.toggles, 1)
  }
}
