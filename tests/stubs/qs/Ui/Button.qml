import QtQuick
Item {
  property string text; property string iconText; property string tooltipText
  property bool bordered; property color foreground; property string fontFamily
  property real fontSize; property real verticalPadding
  property bool iconSpinning
  signal clicked()
  implicitWidth: 80; implicitHeight: 28
  width: implicitWidth; height: implicitHeight
  MouseArea { anchors.fill: parent; enabled: parent.enabled; onClicked: parent.clicked() }
}
