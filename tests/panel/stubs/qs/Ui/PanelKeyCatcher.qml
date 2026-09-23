import QtQuick
FocusScope {
  signal activateRequested()
  signal closeRequested()
  signal moveRequested(int dx, int dy)
  signal tabRequested(int direction)
}
