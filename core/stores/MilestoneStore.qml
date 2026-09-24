import QtQml
import Quickshell
import Quickshell.Io
import "../domain/milestones.js" as Milestones

// Creating a milestone: the New-milestone dialog (by hand, or by handing a spec
// to the default coding agent) and the one agent job the shell may have running,
// as a small state machine (idle -> running -> done|failed). The project, the
// backend directory and the number of cards the board knows about are handed to
// it by App -- it never reaches for another store. The dialog's looks, the spec
// picker and the running indicator stay in the UI.
Scope {
  id: store

  property string backendDir: ""      // <plugin>/core/backend/
  property var project: null          // set by App from ProjectStore.selectedProject
  property int cardCount: 0           // set by App from the board store's card count

  // The dialog
  property bool dialogOpen: false
  property string mode: "manual"      // "manual" | "spec"
  property string title: ""
  property string description: ""
  property string selectedSpec: ""    // path relative to the project root
  property var agentInfo: null        // the last `--describe` answer
  property string dialogError: ""

  // The job
  property string jobState: "idle"    // "idle" | "running" | "done" | "failed"
  property string jobProject: ""      // the project root the job was started for
  property string jobAgent: ""
  property real jobStartedAt: 0       // ms since the epoch
  property string jobLog: ""
  property string jobError: ""
  property int cardsAtStart: 0
  property bool jobDismissed: false

  // One create at a time, from its launch until the helper's own exit -- even
  // when the user has left the project meanwhile.
  readonly property bool dialogBusy: manualRunner.busy

  readonly property string agentMessage: Milestones.agentMessage(store.agentInfo)
  readonly property int cardsCreated: Math.max(0, store.cardCount - store.cardsAtStart)
  // A job started for another project keeps running, but it is not this
  // project's business: only its own project's panel shows it.
  readonly property bool jobVisible: store.jobState !== "idle"
    && store.jobProject === (store.project ? store.project.root_path : "")
    && !store.jobDismissed

  readonly property alias manualRunner: manualRunner
  readonly property alias specRunner: specRunner
  readonly property alias describeRunner: describeRunner

  // The board gained cards: App refetches it.
  signal boardRefreshRequested()

  // Everything the old project left behind, on a project change. Only the
  // dialog is cleared: a job still running belongs to the project the user has
  // left and deliberately keeps running there (see `jobVisible`).
  function reset() {
    store.dialogOpen = false
    store.mode = "manual"
    store.title = ""
    store.description = ""
    store.selectedSpec = ""
    store.dialogError = ""
    store.agentInfo = null
  }

  function openDialog() {
    store.dialogOpen = true
    store.mode = "manual"
    store.title = ""
    store.description = ""
    store.selectedSpec = ""
    store.dialogError = ""
    describeRunner.run(["--describe"])
  }

  // Escape and the backdrop close the dialog -- but never while the create is
  // in flight, which would leave the user with no sign of what happened.
  function cancelDialog() {
    if (store.dialogBusy) return
    store.dialogOpen = false
    store.dialogError = ""
  }

  function applyDescribeResult(text, exitCode) {
    store.agentInfo = Milestones.parseDescribeResult(text, exitCode)
  }

  function createManual() {
    if (!store.project || store.dialogBusy) return
    var name = String(store.title).trim()
    if (name === "") {
      store.dialogError = "A title is required."
      return
    }
    store.dialogError = ""
    var args = [store.project.root_path, "--title", name]
    var desc = String(store.description).trim()
    if (desc !== "") args.push("--description", desc)
    manualRunner.run(args)
  }

  function applyCreateResult(text, exitCode) {
    var result = Milestones.parseCreateResult(text, exitCode)
    if (!result.ok) {
      store.dialogError = result.error
      return
    }
    store.dialogOpen = false
    store.title = ""
    store.description = ""
    store.dialogError = ""
    store.boardRefreshRequested()
  }

  // One job per shell: refused while one runs, without a spec, and without an
  // agent that can run unattended.
  function startFromSpec() {
    if (!store.project || store.jobState === "running") return
    if (store.agentMessage !== "" || store.selectedSpec === "") return
    store.jobState = "running"
    store.jobProject = store.project.root_path
    store.jobAgent = store.agentInfo ? String(store.agentInfo.agent || "") : ""
    store.jobStartedAt = Date.now()
    store.cardsAtStart = store.cardCount
    store.jobLog = ""
    store.jobError = ""
    store.jobDismissed = false
    specRunner.run([store.project.root_path, store.selectedSpec])
    store.dialogOpen = false
    store.dialogError = ""
  }

  function applyRunResult(text, exitCode, launchedGuard) {
    // Only the job that is actually running, and only its own project's run.
    // The runner's seq and guard already drop everything else; this is the last
    // line of defence, so a result can never revive a finished job.
    if (store.jobState !== "running" || launchedGuard !== store.jobProject) return
    var result = Milestones.parseRunResult(text, exitCode)
    if (result.agent !== "") store.jobAgent = result.agent
    if (result.log !== "") store.jobLog = result.log
    store.jobState = result.ok ? "done" : "failed"
    store.jobError = result.ok ? "" : result.error
    store.boardRefreshRequested()
  }

  // Cancel ends the job here and now: `cancel()` stops the helper (which kills
  // the agent's whole process group) and makes its exit be ignored, so nothing
  // else would ever move the job out of "running".
  function cancelJob() {
    if (store.jobState !== "running") return
    store.jobState = "failed"
    store.jobError = "Cancelled."
    specRunner.cancel()
    store.boardRefreshRequested()
  }

  function dismissResult() {
    if (store.jobState === "running") return
    store.jobDismissed = true
  }

  // The guard is the selected project's root: a result for a project the user
  // has since left can never be applied.
  HelperRunner {
    id: manualRunner
    script: store.backendDir + "milestones/create-milestone.py"
    guard: store.project ? store.project.root_path : ""
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyCreateResult(stdout, exitCode) }
  }

  HelperRunner {
    id: describeRunner
    script: store.backendDir + "milestones/run-setup-milestone.py"
    guard: store.project ? store.project.root_path : ""
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyDescribeResult(stdout, exitCode) }
  }

  HelperRunner {
    id: specRunner
    script: store.backendDir + "milestones/run-setup-milestone.py"
    guard: store.project ? store.project.root_path : ""
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyRunResult(stdout, exitCode, launchedGuard) }
    // The newest run's exit always releases `busy`, even when the guard has
    // changed and its result is dropped. The job state has no such release of
    // its own, so it is ended here instead of staying "running" forever: the
    // guard differing from the job's project is exactly the case where no
    // `finished` will follow.
    onBusyChanged: {
      if (specRunner.busy || store.jobState !== "running") return
      if (specRunner.guard === store.jobProject) return
      store.jobState = "failed"
      store.jobError = "The run ended while another project was selected; its result was not read."
      store.boardRefreshRequested()
    }
  }
}
