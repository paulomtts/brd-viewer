import QtQuick
QtObject { property var command; property bool running; property string workingDirectory; property QtObject stdout; property QtObject stderr; signal exited(int exitCode) }
