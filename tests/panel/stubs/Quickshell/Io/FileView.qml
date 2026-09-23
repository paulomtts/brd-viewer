import QtQuick
QtObject {
  property string path; property bool watchChanges; property bool printErrors
  property string stubText: ""
  signal fileChanged()
  signal loaded()
  signal loadFailed(int error)
  function text() { return stubText }
}
