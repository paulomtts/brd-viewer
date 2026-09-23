// tests/qml/tst_logic.qml
import QtQuick
import QtTest
import "../../logic.js" as Logic

TestCase {
  name: "BrdViewerLogic"

  function makeCard(id, status, children, blockedBy) {
    return {
      id: id, title: id, description: "", status: status,
      blocked_by: blockedBy || [], created_at: "", updated_at: "",
      children: children || []
    }
  }

  function test_index_tree_on_empty_forest() {
    var result = Logic.indexTree([])
    compare(Object.keys(result.cardMap).length, 0)
    compare(result.rows.length, 0)
  }

  function test_index_tree_builds_flat_map_and_depth_first_rows() {
    var leaf = makeCard("c2", "todo")
    var mid = makeCard("c1", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var result = Logic.indexTree([root])

    compare(Object.keys(result.cardMap).length, 3)
    compare(result.cardMap["c2"].id, "c2")
    compare(result.rows.length, 3)
    compare(result.rows[0].id, "root")
    compare(result.rows[0].depth, 0)
    compare(result.rows[1].id, "c1")
    compare(result.rows[1].depth, 1)
    compare(result.rows[2].id, "c2")
    compare(result.rows[2].depth, 2)
  }

  function test_index_tree_annotates_parent_id() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "todo", [child])
    var result = Logic.indexTree([root])
    compare(result.cardMap["root"].parentId, null)
    compare(result.cardMap["child"].parentId, "root")
  }

  function test_index_tree_handles_multiple_roots() {
    var result = Logic.indexTree([makeCard("a", "todo"), makeCard("b", "todo")])
    compare(result.rows.length, 2)
    compare(result.cardMap["a"].parentId, null)
    compare(result.cardMap["b"].parentId, null)
  }

  function test_subtree_counts_on_childless_card() {
    var counts = Logic.subtreeCounts(makeCard("solo", "todo"))
    compare(counts.done, 0)
    compare(counts.total, 0)
  }

  // A card's own status must never be folded into its descendant count --
  // the parent here is "done" but every descendant is still "todo".
  function test_subtree_counts_ignores_own_status_counts_descendants_only() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "done", [child])
    var counts = Logic.subtreeCounts(root)
    compare(counts.done, 0)
    compare(counts.total, 1)
  }

  function test_subtree_counts_counts_nested_descendants_recursively() {
    var grandchild1 = makeCard("g1", "done")
    var grandchild2 = makeCard("g2", "todo")
    var child = makeCard("child", "in_progress", [grandchild1, grandchild2])
    var root = makeCard("root", "todo", [child])
    var counts = Logic.subtreeCounts(root)
    compare(counts.total, 3)
    compare(counts.done, 1)
  }

  // ---- search --------------------------------------------------------

  function test_matches_query_is_case_insensitive_substring() {
    compare(Logic.matchesQuery("Write the Parser", "parser"), true)
    compare(Logic.matchesQuery("Write the Parser", "PARSER"), true)
    compare(Logic.matchesQuery("Write the Parser", "xyz"), false)
  }

  function test_matches_query_empty_query_matches_everything() {
    compare(Logic.matchesQuery("anything", ""), true)
    compare(Logic.matchesQuery("anything", "   "), true)
  }

  function test_subtree_matches_on_own_title() {
    var card = makeCard("root", "todo")
    card.title = "Fix the parser"
    compare(Logic.subtreeMatches(card, "parser"), true)
    compare(Logic.subtreeMatches(card, "nope"), false)
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
    compare(Logic.subtreeMatches(root, "parsers"), true)
    compare(Logic.subtreeMatches(child, "parsers"), true)
  }

  function test_subtree_matches_false_when_nothing_in_subtree_matches() {
    var child = makeCard("c", "todo")
    child.title = "Unrelated"
    var root = makeCard("root", "todo", [child])
    root.title = "Also unrelated"
    compare(Logic.subtreeMatches(root, "parsers"), false)
  }

  // ---- blocked state ---------------------------------------------------

  function test_is_blocked_false_with_no_blockers() {
    var card = makeCard("c", "todo", [], [])
    compare(Logic.isBlocked(card, {}), false)
  }

  function test_is_blocked_true_when_a_blocker_is_not_done() {
    var blocker = makeCard("b1", "in_progress")
    var card = makeCard("c", "todo", [], ["b1"])
    var map = Logic.indexTree([blocker]).cardMap
    compare(Logic.isBlocked(card, map), true)
  }

  function test_is_blocked_false_when_every_blocker_is_done() {
    var blocker = makeCard("b1", "done")
    var card = makeCard("c", "todo", [], ["b1"])
    var map = Logic.indexTree([blocker]).cardMap
    compare(Logic.isBlocked(card, map), false)
  }

  // Dangling blocked_by reference (blocker deleted from the board):
  // treated as still-blocking, not silently ignored.
  function test_is_blocked_true_when_a_blocker_id_is_missing_from_the_map() {
    var card = makeCard("c", "todo", [], ["ghost"])
    compare(Logic.isBlocked(card, {}), true)
  }

  function test_is_blocked_false_for_undefined_card() {
    compare(Logic.isBlocked(undefined, {}), false)
  }

  function test_subtree_matches_false_for_undefined_card() {
    compare(Logic.subtreeMatches(undefined, "x"), false)
  }

  // ---- colors, kinds, board order, detail links --------------------------

  function test_status_color_maps_known_statuses() {
    compare(Logic.statusColor("done", "#111111"), "#7fb069")
    compare(Logic.statusColor("blocked", "#111111"), "#e8954a")
    compare(Logic.statusColor("in_progress", "#111111"), "#5fa8d3")
  }

  function test_status_color_falls_back_for_todo_and_unknown() {
    compare(Logic.statusColor("todo", "#111111"), "#111111")
    compare(Logic.statusColor("weird", "#111111"), "#111111")
    compare(Logic.statusColor(undefined, "#111111"), "#111111")
  }

  function test_kind_label_by_depth() {
    compare(Logic.kindLabel(0), "Milestone")
    compare(Logic.kindLabel(1), "Story")
    compare(Logic.kindLabel(2), "Subtask")
    compare(Logic.kindLabel(7), "Subtask")
    compare(Logic.kindLabel(undefined), "Card")
    compare(Logic.kindLabel(-1), "Card")
  }

  function test_index_tree_annotates_depth() {
    var leaf = makeCard("leaf", "todo")
    var mid = makeCard("mid", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var map = Logic.indexTree([root]).cardMap
    compare(map["root"].depth, 0)
    compare(map["mid"].depth, 1)
    compare(map["leaf"].depth, 2)
  }

  function test_effective_status_folds_blocked_into_todo() {
    compare(Logic.effectiveStatus(makeCard("a", "blocked")), "todo")
    compare(Logic.effectiveStatus(makeCard("a", "done")), "done")
    compare(Logic.effectiveStatus(undefined), "todo")
  }

  function test_board_order_groups_by_section_in_order() {
    var a = makeCard("a", "done")
    var b = makeCard("b", "todo")
    var c = makeCard("c", "blocked")
    var d = makeCard("d", "in_progress")
    var ids = Logic.boardOrder([a, b, c, d], ["todo", "in_progress", "done"]).map(function(x) { return x.id })
    compare(ids.join(","), "b,c,d,a")
  }

  function test_board_order_empty() {
    compare(Logic.boardOrder([], ["todo", "in_progress", "done"]).length, 0)
  }

  function test_detail_links_orders_parent_blockers_children() {
    var kid = makeCard("kid", "todo")
    var dep = makeCard("dep", "todo")
    var mid = makeCard("mid", "todo", [kid], ["dep", "ghost"])
    var root = makeCard("root", "todo", [mid])
    var map = Logic.indexTree([root, dep]).cardMap
    var links = Logic.detailLinks(map["mid"], map)
    compare(links.map(function(l) { return l.section + ":" + l.id }).join(","), "parent:root,blocker:dep,child:kid")
  }

  function test_detail_links_skips_dangling_blockers_and_missing_parent() {
    var card = makeCard("c", "todo", [], ["ghost"])
    var map = Logic.indexTree([card]).cardMap
    compare(Logic.detailLinks(card, map).length, 0)
    compare(Logic.detailLinks(undefined, {}).length, 0)
  }
}
