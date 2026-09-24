// tests/core/domain/tst_board.qml
import QtQuick
import QtTest
import "../../../core/domain/board.js" as Board

TestCase {
  name: "DomainBoard"

  function makeCard(id, status, children, blockedBy) {
    return {
      id: id, title: id, description: "", status: status,
      blocked_by: blockedBy || [], created_at: "", updated_at: "",
      children: children || []
    }
  }

  function test_index_tree_on_empty_forest() {
    var result = Board.indexTree([])
    compare(Object.keys(result.cardMap).length, 0)
  }

  function test_index_tree_builds_a_flat_map_of_every_card() {
    var leaf = makeCard("c2", "todo")
    var mid = makeCard("c1", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var result = Board.indexTree([root])

    compare(Object.keys(result.cardMap).length, 3)
    compare(result.cardMap["c2"].id, "c2")
    compare(result.cardMap["c1"].id, "c1")
    compare(result.cardMap["root"].id, "root")
  }

  function test_index_tree_annotates_parent_id() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "todo", [child])
    var result = Board.indexTree([root])
    compare(result.cardMap["root"].parentId, null)
    compare(result.cardMap["child"].parentId, "root")
  }

  function test_index_tree_handles_multiple_roots() {
    var result = Board.indexTree([makeCard("a", "todo"), makeCard("b", "todo")])
    compare(Object.keys(result.cardMap).length, 2)
    compare(result.cardMap["a"].parentId, null)
    compare(result.cardMap["b"].parentId, null)
  }

  function test_subtree_counts_on_childless_card() {
    var counts = Board.subtreeCounts(makeCard("solo", "todo"))
    compare(counts.done, 0)
    compare(counts.total, 0)
  }

  // A card's own status must never be folded into its descendant count --
  // the parent here is "done" but every descendant is still "todo".
  function test_subtree_counts_ignores_own_status_counts_descendants_only() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "done", [child])
    var counts = Board.subtreeCounts(root)
    compare(counts.done, 0)
    compare(counts.total, 1)
  }

  function test_subtree_counts_counts_nested_descendants_recursively() {
    var grandchild1 = makeCard("g1", "done")
    var grandchild2 = makeCard("g2", "todo")
    var child = makeCard("child", "in_progress", [grandchild1, grandchild2])
    var root = makeCard("root", "todo", [child])
    var counts = Board.subtreeCounts(root)
    compare(counts.total, 3)
    compare(counts.done, 1)
  }

  // ---- search --------------------------------------------------------

  function test_subtree_matches_on_own_title() {
    var card = makeCard("root", "todo")
    card.title = "Fix the parser"
    compare(Board.subtreeMatches(card, "parser"), true)
    compare(Board.subtreeMatches(card, "nope"), false)
  }

  // Keeping ancestors of a match visible: a non-matching root whose
  // grandchild matches must still report true.
  function test_subtree_matches_true_for_ancestor_of_a_nested_match() {
    var grandchild = makeCard("g", "todo")
    grandchild.title = "Deep task about parsers"
    var child = makeCard("c", "todo", [grandchild])
    child.title = "Middle"
    var root = makeCard("root", "todo", [child])
    root.title = "Top"
    compare(Board.subtreeMatches(root, "parsers"), true)
    compare(Board.subtreeMatches(child, "parsers"), true)
  }

  function test_subtree_matches_false_when_nothing_in_subtree_matches() {
    var child = makeCard("c", "todo")
    child.title = "Unrelated"
    var root = makeCard("root", "todo", [child])
    root.title = "Also unrelated"
    compare(Board.subtreeMatches(root, "parsers"), false)
  }

  function test_subtree_matches_false_for_undefined_card() {
    compare(Board.subtreeMatches(undefined, "x"), false)
  }

  // ---- colors, kinds, board order, detail links --------------------------

  function test_status_color_maps_known_statuses() {
    compare(Board.statusColor("done", "#111111"), "#7fb069")
    compare(Board.statusColor("blocked", "#111111"), "#e8954a")
    compare(Board.statusColor("in_progress", "#111111"), "#5fa8d3")
  }

  function test_status_color_falls_back_for_todo_and_unknown() {
    compare(Board.statusColor("todo", "#111111"), "#111111")
    compare(Board.statusColor("weird", "#111111"), "#111111")
    compare(Board.statusColor(undefined, "#111111"), "#111111")
  }

  function test_kind_label_by_depth() {
    compare(Board.kindLabel(0), "Milestone")
    compare(Board.kindLabel(1), "Story")
    compare(Board.kindLabel(2), "Subtask")
    compare(Board.kindLabel(7), "Subtask")
    compare(Board.kindLabel(undefined), "Card")
    compare(Board.kindLabel(-1), "Card")
  }

  function test_index_tree_annotates_depth() {
    var leaf = makeCard("leaf", "todo")
    var mid = makeCard("mid", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var map = Board.indexTree([root]).cardMap
    compare(map["root"].depth, 0)
    compare(map["mid"].depth, 1)
    compare(map["leaf"].depth, 2)
  }

  function test_effective_status_folds_blocked_into_todo() {
    compare(Board.effectiveStatus(makeCard("a", "blocked")), "todo")
    compare(Board.effectiveStatus(makeCard("a", "done")), "done")
    compare(Board.effectiveStatus(undefined), "todo")
  }

  function test_board_order_groups_by_section_in_order() {
    var a = makeCard("a", "done")
    var b = makeCard("b", "todo")
    var c = makeCard("c", "blocked")
    var d = makeCard("d", "in_progress")
    var ids = Board.boardOrder([a, b, c, d], ["todo", "in_progress", "done"]).map(function(x) { return x.id })
    compare(ids.join(","), "b,c,d,a")
  }

  function test_board_order_empty() {
    compare(Board.boardOrder([], ["todo", "in_progress", "done"]).length, 0)
  }

  function test_detail_links_orders_parent_blockers_children() {
    var kid = makeCard("kid", "todo")
    var dep = makeCard("dep", "todo")
    var mid = makeCard("mid", "todo", [kid], ["dep", "ghost"])
    var root = makeCard("root", "todo", [mid])
    var map = Board.indexTree([root, dep]).cardMap
    var links = Board.detailLinks(map["mid"], map)
    compare(links.map(function(l) { return l.section + ":" + l.id }).join(","), "parent:root,blocker:dep,child:kid")
  }

  function test_detail_links_skips_dangling_blockers_and_missing_parent() {
    var card = makeCard("c", "todo", [], ["ghost"])
    var map = Board.indexTree([card]).cardMap
    compare(Board.detailLinks(card, map).length, 0)
    compare(Board.detailLinks(undefined, {}).length, 0)
  }

  function test_ancestor_ids_walk_from_the_outermost_card_down() {
    var leaf = makeCard("t1", "todo")
    var mid = makeCard("s1", "todo", [leaf])
    var root = makeCard("m1", "todo", [mid])
    var map = Board.indexTree([root]).cardMap
    compare(Board.ancestorIds("t1", map).join(","), "m1,s1")
    compare(Board.ancestorIds("s1", map).join(","), "m1")
    compare(Board.ancestorIds("m1", map).length, 0)
    compare(Board.ancestorIds("nope", map).length, 0)
  }
}
