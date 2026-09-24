import QtQml

// The panel's non-visual state, in one place. Later tasks add the remaining
// stores beside `nav`.
QtObject {
  property string backendDir: ""

  readonly property NavigationStore nav: NavigationStore {}
}
