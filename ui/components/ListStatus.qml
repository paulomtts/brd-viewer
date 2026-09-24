import QtQuick

// The one line a list shows instead of its rows: loading beats an error,
// which beats the empty message (the filtered wording when a query or a
// filter chip is narrowing the list). The wording itself is the caller's --
// it is domain language -- and an empty text hides the line.
ThemedText {
  id: status

  property bool loading: false
  property string loadingText: ""
  property string error: ""
  property bool empty: false
  // True when a query or a filter is what emptied the list.
  property bool filtered: false
  property string emptyText: ""
  property string filteredText: ""

  variant: "dim"
  text: status.loading ? status.loadingText
    : status.error !== "" ? status.error
    : status.empty ? (status.filtered ? status.filteredText : status.emptyText)
    : ""
  visible: text !== ""
  wrapMode: Text.WordWrap
}
