import QtQuick
import QtTest
import "../.."
TestCase {
  id: tc
  name: "NewMemoryDialog"
  when: windowShown
  visible: true
  width: 600; height: 640

  Component { id: dialogC; NewMemoryDialog { width: 560; height: 600 } }
  SignalSpy { id: createSpy; signalName: "createRequested" }
  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function make() {
    var d = createTemporaryObject(dialogC, tc)
    createSpy.target = d; cancelSpy.target = d
    createSpy.clear(); cancelSpy.clear()
    d.shown = true
    wait(30)
    return d
  }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }

  function test_hidden_until_shown() {
    var d = createTemporaryObject(dialogC, tc)
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
  }

  function test_create_needs_a_name_then_reports_the_fields() {
    var d = make()
    compare(find(d, "newMemoryCreate").enabled, false)
    find(d, "newMemoryName").text = "Terse replies"
    compare(find(d, "newMemoryCreate").enabled, true)
    find(d, "newMemoryDescription").text = "no trailing summaries"
    find(d, "newMemoryBody").text = "Keep answers short."
    click(find(d, "newMemoryType" + "reference"))
    click(find(d, "newMemoryCreate"))
    compare(createSpy.count, 1)
    compare(createSpy.signalArguments[0][0], "Terse replies")
    compare(createSpy.signalArguments[0][1], "reference")
    compare(createSpy.signalArguments[0][2], "no trailing summaries")
    compare(createSpy.signalArguments[0][3], "Keep answers short.")
  }

  function test_the_default_type_is_feedback_and_only_one_type_is_active() {
    var d = make()
    compare(find(d, "newMemoryTypefeedback").active, true)
    click(find(d, "newMemoryTypeuser"))
    compare(find(d, "newMemoryTypeuser").active, true)
    compare(find(d, "newMemoryTypefeedback").active, false)
    verify(!find(d, "newMemoryTypeother"), "other is not offered for new notes")
  }

  function test_cancel_and_backdrop_and_busy() {
    var d = make()
    click(find(d, "newMemoryCancel")); compare(cancelSpy.count, 1)
    mouseClick(find(d, "newMemoryBackdrop"), 2, 2); compare(cancelSpy.count, 2)
    mouseClick(find(d, "newMemoryCard"), 3, 3); compare(cancelSpy.count, 2)
    find(d, "newMemoryName").text = "x"
    d.busy = true
    compare(find(d, "newMemoryCreate").enabled, false)
    compare(find(d, "newMemoryCancel").enabled, false)
    mouseClick(find(d, "newMemoryBackdrop"), 2, 2); compare(cancelSpy.count, 2)
  }

  function test_ctrl_s_in_the_body_does_not_create() {
    var d = make()
    find(d, "newMemoryName").text = "Terse replies"
    var body = find(d, "newMemoryBody")
    body.forceActiveFocus()
    keyClick(Qt.Key_S, Qt.ControlModifier)
    compare(createSpy.count, 0)
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    compare(createSpy.count, 1)
  }

  function test_fields_reset_when_reopened_and_errors_show() {
    var d = make()
    find(d, "newMemoryName").text = "abc"
    click(find(d, "newMemoryTypeuser"))
    d.shown = false
    d.shown = true
    compare(find(d, "newMemoryName").text, "")
    compare(find(d, "newMemoryTypefeedback").active, true)
    compare(find(d, "newMemoryError").visible, false)
    d.error = "exists"
    compare(find(d, "newMemoryError").visible, true)
    compare(find(d, "newMemoryError").text, "exists")
  }
}
