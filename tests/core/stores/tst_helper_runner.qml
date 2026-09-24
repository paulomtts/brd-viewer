// tests/core/stores/tst_helper_runner.qml
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresHelperRunner"

  property var events: []

  function make() {
    var comp = Qt.createComponent("../../../core/stores/HelperRunner.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var r = comp.createObject(tc, { script: "/plugin/core/backend/documents/list-docs.py" })
    tc.events = []
    r.finished.connect(function(stdout, exitCode, launchedGuard) {
      tc.events.push({ stdout: stdout, exitCode: exitCode, guard: launchedGuard })
    })
    return r
  }

  function test_run_launches_the_script_with_its_arguments_and_marks_the_runner_busy() {
    var r = make(); if (!r) return
    compare(r.busy, false)
    r.run(["/home/u/proj"])
    compare(r.busy, true)
    var proc = r.current
    verify(proc, "a process was created")
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/documents/list-docs.py")
    compare(proc.command[2], "/home/u/proj")
    compare(proc.command.length, 3)
    compare(proc.running, true)
  }

  function test_the_newest_runs_exit_emits_finished_with_the_stdout_and_exit_code() {
    var r = make(); if (!r) return
    r.guard = "/home/u/proj"
    r.run(["/home/u/proj"])
    var proc = r.current
    proc.outText = '{"ok": true, "docs": []}\n'
    proc.exited(0)
    compare(tc.events.length, 1)
    compare(tc.events[0].stdout, '{"ok": true, "docs": []}\n')
    compare(tc.events[0].exitCode, 0)
    compare(tc.events[0].guard, "/home/u/proj")
    compare(r.busy, false)
  }

  function test_a_late_exit_from_an_older_run_is_ignored() {
    var r = make(); if (!r) return
    r.run(["a"])
    var a = r.current
    r.run(["b"])
    var b = r.current
    compare(a.running, false, "the older run is stopped")
    a.outText = "stale"
    a.exited(0)
    compare(tc.events.length, 0)
    b.outText = "fresh"
    b.exited(0)
    compare(tc.events.length, 1)
    compare(tc.events[0].stdout, "fresh")
  }

  function test_a_stale_exit_after_the_newer_run_finished_emits_nothing_more() {
    var r = make(); if (!r) return
    r.run(["a"])
    var a = r.current
    r.run(["b"])
    var b = r.current
    b.outText = "fresh"
    b.exited(0)
    compare(tc.events.length, 1)
    a.outText = "stale"
    a.exited(0)
    compare(tc.events.length, 1)
    compare(tc.events[0].stdout, "fresh")
  }

  // An ignored stale exit must not clear `busy`: the newer run is still going.
  function test_an_ignored_stale_exit_leaves_the_runner_busy() {
    var r = make(); if (!r) return
    r.run(["a"])
    var a = r.current
    r.run(["b"])
    var b = r.current
    a.exited(0)
    compare(r.busy, true, "the newer run is still in flight")
    b.exited(0)
    compare(r.busy, false)
  }

  // Every run gets its own Process; without the destroy they would pile up for
  // the life of the panel.
  function test_the_per_run_process_is_destroyed_after_it_exits() {
    var r = make(); if (!r) return
    r.run(["a"])
    var proc = r.current
    verify(proc, "a process was created")
    proc.exited(0)
    wait(50)
    verify(!r.current, "the process object is gone")
    compare(proc.command, undefined, "and its properties are no longer readable")
  }

  function test_a_result_is_dropped_when_the_guard_changed_since_the_launch() {
    var r = make(); if (!r) return
    r.guard = "/home/u/a"
    r.run(["/home/u/a"])
    var proc = r.current
    r.guard = "/home/u/b"
    proc.outText = "for a"
    proc.exited(0)
    compare(tc.events.length, 0)
  }

  function test_cancel_drops_the_running_run() {
    var r = make(); if (!r) return
    r.run(["a"])
    var proc = r.current
    r.cancel()
    compare(r.busy, false)
    compare(proc.running, false)
    proc.outText = "late"
    proc.exited(0)
    compare(tc.events.length, 0)
  }
}
