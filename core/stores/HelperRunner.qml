import QtQml
import Quickshell
import Quickshell.Io

// One helper script, latest run wins. Each run gets its own Process carrying the
// sequence number and guard it was launched with, so a late exit from an older
// run -- or from a run whose guard (e.g. the selected project) has since changed
// -- can never be mistaken for the current one. Parsing is the caller's job: the
// runner hands out the raw stdout and exit code.
Scope {
  id: runner

  property string script: ""            // absolute path
  property bool busy: false
  property string guard: ""             // a result is applied only if this still equals the guard at launch
  property int seq: 0
  property var current: null

  signal finished(string stdout, int exitCode, string launchedGuard)

  // args: string[]; stops the previous run.
  function run(args) {
    if (current) current.running = false
    seq += 1
    busy = true
    var proc = procC.createObject(runner, { launchSeq: seq, launchGuard: guard })
    proc.command = ["python3", script].concat(args || [])
    current = proc
    proc.running = true
  }

  function cancel() {
    seq += 1
    if (current) current.running = false
    busy = false
  }

  Component {
    id: procC

    Process {
      id: p
      property int launchSeq: 0
      property string launchGuard: ""
      property string outText: ""
      stdout: StdioCollector { waitForEnd: true; onStreamFinished: p.outText = String(text || "") }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        if (p.launchSeq === runner.seq && p.launchGuard === runner.guard) {
          runner.busy = false
          runner.finished(p.outText, exitCode, p.launchGuard)
        }
        p.destroy()
      }
    }
  }
}
