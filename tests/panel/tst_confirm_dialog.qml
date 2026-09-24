import QtQuick
import QtTest
TestCase {
  id: tc
  name: "ConfirmDialog"
  when: windowShown
  visible: true
  width: 600; height: 400

  Component { id: dialogC; ConfirmDialog { width: 560; height: 360; message: "Remove it?"; detail: "/some/path" } }
  SignalSpy { id: confirmSpy; signalName: "confirmRequested" }
  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function make() {
    var d = createTemporaryObject(dialogC, tc)
    confirmSpy.target = d; cancelSpy.target = d
    confirmSpy.clear(); cancelSpy.clear()
    return d
  }

  function test_hidden_until_shown_and_the_accept_button_needs_the_word() {
    var d = make()
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
    compare(find(d, "confirmAccept").enabled, false)
    find(d, "confirmTyped").text = "Delete "
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, true)
    d.shown = false
    d.shown = true
    compare(find(d, "confirmTyped").text, "")
  }

  function test_clicks_accept_cancel_and_backdrop() {
    var d = make()
    d.shown = true
    find(d, "confirmTyped").text = "delete"
    var accept = find(d, "confirmAccept")
    mouseClick(accept, accept.width / 2, accept.height / 2)
    compare(confirmSpy.count, 1)
    var cancel = find(d, "confirmCancel")
    mouseClick(cancel, cancel.width / 2, cancel.height / 2)
    compare(cancelSpy.count, 1)
    mouseClick(find(d, "confirmBackdrop"), 2, 2)
    compare(cancelSpy.count, 2)
    mouseClick(find(d, "confirmCard"), 3, 3)
    compare(cancelSpy.count, 2)
  }

  function test_busy_blocks_everything_and_errors_show() {
    var d = make()
    d.shown = true
    find(d, "confirmTyped").text = "delete"
    d.busy = true
    compare(find(d, "confirmAccept").enabled, false)
    compare(find(d, "confirmCancel").enabled, false)
    mouseClick(find(d, "confirmBackdrop"), 2, 2)
    compare(cancelSpy.count, 0)
    d.busy = false
    compare(find(d, "confirmError").visible, false)
    d.error = "nope"
    compare(find(d, "confirmError").visible, true)
    compare(find(d, "confirmError").text, "nope")
  }
}
