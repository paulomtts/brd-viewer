// tests/ui/screens/tst_board_screen.qml
// ui/screens/BoardScreen.qml on its own: the status sections and their counts,
// the derived-blocked-in-todo rule, the empty/no-match messages, and the
// hover/click forwarding to the navigator. Built on the REAL core/stores App
// and the REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "BoardScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var reveals: []

  function card(id, title, status, children, blockedBy) {
    return { id: id, title: title, status: status, description: "d",
      blocked_by: blockedBy || [], children: children || [] }
  }

  function make() {
    tc.reveals = []
    var host = createTemporaryObject(hostC, tc)
    var appC = Qt.createComponent("../../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(host, { backendDir: "/plugin/core/backend/" })
    var navC = Qt.createComponent("../../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    var flick = flickC.createObject(host)
    var nav = navC.createObject(host, { app: app, flick: flick, actions: ({
      focusForView: function() {},
      scrollToTop: function() { flick.contentY = 0 },
      scrollBy: function(px) { flick.contentY = flick.contentY + px },
      centerOnGraphNode: function(id) {}
    }) })
    var sC = Qt.createComponent("../../../ui/screens/BoardScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 500 })
    s.revealRequested.connect(function(item) { tc.reveals.push(item) })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    return s
  }

  // Every visible piece of text the screen renders, in tree order.
  function texts(item, out) {
    out = out || []
    if (item.visible === false) return out
    if (item.text !== undefined && String(item.text) !== "") out.push(String(item.text))
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) texts(kids[i], out)
    return out
  }

  // Every rendered board card, in tree order (they are the items with cardIndex).
  function cards(item, out) {
    out = out || []
    if (item.cardIndex !== undefined && item.title !== undefined && item.progress !== undefined) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) cards(kids[i], out)
    return out
  }

  function test_the_board_screen_shows_only_in_the_board_view_with_a_project() {
    var s = make(); if (!s) return
    compare(s.visible, true)
    s.app.nav.viewMode = "graph"
    compare(s.visible, false)
    s.app.nav.viewMode = "board"
    compare(s.visible, true)
    s.app.projects.selectedProject = null
    compare(s.visible, false)
  }

  function test_cards_are_grouped_into_status_sections_with_counts() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([
      card("m1", "Milestone one", "todo", [card("s1", "Story", "done")]),
      card("m2", "Milestone two", "in_progress"),
      card("m3", "Milestone three", "done")])
    wait(50)
    var t = texts(s)
    verify(t.indexOf("Todo (1)") >= 0, "Todo header: " + t.join(" | "))
    verify(t.indexOf("In Progress (1)") >= 0, "In Progress header: " + t.join(" | "))
    verify(t.indexOf("Done (1)") >= 0, "Done header: " + t.join(" | "))
    verify(t.indexOf("Milestone one") >= 0)
    verify(t.indexOf("1/1 done") >= 0, "the subtree progress: " + t.join(" | "))
  }

  function test_a_blocked_root_is_listed_under_todo_and_labelled_blocked() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo"), card("b1", "Blocked one", "blocked")])
    wait(50)
    var t = texts(s)
    verify(t.indexOf("Todo (2)") >= 0, "both roots in Todo: " + t.join(" | "))
    verify(t.indexOf("Blocked") >= 0, "the blocked label: " + t.join(" | "))
  }

  function test_an_empty_board_says_so_and_a_search_with_no_match_says_so() {
    var s = make(); if (!s) return
    wait(50)
    verify(texts(s).indexOf("This project's board is empty.") >= 0)
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo")])
    wait(50)
    verify(texts(s).indexOf("This project's board is empty.") < 0)
    s.app.nav.searchQuery = "zzz"
    wait(50)
    verify(texts(s).indexOf("No cards match “zzz”.") >= 0, texts(s).join(" | "))
  }

  function test_clicking_a_card_opens_it_through_the_navigator() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo"), card("m2", "Milestone two", "todo")])
    wait(50)
    var list = cards(s)
    compare(list.length, 2)
    compare(list[1].title, "Milestone two")
    mouseClick(list[1])
    compare(s.app.board.selectedCardId, "m2")
    compare(s.app.nav.viewMode, "entry")
  }

  function test_hovering_a_card_moves_the_cursor_through_the_navigator() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo"), card("m2", "Milestone two", "todo")])
    wait(50)
    var list = cards(s)
    compare(list.length, 2)
    compare(s.app.nav.cursorIndex, 0)
    mouseMove(list[1], list[1].width / 2, list[1].height / 2)
    compare(s.app.nav.cursorIndex, 1)
    compare(list[1].hasCursor, true)
  }
}
