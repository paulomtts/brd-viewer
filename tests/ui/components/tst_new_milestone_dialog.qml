import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "NewMilestoneDialog"
  when: windowShown
  visible: true
  width: 640; height: 700

  readonly property var docs: [
    { title: "New milestone", path: "docs/specs/new-milestone.md", category: "specs" },
    { title: "Architecture", path: "docs/architecture.md", category: "" },
    { title: "Board notes", path: "docs/board-notes.md", category: "" }
  ]

  Component { id: dialogC; UI.NewMilestoneDialog { width: 600; height: 660 } }
  SignalSpy { id: specs; signalName: "specChosen" }
  SignalSpy { id: submits; signalName: "submitRequested" }
  SignalSpy { id: cancels; signalName: "cancelRequested" }

  function make() {
    var d = createTemporaryObject(dialogC, tc)
    specs.target = d; submits.target = d; cancels.target = d
    specs.clear(); submits.clear(); cancels.clear()
    d.specs = tc.docs
    d.shown = true
    wait(30)
    return d
  }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }

  // ---- shell ------------------------------------------------------------

  function test_it_is_hidden_until_shown_and_heads_the_card() {
    var d = createTemporaryObject(dialogC, tc)
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
    verify(H.find(d, "newMilestoneCard"), "the modal card")
    verify(H.find(d, "newMilestoneBackdrop"), "the backdrop")
    compare(H.find(d, "newMilestoneHeading").text, "New milestone")
  }

  // ---- the spec list ----------------------------------------------------

  // The modal is the spec picker: the search, the list and Start, with no mode
  // to choose first.
  function test_the_card_is_the_spec_picker() {
    var d = make()
    verify(H.find(d, "newMilestoneSpecs").visible, "the spec column")
    verify(H.find(d, "newMilestoneSearch").visible, "the search field")
    compare(H.find(d, "newMilestoneOk").text, "Start")
    verify(!H.find(d, "milestoneModemanual"), "no mode switch")
    verify(!H.find(d, "milestoneModespec"), "no mode switch")
    verify(!H.find(d, "newMilestoneTitle"), "no title field")
    verify(!H.find(d, "newMilestoneDescription"), "no description field")
  }

  function test_ok_needs_a_selected_spec() {
    var d = make()
    compare(H.find(d, "newMilestoneOk").enabled, false)
    d.selectedSpec = "docs/specs/new-milestone.md"
    compare(H.find(d, "newMilestoneOk").enabled, true)
    click(H.find(d, "newMilestoneOk"))
    compare(submits.count, 1)
  }

  function test_ok_stays_disabled_while_the_agent_cannot_run() {
    var d = make()
    d.selectedSpec = "docs/specs/new-milestone.md"
    d.agentMessage = "No default agent is set."
    compare(H.find(d, "newMilestoneOk").enabled, false)
    click(H.find(d, "newMilestoneOk"))
    compare(submits.count, 0)
  }

  function test_the_spec_rows_show_the_title_the_path_and_the_category_badge() {
    var d = make()
    compare(H.find(d, "specRowTitle0").text, "New milestone")
    compare(H.find(d, "specRowPath0").text, "docs/specs/new-milestone.md")
    compare(H.find(d, "specRowPath0").elide, Text.ElideMiddle)
    compare(H.find(d, "specRowBadge0").text, "Specs")
    verify(H.find(d, "specRow2"), "the third row")
    verify(!H.find(d, "specRow3"), "no fourth row")
  }

  function test_clicking_a_row_reports_the_path_and_the_selected_row_is_marked() {
    var d = make()
    compare(H.find(d, "specRow1").hasCursor, false)
    click(H.find(d, "specRow1"))
    compare(specs.count, 1)
    compare(specs.signalArguments[0][0], "docs/architecture.md")
    d.selectedSpec = "docs/architecture.md"
    compare(H.find(d, "specRow1").hasCursor, true)
    compare(H.find(d, "specRow0").hasCursor, false)
  }

  function test_the_search_field_narrows_the_list_by_title_and_by_path() {
    var d = make()
    H.find(d, "newMilestoneSearch").text = "architecture"
    compare(H.find(d, "specRowTitle0").text, "Architecture")
    verify(!H.find(d, "specRow1"), "only the match is listed")
    H.find(d, "newMilestoneSearch").text = "docs/specs"
    compare(H.find(d, "specRowTitle0").text, "New milestone")
  }

  function test_the_list_words_its_empty_states() {
    var d = make()
    var status = H.find(d, "specsMessage")
    compare(status.visible, false)
    H.find(d, "newMilestoneSearch").text = "zzz"
    compare(status.text, "No documents match “zzz”.")
    H.find(d, "newMilestoneSearch").text = ""
    d.specs = []
    compare(status.text, "No documents found in this project.")
  }

  function test_the_list_says_it_is_loading_or_why_it_could_not_instead_of_being_empty() {
    var d = make()
    d.specs = []
    var status = H.find(d, "specsMessage")
    compare(status.text, "No documents found in this project.")
    d.docsLoading = true
    compare(status.text, "Loading documents…")
    verify(!H.find(d, "specRow0"), "nothing is listed while it loads")
    d.docsLoading = false
    d.docsError = "list-docs.py failed."
    compare(status.text, "list-docs.py failed.")
  }

  function test_an_error_hides_the_rows_it_could_not_trust() {
    var d = make()
    verify(H.find(d, "specRow0"), "the rows are there")
    d.docsError = "list-docs.py failed."
    verify(!H.find(d, "specRow0"), "and gone once the listing failed")
  }

  function test_the_arrows_in_the_search_move_the_selection_through_the_visible_rows() {
    var d = make()
    var search = H.find(d, "newMilestoneSearch")
    search.forceActiveFocus()
    keyClick(Qt.Key_Down)
    compare(specs.count, 1)
    compare(specs.signalArguments[0][0], "docs/specs/new-milestone.md")
    d.selectedSpec = "docs/specs/new-milestone.md"
    keyClick(Qt.Key_Down)
    compare(specs.signalArguments[1][0], "docs/architecture.md")
    d.selectedSpec = "docs/architecture.md"
    keyClick(Qt.Key_Up)
    compare(specs.signalArguments[2][0], "docs/specs/new-milestone.md")
  }

  function test_the_arrows_stop_at_the_ends_and_only_walk_what_the_search_left() {
    var d = make()
    var search = H.find(d, "newMilestoneSearch")
    search.text = "architecture"
    search.forceActiveFocus()
    keyClick(Qt.Key_Up)
    compare(specs.signalArguments[0][0], "docs/architecture.md")
    d.selectedSpec = "docs/architecture.md"
    keyClick(Qt.Key_Down)
    compare(specs.signalArguments[1][0], "docs/architecture.md")
    search.text = "zzz"
    var before = specs.count
    keyClick(Qt.Key_Down)
    compare(specs.count, before)
  }

  function test_return_in_the_search_submits_only_when_the_run_is_valid() {
    var d = make()
    H.find(d, "newMilestoneSearch").forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(submits.count, 0)
    d.selectedSpec = "docs/architecture.md"
    keyClick(Qt.Key_Return)
    compare(submits.count, 1)
  }

  function test_the_search_field_takes_the_focus() {
    var d = make()
    compare(d.focusItem, H.find(d, "newMilestoneSearch"))
  }

  function test_the_agent_line_names_the_agent_and_its_note() {
    var d = make()
    d.agentName = "claude"
    d.agentNote = "runs with full auto-approval"
    var agent = H.find(d, "newMilestoneAgent")
    compare(agent.visible, true)
    compare(agent.text, "Agent: claude")
    compare(H.find(d, "newMilestoneAgentNote").text, "runs with full auto-approval")
    compare(H.find(d, "newMilestoneAgentMessage").visible, false)
  }

  function test_the_agent_message_replaces_the_agent_line_in_the_urgent_colour() {
    var d = make()
    d.agentName = "gemini"
    d.agentMessage = "gemini has no supported unattended mode."
    var message = H.find(d, "newMilestoneAgentMessage")
    compare(message.visible, true)
    compare(message.text, "gemini has no supported unattended mode.")
    compare(message.color, d.theme.urgent)
    compare(H.find(d, "newMilestoneAgent").visible, false)
  }

  function test_an_agent_error_shows_in_the_message_line_and_disables_ok() {
    var d = make()
    d.selectedSpec = "docs/architecture.md"
    compare(H.find(d, "newMilestoneOk").enabled, true)
    d.agentMessage = "omarchy-default-agent failed: exit 2"
    compare(H.find(d, "newMilestoneAgentMessage").visible, true)
    compare(H.find(d, "newMilestoneAgentMessage").text, "omarchy-default-agent failed: exit 2")
    compare(H.find(d, "newMilestoneOk").enabled, false)
  }

  // One job per shell: a run already going is not something a second Start
  // could ever fix, so the dialog says so and refuses.
  function test_a_run_already_in_progress_freezes_start_and_says_so() {
    var d = make()
    d.selectedSpec = "docs/architecture.md"
    var line = H.find(d, "newMilestoneJobRunning")
    verify(line, "the in-progress line")
    compare(line.visible, false)
    compare(H.find(d, "newMilestoneOk").enabled, true)
    d.jobRunning = true
    compare(line.visible, true)
    compare(line.text, "A milestone run is already in progress.")
    compare(H.find(d, "newMilestoneOk").enabled, false)
    click(H.find(d, "newMilestoneOk"))
    compare(submits.count, 0, "and nothing is submitted")
  }

  // The owner has the last word on whether a run may start: an agent nobody has
  // checked yet has nothing to report and is still not one to run on.
  function test_the_owner_can_veto_a_run_with_agent_ready() {
    var d = make()
    d.selectedSpec = "docs/architecture.md"
    compare(d.agentReady, true, "on its own the dialog trusts a silent check")
    compare(H.find(d, "newMilestoneOk").enabled, true)
    d.agentReady = false
    compare(H.find(d, "newMilestoneAgentMessage").visible, false, "nothing to report")
    compare(H.find(d, "newMilestoneOk").enabled, false, "but no run either")
  }

  function test_while_the_agent_is_being_checked_ok_waits_and_the_dialog_says_so() {
    var d = make()
    var checking = H.find(d, "newMilestoneAgentChecking")
    compare(checking.visible, false)
    d.selectedSpec = "docs/architecture.md"
    compare(H.find(d, "newMilestoneOk").enabled, true)
    d.agentChecking = true
    compare(checking.visible, true)
    compare(checking.text, "Checking the default agent…")
    compare(H.find(d, "newMilestoneOk").enabled, false)
    compare(H.find(d, "newMilestoneAgent").visible, false)
    d.agentChecking = false
    compare(H.find(d, "newMilestoneOk").enabled, true)
  }

  // ---- errors and cancelling --------------------------------------------

  function test_the_error_line_shows_only_when_there_is_one() {
    var d = make()
    compare(H.find(d, "newMilestoneError").visible, false)
    d.error = "brd add failed."
    compare(H.find(d, "newMilestoneError").visible, true)
    compare(H.find(d, "newMilestoneError").text, "brd add failed.")
    compare(H.find(d, "newMilestoneError").color, d.theme.urgent)
  }

  function test_cancel_the_backdrop_and_escape_all_cancel_but_the_card_does_not() {
    var d = make()
    click(H.find(d, "newMilestoneCancel"))
    compare(cancels.count, 1)
    mouseClick(H.find(d, "newMilestoneBackdrop"), 2, 2)
    compare(cancels.count, 2)
    mouseClick(H.find(d, "newMilestoneCard"), 3, 3)
    compare(cancels.count, 2)
  }

  function test_escape_in_the_spec_search_cancels_too() {
    var d = make()
    H.find(d, "newMilestoneSearch").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
  }

  // ---- what a reopen keeps ----------------------------------------------

  function test_reopening_clears_the_search() {
    var d = make()
    H.find(d, "newMilestoneSearch").text = "architecture"
    d.shown = false
    d.shown = true
    compare(H.find(d, "newMilestoneSearch").text, "")
  }
}
