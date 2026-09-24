pragma Singleton
import QtQuick
QtObject {
  function space(n) { return n }
  property QtObject font: QtObject { property string family: "sans"; property int body: 14; property int bodySmall: 12; property int caption: 10; property int heading: 18; property int icon: 18; property int iconSmall: 12 }
  property QtObject spacing: QtObject { property int md: 8; property int rowPaddingX: 8; property int controlPaddingY: 4 }
}
