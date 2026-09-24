import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../theme" as T

// The trail that says where the panel is: `crumbs` is [{ label, clickable }],
// outermost first. Every crumb but the first is preceded by a chevron; the
// earlier ones are dim and report their index when clicked, and the last one is
// the current location, drawn as the heading and never clickable. It renders
// and emits only -- Navigator.qml builds the list and acts on the clicks.
Item {
  id: bar

  property var crumbs: []
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal crumbActivated(int index)

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: bar.crumbs

      delegate: Item {
        id: crumb
        required property var modelData
        required property int index
        readonly property bool last: crumb.index === bar.crumbs.length - 1

        objectName: "crumb" + crumb.index
        implicitWidth: crumbRow.implicitWidth
        implicitHeight: crumbRow.implicitHeight
        Layout.fillWidth: crumb.last
        Layout.preferredWidth: crumb.last ? 0 : crumbRow.implicitWidth

        Row {
          id: crumbRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          spacing: Style.space(6)

          ThemedText {
            id: separator
            objectName: "crumbSeparator" + crumb.index
            visible: crumb.index > 0
            theme: bar.theme
            variant: "caption"
            anchors.verticalCenter: label.verticalCenter
            // Font Awesome chevron-right, drawn in the theme's font like every
            // other icon (tests/architecture/test_icon_glyphs.py checks it).
            text: ""
            color: bar.theme ? bar.theme.dim : Color.foreground
            rightPadding: Style.space(2)
            leftPadding: Style.space(2)
          }

          ThemedText {
            id: label
            objectName: crumb.last ? "projectHeading" : "crumbText" + crumb.index
            theme: bar.theme
            variant: crumb.last ? "heading" : "dim"
            font.bold: crumb.last
            text: crumb.modelData.label
            elide: crumb.last ? Text.ElideRight : Text.ElideNone
            width: crumb.last ? Math.max(0, crumbRow.width - (separator.visible ? separator.width + crumbRow.spacing : 0))
              : label.implicitWidth

            MouseArea {
              anchors.fill: parent
              enabled: !!crumb.modelData.clickable
              cursorShape: Qt.PointingHandCursor
              onClicked: bar.crumbActivated(crumb.index)
            }
          }
        }
      }
    }
  }
}
