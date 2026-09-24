import QtQuick
import QtTest
TestCase {
  id: tc
  name: "MemoryNoteView"
  when: windowShown
  visible: true
  width: 500; height: 600

  Component { id: viewC; MemoryNoteView { width: 460 } }
  SignalSpy { id: editSpy; signalName: "editRequested" }
  SignalSpy { id: delSpy; signalName: "deleteRequested" }
  SignalSpy { id: saveSpy; signalName: "saveRequested" }
  SignalSpy { id: cancelSpy; signalName: "cancelEditRequested" }
  SignalSpy { id: draftSpy; signalName: "draftEdited" }
  SignalSpy { id: escSpy; signalName: "escapePressed" }

  property var entry: ({ file: "feedback_a.md", name: "Terse", description: "no summaries", type: "feedback" })
  property string raw: "---\nname: Terse\n---\n\nBody **text**\n"

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function make() {
    var v = createTemporaryObject(viewC, tc)
    var spies = [editSpy, delSpy, saveSpy, cancelSpy, draftSpy, escSpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = v; spies[i].clear() }
    v.entry = entry
    v.text = raw
    return v
  }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }

  function test_reading_shows_header_body_without_frontmatter_and_actions() {
    var v = make()
    compare(find(v, "memoryNoteName").text, "Terse")
    compare(find(v, "memoryNoteBadge").text, "Feedback")
    compare(find(v, "memoryNoteDescription").text, "no summaries")
    compare(find(v, "memoryNoteFile").text, "feedback_a.md")
    compare(find(v, "memoryNoteBody").text, "\nBody **text**\n")
    compare(find(v, "memoryNoteBody").visible, true)
    compare(find(v, "memoryEdit").visible, true)
    compare(find(v, "memoryDelete").visible, true)
    compare(find(v, "memorySave").visible, false)
    compare(find(v, "memoryEditor").parent.visible, false)
    click(find(v, "memoryEdit")); compare(editSpy.count, 1)
    click(find(v, "memoryDelete")); compare(delSpy.count, 1)
  }

  function test_editing_shows_the_editor_with_the_draft_and_save_needs_changes() {
    var v = make()
    v.editing = true
    v.draft = raw
    compare(find(v, "memoryNoteBody").visible, false)
    compare(find(v, "memoryEditor").parent.visible, true)
    compare(find(v, "memoryEditor").text, raw)
    compare(find(v, "memoryEdit").visible, false)
    compare(find(v, "memorySave").enabled, false)
    v.draft = raw + "more"
    compare(v.dirty, true)
    wait(30)
    compare(find(v, "memorySave").enabled, true)
    click(find(v, "memorySave")); compare(saveSpy.count, 1)
    click(find(v, "memoryCancelEdit")); compare(cancelSpy.count, 1)
  }

  function test_typing_reports_the_new_draft() {
    var v = make()
    v.editing = true
    v.draft = "abc"
    var editor = find(v, "memoryEditor")
    editor.text = "abcd"
    compare(draftSpy.count, 1)
    compare(draftSpy.signalArguments[0][0], "abcd")
  }

  function test_keys_in_the_editor() {
    var v = make()
    v.editing = true
    v.draft = raw
    var editor = find(v, "memoryEditor")
    editor.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(escSpy.count, 1)
    keyClick(Qt.Key_S, Qt.ControlModifier)
    compare(saveSpy.count, 1)
  }

  function test_read_errors_hide_the_actions_and_op_errors_show() {
    var v = make()
    v.readError = "Could not read this memory."
    compare(find(v, "memoryNoteReadError").visible, true)
    compare(find(v, "memoryNoteActions").visible, false)
    compare(find(v, "memoryNoteBody").visible, false)
    v.readError = ""
    v.error = "Could not write"
    compare(find(v, "memoryNoteError").visible, true)
    compare(find(v, "memoryNoteError").text, "Could not write")
  }
}
