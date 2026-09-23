import QtQuick
import QtTest
TestCase {
  id: testCase
  name: "DeleteFlow"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  function procByName(p, name) {
    for (var i = 0; i < p.data.length; i++)
      if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }

  function test_delete_flow() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    p.opened = true
    p.applyProjectsList([{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }])
    wait(50)
    var proc = procByName(p, "deleteProc")
    verify(proc, "deleteProc found (Task 1 gives it objectName deleteProc)")

    p.openDelete(p.projects[1])
    compare(p.deleteTarget.name, "beta")
    compare(p.displayPath("/home/u/b"), "~/b")
    p.confirmText = "delet"; p.performDelete(); compare(p.deleting, false)
    p.cancelDelete(); compare(p.deleteTarget, null)

    p.openDelete(p.projects[0])
    p.confirmText = " Delete "
    p.performDelete()
    compare(p.deleting, true)
    var cmd = proc.command
    compare(cmd[0], "python3")
    verify(String(cmd[1]).endsWith("snapshot-and-forget.py"))
    compare(cmd[2], "/home/u/a"); compare(cmd[3], "alpha")

    p.performDelete(); p.cancelDelete()
    compare(p.deleting, true)

    proc.outText = '{"ok": false, "error": "could not snapshot the project, so it was not removed"}'
    proc.exited(1)
    compare(p.deleting, false)
    verify(p.deleteTarget !== null)
    compare(p.deleteError, "could not snapshot the project, so it was not removed")

    p.confirmText = "delete"; p.performDelete()
    proc.outText = '{"ok": true, "snapshot": "/home/u/Snapshots/brd-viewer/alpha-1"}'
    proc.exited(0)
    compare(p.deleting, false); compare(p.deleteTarget, null)
    compare(p.lastSnapshot, "/home/u/Snapshots/brd-viewer/alpha-1")
    p.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    compare(p.selectedProject.root_path, "/home/u/b")
  }
}
