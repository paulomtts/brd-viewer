import QtQuick
import qs.Commons
import "core/domain/documents.js" as Documents
import "ui/components" as UI
import "ui/theme" as T

// Chooses the open document's type. Renders and emits only; Panel.qml runs
// set-doc-tag.py and owns busy/error.
Column {
  id: picker
  objectName: "tagPicker"
  spacing: Style.space(6)

  property string current: ""
  property bool busy: false
  property string error: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  // What the shared components draw with; Panel still passes the colours one
  // by one, so the theme follows them.
  property var theme: T.Theme {
    foreground: picker.foreground
    dim: picker.dim
    fontFamily: picker.fontFamily
  }

  signal tagChosen(string id)

  readonly property var choices: [
    { id: "architecture", label: "Architecture" },
    { id: "specs", label: "Specs" },
    { id: "standards", label: "Standards" },
    { id: "audits", label: "Audits" },
    { id: "default", label: "Folder default" }
  ]

  Row {
    spacing: Style.space(8)

    UI.ThemedText {
      variant: "caption"
      theme: picker.theme
      anchors.verticalCenter: parent.verticalCenter
      text: "Type"
    }

    UI.ChipRow {
      width: picker.width - Style.space(48)
      theme: picker.theme
      chipPrefix: "tagChip"
      active: picker.current
      busy: picker.busy
      model: picker.choices.map(function(choice) {
        return {
          id: choice.id,
          label: choice.label,
          tint: Documents.docCategoryColor(choice.id, picker.dim)
        }
      })
      onChosen: function(id) { picker.tagChosen(id) }
    }
  }

  UI.ThemedText {
    objectName: "tagError"
    variant: "caption"
    theme: picker.theme
    visible: picker.error !== ""
    width: parent.width
    text: picker.error
    wrapMode: Text.WordWrap
  }
}
