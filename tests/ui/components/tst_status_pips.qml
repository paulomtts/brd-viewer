// tests/ui/components/tst_status_pips.qml
// ui/components/StatusPips.qml: one small circle per subtask, coloured by the
// board's own status colours, with the overflow collapsed into a "+N" and the
// in-progress ones pulsing -- but only while one of them is visible.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../core/domain/board.js" as Board
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "StatusPips"
  when: windowShown
  visible: true
  width: 400; height: 200

  Component { id: pipsC; UI.StatusPips {} }

  function make(model, more) {
    var pips = createTemporaryObject(pipsC, tc)
    pips.model = model
    pips.more = more || 0
    wait(30)
    return pips
  }

  function test_one_pip_per_subtask_in_the_board_status_colour() {
    var pips = make([{ id: "t1", status: "done" }, { id: "t2", status: "in_progress" },
                     { id: "t3", status: "blocked" }, { id: "t4", status: "todo" }])
    var done = H.find(pips, "statusPipt1")
    verify(done, "a pip per subtask")
    verify(done.width > 0 && done.height > 0)
    compare(done.radius, done.height / 2, "a pip is a circle")
    verify(Qt.colorEqual(done.color, Board.statusColor("done", pips.palette.dim)))
    verify(Qt.colorEqual(H.find(pips, "statusPipt2").color, Board.statusColor("in_progress", pips.palette.dim)))
    verify(Qt.colorEqual(H.find(pips, "statusPipt3").color, Board.statusColor("blocked", pips.palette.dim)))
    verify(Qt.colorEqual(H.find(pips, "statusPipt4").color, pips.palette.dim), "todo takes the theme's neutral")
  }

  function test_a_story_without_subtasks_shows_nothing() {
    var pips = make([])
    compare(pips.visible, false)
    compare(H.find(pips, "statusPipsMore").visible, false)
  }

  function test_the_overflow_collapses_into_a_plus_n() {
    var pips = make([{ id: "t1", status: "todo" }], 0)
    compare(H.find(pips, "statusPipsMore").visible, false)
    pips.more = 4
    wait(30)
    var more = H.find(pips, "statusPipsMore")
    compare(more.visible, true)
    compare(more.text, "+4")
  }

  function test_only_in_progress_pips_pulse_and_an_idle_row_costs_nothing() {
    var still = make([{ id: "t1", status: "done" }, { id: "t2", status: "todo" }])
    compare(still.pulsing, false, "no in-progress pip: no animation")
    compare(H.find(still, "statusPipt1").opacity, 1)

    var live = make([{ id: "t1", status: "done" }, { id: "t2", status: "in_progress" }])
    compare(live.pulsing, true)
    compare(H.find(live, "statusPipt1").opacity, 1, "other statuses stay static")
    wait(120)
    verify(H.find(live, "statusPipt2").opacity < 1, "the in-progress pip fades")

    live.visible = false
    wait(30)
    compare(live.pulsing, false, "a hidden row runs nothing")
    live.visible = true
    wait(30)
    compare(live.pulsing, true)

    live.model = [{ id: "t1", status: "done" }]
    wait(30)
    compare(live.pulsing, false)
    compare(H.find(live, "statusPipt1").opacity, 1, "the fade is undone when it stops")
  }
}
