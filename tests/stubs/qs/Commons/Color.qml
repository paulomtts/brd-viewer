pragma Singleton
import QtQuick
QtObject {
  property color foreground: "#ddd"
  property color urgent: "#f55"
  property QtObject popups: QtObject { property color background: "#101315"; property color border: "#555" }
}
