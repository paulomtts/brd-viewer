import QtQml

// One active filter value (a document category, a memory type): choosing the
// active one again clears it.
QtObject {
  property string active: ""

  signal toggled()

  function toggle(id) {
    active = active === id ? "" : id
    toggled()
  }

  function clear() { active = "" }
}
