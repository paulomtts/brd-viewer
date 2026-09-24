// tests/ui/screens/tst_card_detail_screen.qml
// ui/screens/CardDetailScreen.qml on its own: the parent/blocker/child link
// rows, the kind and status badges, the description fallback, a blocker that is
// not in this board, and the click that opens a link through the navigator.
// REAL core/stores App and REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "CardDetailScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })

  function card(id, title, status, description, children, blockedBy) {
    return { id: id, title: title, status: status, description: description,
      blocked_by: blockedBy || [], children: children || [] }
  }

  function roots() {
    return [
      card("m1", "Milestone one", "todo", "m desc", [
        card("s1", "Story one", "todo", "s desc",
          [card("t1", "Subtask one", "done", "t desc")], ["x1", "ghost"])]),
      card("x1", "Other milestone", "in_progress", "x desc")]
  }

  function make() {
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
    var sC = Qt.createComponent("../../../ui/screens/CardDetailScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 500 })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    app.board.applyTreeData(roots())
    return s
  }

  function texts(item, out) {
    out = out || []
    if (item.visible === false) return out
    if (item.text !== undefined && String(item.text) !== "") out.push(String(item.text))
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) texts(kids[i], out)
    return out
  }

  // The clickable link rows: the items that carry a `resolved` descriptor.
  function links(item, out) {
    out = out || []
    if (item.resolved !== undefined && item.rowIndex !== undefined && item.visible !== false) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) links(kids[i], out)
    return out
  }

  function test_the_card_detail_shows_only_for_an_open_card_that_is_in_the_board() {
    var s = make(); if (!s) return
    compare(s.visible, false)
    s.navigator.openCard("s1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.visible, true)
    s.app.board.selectedCardId = "nope"
    compare(s.visible, false)
  }

  function test_the_open_card_renders_its_title_badges_and_description() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var t = texts(s)
    verify(t.indexOf("Story one") >= 0, t.join(" | "))
    verify(t.indexOf("Story") >= 0, "the kind badge by depth: " + t.join(" | "))
    verify(t.indexOf("Todo") >= 0, "the status badge: " + t.join(" | "))
    verify(t.indexOf("s desc") >= 0, t.join(" | "))
  }

  function test_a_card_without_a_description_says_so() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo", "")])
    s.navigator.openCard("m1")
    wait(50)
    verify(texts(s).indexOf("No description.") >= 0, texts(s).join(" | "))
  }

  function test_the_parent_blocker_and_child_links_are_listed_with_their_sections() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var t = texts(s)
    verify(t.indexOf("BLOCKED BY") >= 0, t.join(" | "))
    verify(t.indexOf("CHILDREN") >= 0, t.join(" | "))
    var rows = links(s)
    var titles = rows.map(function(r) { return r.prefix + r.resolved.title })
    compare(titles.join(","), "↑ Milestone one,Other milestone,ghost,Subtask one")
  }

  function test_a_blocker_that_is_not_in_this_board_is_marked_and_not_openable() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var rows = links(s)
    var ghost = rows.filter(function(r) { return r.resolved.title === "ghost" })[0]
    verify(ghost, "the unresolved blocker row")
    compare(ghost.resolved.inBoard, false)
    compare(ghost.rowIndex, -1)
    verify(texts(ghost).join(" | ").indexOf("ghost (not in this board)") >= 0, texts(ghost).join(" | "))
    mouseClick(ghost)
    compare(s.app.board.selectedCardId, "s1")
  }

  function test_clicking_a_child_link_opens_that_card() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var rows = links(s)
    var child = rows.filter(function(r) { return r.resolved.title === "Subtask one" })[0]
    verify(child, "the child row")
    mouseClick(child)
    compare(s.app.board.selectedCardId, "t1")
  }

  function test_clicking_the_parent_link_opens_the_parent_card() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var rows = links(s)
    compare(rows[0].prefix, "↑ ")
    mouseClick(rows[0])
    compare(s.app.board.selectedCardId, "m1")
  }
}
