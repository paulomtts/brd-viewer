import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "TextAreaBox"
  when: windowShown
  visible: true
  width: 500; height: 400

  Component {
    id: boxC
    UI.TextAreaBox {
      width: 460
      minHeight: Style.space(280)
      placeholder: "What should be remembered?"
      editorObjectName: "theEditor"
      submitChords: ["ctrl-s", "ctrl-enter"]
    }
  }
  Component {
    id: chordBoxC
    UI.TextAreaBox { width: 460; editorObjectName: "chordEditor" }
  }
  SignalSpy { id: edits; signalName: "edited" }
  SignalSpy { id: escapes; signalName: "escapePressed" }
  SignalSpy { id: submits; signalName: "submitRequested" }

  function make() {
    var box = createTemporaryObject(boxC, tc)
    edits.target = box; escapes.target = box; submits.target = box
    edits.clear(); escapes.clear(); submits.clear()
    return box
  }

  function test_it_is_a_bordered_box_at_least_min_height_tall() {
    var box = make()
    compare(box.height, Style.space(280))
    compare(box.radius, Style.space(6))
    compare(box.border.width, 1)
    verify(box.color !== undefined)
  }

  function test_the_editor_is_findable_and_shows_the_text() {
    var box = make()
    box.text = "hello"
    var editor = H.find(box, "theEditor")
    verify(editor, "editor")
    compare(editor.text, "hello")
    compare(editor.placeholderText, "What should be remembered?")
    compare(box.editorItem, editor)
    compare(editor.parent, box)
  }

  function test_typing_is_reported_once() {
    var box = make()
    box.text = "abc"
    var editor = H.find(box, "theEditor")
    edits.clear()
    editor.text = "abcd"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "abcd")
  }

  function test_escape_and_the_submit_chords() {
    var box = make()
    var editor = H.find(box, "theEditor")
    editor.forceActiveFocus()
    verify(editor.activeFocus, "the editor takes focus")
    keyClick(Qt.Key_Escape)
    compare(escapes.count, 1)
    keyClick(Qt.Key_S, Qt.ControlModifier)
    compare(submits.count, 1)
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    compare(submits.count, 2)
  }

  function makeChordBox(chords) {
    var box = createTemporaryObject(chordBoxC, tc)
    box.submitChords = chords
    submits.target = box
    submits.clear()
    H.find(box, "chordEditor").forceActiveFocus()
    return box
  }

  function test_no_chord_submits_unless_the_caller_asked_for_it() {
    var box = makeChordBox([])
    keyClick(Qt.Key_S, Qt.ControlModifier)
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    keyClick(Qt.Key_Enter, Qt.ControlModifier)
    compare(submits.count, 0)
  }

  function test_ctrl_s_only_ignores_ctrl_enter() {
    var box = makeChordBox(["ctrl-s"])
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    keyClick(Qt.Key_Enter, Qt.ControlModifier)
    compare(submits.count, 0)
    keyClick(Qt.Key_S, Qt.ControlModifier)
    compare(submits.count, 1)
  }

  function test_ctrl_enter_only_ignores_ctrl_s() {
    var box = makeChordBox(["ctrl-enter"])
    keyClick(Qt.Key_S, Qt.ControlModifier)
    compare(submits.count, 0)
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    compare(submits.count, 1)
    keyClick(Qt.Key_Enter, Qt.ControlModifier)
    compare(submits.count, 2)
  }

  function test_the_border_follows_focus() {
    var box = make()
    var editor = H.find(box, "theEditor")
    compare(box.border.color, Qt.alpha(box.tint, 0.3))
    editor.forceActiveFocus()
    verify(editor.activeFocus, "the editor takes focus")
    compare(box.border.color, box.tint)
  }
}
