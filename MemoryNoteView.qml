import QtQuick
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
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}
  readonly property bool dirty: view.draft !== view.text
  readonly property Item editorItem: editorBox.editorItem

  signal editRequested()
  signal deleteRequested()
  signal saveRequested()
  signal cancelEditRequested()
  signal draftEdited(string text)
  signal escapePressed()

  Row {
    width: parent.width
    spacing: Style.space(8)

    UI.ThemedText {
      objectName: "memoryNoteName"
      variant: "heading"
      theme: view.theme
      width: Math.max(0, parent.width - noteBadge.width - parent.spacing)
      text: view.entry.name
      font.bold: true
      elide: Text.ElideRight
    }

    UI.Badge {
      id: noteBadge
      theme: view.theme
      textObjectName: "memoryNoteBadge"
      paddingY: Style.space(4)
      text: Memories.memoryTypeLabel(view.entry.type)
      tint: Memories.memoryTypeColor(view.entry.type, view.theme.dim)
    }
  }

  UI.ThemedText {
    objectName: "memoryNoteDescription"
    variant: "caption"
    theme: view.theme
    visible: text !== ""
    width: parent.width
    text: view.entry.description
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "memoryNoteFile"
    variant: "caption"
    theme: view.theme
    width: parent.width
    text: view.entry.file
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

  UI.ThemedText {
    objectName: "memoryNoteError"
    variant: "caption"
    theme: view.theme
    visible: view.error !== ""
    width: parent.width
    text: view.error
    color: view.theme.urgent
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "memoryNoteReadError"
    variant: "dim"
    theme: view.theme
    visible: view.readError !== ""
    width: parent.width
    text: view.readError
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "memoryNoteBody"
    variant: "small"
    theme: view.theme
    visible: !view.editing && view.readError === ""
    width: parent.width
    text: view.text !== "" ? Documents.stripFrontmatter(view.text) : "Loading…"
    wrapMode: Text.WordWrap
    textFormat: Text.MarkdownText
  }

  UI.TextAreaBox {
    id: editorBox
    visible: view.editing
    width: parent.width
    minHeight: Style.space(280)
    editorObjectName: "memoryEditor"
    submitChords: ["ctrl-s"]
    theme: view.theme
    enabled: !view.busy
    text: view.draft
    onEdited: function(text) { if (text !== view.draft) view.draftEdited(text) }
    onEscapePressed: view.escapePressed()
    onSubmitRequested: view.saveRequested()
  }

  UI.ThemedText {
    variant: "caption"
    theme: view.theme
    visible: view.editing
    width: parent.width
    text: view.dirty ? "Unsaved changes. Ctrl+S saves; Cancel discards." : "Ctrl+S saves. Escape cancels."
  }
}
