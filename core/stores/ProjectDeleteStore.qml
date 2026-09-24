import QtQml
import Quickshell
import Quickshell.Io
import "../domain/projects.js" as Projects

// Deleting a project (brd forget). Always gated behind typing "delete", and
// snapshot-and-forget.py saves a snapshot first and refuses to forget if it
// cannot.
Scope {
  id: deleter

  property string backendDir: ""   // <plugin>/core/backend/
  property var projects: null      // the ProjectStore, set by App

  property var deleteTarget: null  // { root_path, name } | null
  property string confirmText: ""
  property bool deleting: false
  property string deleteError: ""
  property string lastSnapshot: ""

  readonly property alias deleteProc: deleteProc

  // The confirmation opened (the dropdown closes, the field takes focus).
  signal requested()
  // The confirmation closed without deleting.
  signal closed()
  // A project was removed.
  signal deleted()

  function openDelete(project) {
    if (deleter.deleting || !project) return
    deleter.deleteTarget = project
    deleter.confirmText = ""
    deleter.deleteError = ""
    deleter.lastSnapshot = ""
    deleter.requested()
  }

  function cancelDelete() {
    if (deleter.deleting) return
    deleter.deleteTarget = null
    deleter.confirmText = ""
    deleter.deleteError = ""
    deleter.closed()
  }

  function performDelete() {
    if (deleter.deleting || !deleter.deleteTarget) return
    if (!Projects.isDeleteConfirmed(deleter.confirmText)) return
    deleter.deleteError = ""
    deleter.deleting = true
    deleteProc.command = ["python3", deleter.backendDir + "projects/snapshot-and-forget.py",
      deleter.deleteTarget.root_path, deleter.deleteTarget.name]
    deleteProc.running = true
  }

  // The panel was opened: a half-typed confirmation is dropped, a delete that
  // is already running is not.
  function onPanelOpened() {
    if (deleter.deleting) return
    deleter.deleteTarget = null
    deleter.confirmText = ""
    deleter.deleteError = ""
  }

  // snapshot-and-forget.py prints one JSON line and exits 0/1; nothing here
  // assumes success until Projects.parseDeleteResult says so.
  Process {
    id: deleteProc
    objectName: "deleteProc"
    property string outText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: deleteProc.outText = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var result = Projects.parseDeleteResult(deleteProc.outText, exitCode)
      deleteProc.outText = ""
      deleter.deleting = false
      if (result.ok) {
        deleter.deleteTarget = null
        deleter.confirmText = ""
        deleter.lastSnapshot = result.snapshot
        deleter.deleted()
        if (deleter.projects) deleter.projects.refreshProjects()
      } else {
        deleter.deleteError = result.error
      }
    }
  }
}
