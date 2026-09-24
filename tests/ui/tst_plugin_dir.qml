// tests/ui/tst_plugin_dir.qml
// `pluginDir` is how every Python helper is found, and nothing else in the
// suite notices when it points at the wrong directory: the store tests only
// assert the file NAME at the end of the command. So this test takes the
// absolute path a real panel hands its stores and checks that the script is
// actually there -- the check that catches `Qt.resolvedUrl(".")` still meaning
// "the folder Panel.qml sits in" after Panel.qml moved into ui/.
import QtQuick
import QtTest
import Qt.labs.folderlistmodel

TestCase {
  id: tc
  name: "PanelPluginDir"
  when: windowShown
  width: 400; height: 400

  Component { id: hostC; Item { width: 400; height: 400 } }

  // A directory listing is the only filesystem read QML offers here
  // (XMLHttpRequest refuses file:// URLs unless QML_XHR_ALLOW_FILE_READ is set).
  FolderListModel { id: folder; showDirs: true; showFiles: true; showDotAndDotDot: false }

  function fileExists(path) {
    var slash = path.lastIndexOf("/")
    var dir = path.substring(0, slash)
    var name = path.substring(slash + 1)
    folder.folder = "file://" + dir
    // The model loads asynchronously and still reports the previous folder's
    // status for a turn, so poll until it has entries (every directory this
    // test asks about is non-empty when it exists) or the budget runs out.
    for (var t = 0; t < 40; t++) {
      if (folder.status === FolderListModel.Ready && folder.count > 0) break
      tc.wait(20)
    }
    for (var i = 0; i < folder.count; i++)
      if (folder.get(i, "fileName") === name) return true
    return false
  }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(host)
  }

  function test_the_state_helper_path_a_store_receives_points_at_a_real_script() {
    var p = make(); if (!p) return
    var get = p.app.projects.stateRunner.current
    verify(get, "the state helper is running")
    var script = String(get.command[1])
    verify(script.indexOf("/") === 0, "not an absolute path: " + script)
    verify(script.endsWith("/core/backend/projects/viewer-state.py"), script)
    verify(fileExists(script), "no such file: " + script)
  }

  function test_the_plugin_dir_is_the_plugin_root_not_the_folder_the_panel_lives_in() {
    var p = make(); if (!p) return
    verify(p.pluginDir.endsWith("/"), p.pluginDir)
    verify(fileExists(p.pluginDir + "manifest.json"), "not the plugin root: " + p.pluginDir)
    verify(fileExists(p.pluginDir + "core/backend/projects/viewer-state.py"), p.pluginDir)
    compare(p.app.backendDir, p.pluginDir + "core/backend/")
  }
}
