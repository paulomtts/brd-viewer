import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "core/domain/documents.js" as Documents
import "core/domain/memories.js" as Memories
import "ui/components" as UI
import "ui/theme" as T

// One memory note: rendered text with Edit / Delete, or a raw-text editor with
// Save / Cancel. Renders and emits only; Panel.qml owns the text, the draft and
// the file operations (memory-op.py).
Column {
  id: view
  objectName: "memoryNoteView"
  spacing: Style.space(10)

  property var entry: ({ file: "", name: "", description: "", type: "other" })
  property string text: ""
  property string readError: ""
  property bool editing: false
  property string draft: ""
  property bool busy: false
  property string error: ""
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  // What the shared components draw with; Panel still passes the colours one
  // by one, so the theme follows them.
  property var theme: T.Theme {
    foreground: view.foreground
    dim: view.dim
    urgent: view.urgent
    fontFamily: view.fontFamily
  }
  readonly property bool dirty: view.draft !== view.text
  readonly property Item editorItem: editor

  signal editRequested()
  signal deleteRequested()
  signal saveRequested()
  signal cancelEditRequested()
  signal draftEdited(string text)
  signal escapePressed()

  Row {
    width: parent.width
    spacing: Style.space(8)

    Text {
      objectName: "memoryNoteName"
      width: Math.max(0, parent.width - noteBadge.width - parent.spacing)
      text: view.entry.name
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
      elide: Text.ElideRight
    }

    UI.Badge {
      id: noteBadge
      theme: view.theme
      textObjectName: "memoryNoteBadge"
      paddingY: Style.space(4)
      text: Memories.memoryTypeLabel(view.entry.type)
      tint: Memories.memoryTypeColor(view.entry.type, view.dim)
    }
  }

  Text {
    objectName: "memoryNoteDescription"
    visible: text !== ""
    width: parent.width
    text: view.entry.description
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    objectName: "memoryNoteFile"
    width: parent.width
    text: view.entry.file
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideMiddle
  }

  Row {
    objectName: "memoryNoteActions"
    spacing: Style.spacing.md
    visible: view.readError === ""

    UI.ActionButton {
      objectName: "memoryEdit"
      visible: !view.editing
      text: "Edit"
      theme: view.theme
      onClicked: view.editRequested()
    }

    UI.ActionButton {
      objectName: "memoryDelete"
      visible: !view.editing
      text: "Delete"
      tone: "danger"
      theme: view.theme
      onClicked: view.deleteRequested()
    }

    UI.ActionButton {
      objectName: "memorySave"
      visible: view.editing
      text: view.busy ? "Saving…" : "Save"
      enabled: !view.busy && view.dirty
      theme: view.theme
      onClicked: view.saveRequested()
    }

    UI.ActionButton {
      objectName: "memoryCancelEdit"
      visible: view.editing
      text: "Cancel"
      enabled: !view.busy
      opacity: 1
      theme: view.theme
      onClicked: view.cancelEditRequested()
    }
  }

  Text {
    objectName: "memoryNoteError"
    visible: view.error !== ""
    width: parent.width
    text: view.error
    color: view.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    objectName: "memoryNoteReadError"
    visible: view.readError !== ""
    width: parent.width
    text: view.readError
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }

  Text {
    objectName: "memoryNoteBody"
    visible: !view.editing && view.readError === ""
    width: parent.width
    text: view.text !== "" ? Documents.stripFrontmatter(view.text) : "Loading…"
    color: view.foreground
    font.family: view.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
    textFormat: Text.MarkdownText
  }

  Rectangle {
    visible: view.editing
    width: parent.width
    height: Math.max(Style.space(280), editor.implicitHeight + Style.space(16))
    radius: Style.space(6)
    color: Qt.alpha(view.foreground, 0.06)
    border.width: 1
    border.color: editor.activeFocus ? view.foreground : Qt.alpha(view.foreground, 0.3)

    Controls.TextArea {
      id: editor
      objectName: "memoryEditor"
      anchors.fill: parent
      anchors.margins: Style.space(8)
      background: null
      text: view.draft
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: TextEdit.Wrap
      selectByMouse: true
      enabled: !view.busy
      onTextChanged: if (text !== view.draft) view.draftEdited(text)

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { view.escapePressed(); event.accepted = true; return }
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
          view.saveRequested(); event.accepted = true
        }
      }
    }
  }

  Text {
    visible: view.editing
    width: parent.width
    text: view.dirty ? "Unsaved changes. Ctrl+S saves; Cancel discards." : "Ctrl+S saves. Escape cancels."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }
}
