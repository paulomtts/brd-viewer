import QtQml
import Quickshell
import Quickshell.Io
import "../domain/milestones.js" as Milestones

// Creating a milestone: the New-milestone dialog (always a spec handed to the
// default coding agent) and the one agent job the shell may have running, as a
// small state machine (idle -> running -> done|failed). The project, the
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
  property int cardsFrozen: -1        // the count as it stood when the job ended
  property bool cardsCountKnown: true // false when the job ended away from its own board
  property bool jobDismissed: false

  // The agent check is on its way: the dialog says so rather than showing a
  // verdict nobody has reached yet.
  readonly property bool agentChecking: describeRunner.busy
  readonly property string agentMessage: Milestones.agentMessage(store.agentInfo)
  // An agent nobody has checked is not an agent to run on: an empty
  // `agentMessage` is not enough on its own.
  readonly property bool agentReady: store.agentInfo !== null && store.agentMessage === ""
  // Live while the job runs, frozen at its end so later board changes cannot
  // keep inflating the result.
  readonly property int cardsCreated: store.cardsFrozen >= 0
    ? store.cardsFrozen : Math.max(0, store.cardCount - store.cardsAtStart)
  // A job started for another project keeps running, but it is not this
  // project's business: only its own project's panel shows it.
  readonly property bool jobVisible: store.jobState !== "idle"
    && store.jobProject === (store.project ? store.project.root_path : "")
    && !store.jobDismissed

  readonly property alias specRunner: specRunner
  readonly property alias describeRunner: describeRunner

  // The board gained cards: App refetches it.
  signal boardRefreshRequested()

  // Everything the old project left behind, on a project change. Only the
  // dialog is cleared: a job still running belongs to the project the user has
  // left and deliberately keeps running there (see `jobVisible`).
  function reset() {
    store.dialogOpen = false
    store.selectedSpec = ""
    store.dialogError = ""
    store.agentInfo = null
  }

  // Every milestone comes from a spec, so the agent matters from the moment the
  // dialog opens. Asked for once per project: the answer cannot change while
  // the user stays in it, and `reset()` forgets it when they leave.
  function openDialog() {
    store.dialogOpen = true
    store.selectedSpec = ""
    store.dialogError = ""
    if (store.agentInfo === null) store.checkAgent()
  }

  function checkAgent() {
    if (describeRunner.busy) return
    describeRunner.run(["--describe"])
  }

  // Escape and the backdrop close the dialog. Nothing is ever in flight behind
  // it: starting a run closes it itself.
  function cancelDialog() {
    store.dialogOpen = false
    store.dialogError = ""
  }

  function applyDescribeResult(text, exitCode) {
    store.agentInfo = Milestones.parseDescribeResult(text, exitCode)
  }

  // One job per shell: refused while one runs, without a spec, and without an
  // agent that can run unattended.
  function startFromSpec() {
    if (!store.project) return
    // One job per shell -- including one started from a project the dialog is
    // not showing. Say so instead of ignoring the click.
    if (store.jobState === "running") {
      store.dialogError = "A milestone run is already in progress."
      return
    }
    if (!store.agentReady || store.selectedSpec === "") return
    store.cardsCountKnown = true
    store.jobState = "running"
    store.jobProject = store.project.root_path
    store.jobAgent = store.agentInfo ? String(store.agentInfo.agent || "") : ""
    store.jobStartedAt = Date.now()
    store.cardsAtStart = store.cardCount
    store.cardsFrozen = -1
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
    store.endJobBookkeeping()
  }

  // Cancel ends the job here and now: `cancel()` stops the helper (which kills
  // the agent's whole process group) and makes its exit be ignored, so nothing
  // else would ever move the job out of "running".
  function cancelJob() {
    if (store.jobState !== "running") return
    store.jobState = "failed"
    store.jobError = "Cancelled."
    specRunner.cancel()
    store.endJobBookkeeping()
  }

  // What every ending has in common. The count is ALWAYS frozen: a job that has
  // ended must never keep counting later board changes as its own. It can only
  // be counted against the job's own board, though -- when the job ends while
  // another project is selected, the number on screen belongs to that other
  // project, so nothing is claimed (`cardsCountKnown` is false and the UI drops
  // the count) rather than a figure being invented. Only the board refresh is
  // gated on the project: it is this project's board that would be refetched.
  function endJobBookkeeping() {
    var own = store.project && store.project.root_path === store.jobProject
    store.cardsFrozen = own ? Math.max(0, store.cardCount - store.cardsAtStart) : 0
    store.cardsCountKnown = own
    if (own) store.boardRefreshRequested()
  }

  function dismissResult() {
    if (store.jobState === "running") return
    store.jobDismissed = true
  }

  HelperRunner {
    id: describeRunner
    script: store.backendDir + "milestones/run-setup-milestone.py"
    guard: store.project ? store.project.root_path : ""
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyDescribeResult(stdout, exitCode) }
  }

  // The job's guard is the project the JOB is for, not the selected one: the
  // run outlives a project switch on purpose, so its result must still reach
  // the job it belongs to and be recorded truthfully. That also means the
  // newest run's exit always emits `finished` -- the job can never be left
  // "running" because the user wandered off. Which project's panel shows the
  // result is `jobVisible`'s business, and refreshing a board is
  // `endJobBookkeeping`'s.
  HelperRunner {
    id: specRunner
    script: store.backendDir + "milestones/run-setup-milestone.py"
    guard: store.jobProject
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyRunResult(stdout, exitCode, launchedGuard) }
  }
}
