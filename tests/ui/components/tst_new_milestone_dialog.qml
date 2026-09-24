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
  SignalSpy { id: modes; signalName: "modeChosen" }
  SignalSpy { id: titles; signalName: "titleEdited" }
  SignalSpy { id: descriptions; signalName: "descriptionEdited" }
  SignalSpy { id: specs; signalName: "specChosen" }
  SignalSpy { id: submits; signalName: "submitRequested" }
  SignalSpy { id: cancels; signalName: "cancelRequested" }

  function make(mode) {
    var d = createTemporaryObject(dialogC, tc)
    modes.target = d; titles.target = d; descriptions.target = d
    specs.target = d; submits.target = d; cancels.target = d
    modes.clear(); titles.clear(); descriptions.clear()
    specs.clear(); submits.clear(); cancels.clear()
    d.specs = tc.docs
    d.mode = mode || "manual"
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

  function test_the_mode_switch_offers_manual_and_from_spec_and_reports_the_choice() {
    var d = make("manual")
    compare(H.find(d, "milestoneModemanual").active, true)
    compare(H.find(d, "milestoneModespec").active, false)
    compare(H.find(d, "milestoneModemanual").text, "Manual")
    compare(H.find(d, "milestoneModespec").text, "From spec")
    click(H.find(d, "milestoneModespec"))
    compare(modes.count, 1)
    compare(modes.signalArguments[0][0], "spec")
  }

  function test_each_mode_shows_only_its_own_fields() {
    var d = make("manual")
    compare(H.find(d, "newMilestoneTitle").visible, true)
    compare(H.find(d, "newMilestoneSpecs").visible, false)
    d.mode = "spec"
    compare(H.find(d, "newMilestoneTitle").visible, false)
    compare(H.find(d, "newMilestoneSpecs").visible, true)
    compare(H.find(d, "newMilestoneSearch").visible, true)
  }

  // ---- manual mode ------------------------------------------------------

  function test_ok_needs_a_title_in_manual_mode_and_submitting_reports_it() {
    var d = make("manual")
    compare(H.find(d, "newMilestoneOk").enabled, false)
    H.find(d, "newMilestoneTitle").text = "   "
    compare(H.find(d, "newMilestoneOk").enabled, false)
    H.find(d, "newMilestoneTitle").text = "Ship the panel"
    compare(H.find(d, "newMilestoneOk").enabled, true)
    compare(titles.signalArguments[titles.count - 1][0], "Ship the panel")
    H.find(d, "newMilestoneDescription").text = "Everything the board writes."
    compare(descriptions.signalArguments[descriptions.count - 1][0], "Everything the board writes.")
    click(H.find(d, "newMilestoneOk"))
    compare(submits.count, 1)
  }

  function test_enter_in_the_title_submits_only_when_it_is_valid() {
    var d = make("manual")
    var title = H.find(d, "newMilestoneTitle")
    title.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(submits.count, 0)
    title.text = "Ship the panel"
    title.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(submits.count, 1)
  }

  function test_the_ok_label_follows_the_mode() {
    var d = make("manual")
    compare(H.find(d, "newMilestoneOk").text, "Create")
    d.mode = "spec"
    compare(H.find(d, "newMilestoneOk").text, "Start")
  }

  // ---- spec mode --------------------------------------------------------

  function test_ok_needs_a_selected_spec_in_spec_mode() {
    var d = make("spec")
    compare(H.find(d, "newMilestoneOk").enabled, false)
    d.selectedSpec = "docs/specs/new-milestone.md"
    compare(H.find(d, "newMilestoneOk").enabled, true)
    click(H.find(d, "newMilestoneOk"))
    compare(submits.count, 1)
  }

  function test_ok_stays_disabled_while_the_agent_cannot_run() {
    var d = make("spec")
    d.selectedSpec = "docs/specs/new-milestone.md"
    d.agentMessage = "No default agent is set."
    compare(H.find(d, "newMilestoneOk").enabled, false)
    click(H.find(d, "newMilestoneOk"))
    compare(submits.count, 0)
  }

  function test_the_spec_rows_show_the_title_the_path_and_the_category_badge() {
    var d = make("spec")
    compare(H.find(d, "specRowTitle0").text, "New milestone")
    compare(H.find(d, "specRowPath0").text, "docs/specs/new-milestone.md")
    compare(H.find(d, "specRowPath0").elide, Text.ElideMiddle)
    compare(H.find(d, "specRowBadge0").text, "Specs")
    verify(H.find(d, "specRow2"), "the third row")
    verify(!H.find(d, "specRow3"), "no fourth row")
  }

  function test_clicking_a_row_reports_the_path_and_the_selected_row_is_marked() {
    var d = make("spec")
    compare(H.find(d, "specRow1").hasCursor, false)
    click(H.find(d, "specRow1"))
    compare(specs.count, 1)
    compare(specs.signalArguments[0][0], "docs/architecture.md")
    d.selectedSpec = "docs/architecture.md"
    compare(H.find(d, "specRow1").hasCursor, true)
    compare(H.find(d, "specRow0").hasCursor, false)
  }

  function test_the_search_field_narrows_the_list_by_title_and_by_path() {
    var d = make("spec")
    H.find(d, "newMilestoneSearch").text = "architecture"
    compare(H.find(d, "specRowTitle0").text, "Architecture")
    verify(!H.find(d, "specRow1"), "only the match is listed")
    H.find(d, "newMilestoneSearch").text = "docs/specs"
    compare(H.find(d, "specRowTitle0").text, "New milestone")
  }

  function test_the_list_words_its_empty_states() {
    var d = make("spec")
    var status = H.find(d, "specsMessage")
    compare(status.visible, false)
    H.find(d, "newMilestoneSearch").text = "zzz"
    compare(status.text, "No documents match “zzz”.")
    H.find(d, "newMilestoneSearch").text = ""
    d.specs = []
    compare(status.text, "No documents found in this project.")
  }

  function test_the_agent_line_names_the_agent_and_its_note() {
    var d = make("spec")
    d.agentName = "claude"
    d.agentNote = "runs with full auto-approval"
    var agent = H.find(d, "newMilestoneAgent")
    compare(agent.visible, true)
    compare(agent.text, "Agent: claude")
    compare(H.find(d, "newMilestoneAgentNote").text, "runs with full auto-approval")
    compare(H.find(d, "newMilestoneAgentMessage").visible, false)
  }

  function test_the_agent_message_replaces_the_agent_line_in_the_urgent_colour() {
    var d = make("spec")
    d.agentName = "gemini"
    d.agentMessage = "gemini has no supported unattended mode."
    var message = H.find(d, "newMilestoneAgentMessage")
    compare(message.visible, true)
    compare(message.text, "gemini has no supported unattended mode.")
    compare(message.color, d.theme.urgent)
    compare(H.find(d, "newMilestoneAgent").visible, false)
  }

  // ---- errors, cancelling, busy ----------------------------------------

  function test_the_error_line_shows_only_when_there_is_one() {
    var d = make("manual")
    compare(H.find(d, "newMilestoneError").visible, false)
    d.error = "brd add failed."
    compare(H.find(d, "newMilestoneError").visible, true)
    compare(H.find(d, "newMilestoneError").text, "brd add failed.")
    compare(H.find(d, "newMilestoneError").color, d.theme.urgent)
  }

  function test_cancel_the_backdrop_and_escape_all_cancel_but_the_card_does_not() {
    var d = make("manual")
    click(H.find(d, "newMilestoneCancel"))
    compare(cancels.count, 1)
    mouseClick(H.find(d, "newMilestoneBackdrop"), 2, 2)
    compare(cancels.count, 2)
    mouseClick(H.find(d, "newMilestoneCard"), 3, 3)
    compare(cancels.count, 2)
    H.find(d, "newMilestoneTitle").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 3)
  }

  function test_escape_in_the_spec_search_cancels_too() {
    var d = make("spec")
    H.find(d, "newMilestoneSearch").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
  }

  function test_busy_disables_everything_and_stops_every_way_out() {
    var d = make("manual")
    H.find(d, "newMilestoneTitle").text = "Ship the panel"
    d.busy = true
    compare(H.find(d, "newMilestoneOk").enabled, false)
    compare(H.find(d, "newMilestoneCancel").enabled, false)
    compare(H.find(d, "newMilestoneTitle").enabled, false)
    compare(H.find(d, "newMilestoneDescription").enabled, false)
    mouseClick(H.find(d, "newMilestoneBackdrop"), 2, 2)
    compare(cancels.count, 0)
    // The ways a key press reaches the dialog: both are refused while busy.
    d.cancel()
    compare(cancels.count, 0)
    d.submit()
    compare(submits.count, 0)
    click(H.find(d, "newMilestoneOk"))
    compare(submits.count, 0)
    click(H.find(d, "newMilestoneCancel"))
    compare(cancels.count, 0)
  }

  function test_busy_also_freezes_the_mode_switch_and_the_spec_list() {
    var d = make("spec")
    d.busy = true
    click(H.find(d, "milestoneModemanual"))
    compare(modes.count, 0)
    compare(H.find(d, "newMilestoneSearch").enabled, false)
  }

  // ---- what a mode switch and a reopen keep -----------------------------

  function test_switching_modes_keeps_the_typed_title_the_search_and_the_selection() {
    var d = make("manual")
    H.find(d, "newMilestoneTitle").text = "Ship the panel"
    H.find(d, "newMilestoneDescription").text = "Everything."
    d.mode = "spec"
    H.find(d, "newMilestoneSearch").text = "docs"
    d.selectedSpec = "docs/architecture.md"
    d.mode = "manual"
    compare(H.find(d, "newMilestoneTitle").text, "Ship the panel")
    compare(H.find(d, "newMilestoneDescription").text, "Everything.")
    d.mode = "spec"
    compare(H.find(d, "newMilestoneSearch").text, "docs")
    compare(d.selectedSpec, "docs/architecture.md")
  }

  function test_reopening_clears_the_search_and_the_fields() {
    var d = make("spec")
    H.find(d, "newMilestoneSearch").text = "architecture"
    d.mode = "manual"
    H.find(d, "newMilestoneTitle").text = "Ship the panel"
    H.find(d, "newMilestoneDescription").text = "Everything."
    d.shown = false
    d.shown = true
    compare(H.find(d, "newMilestoneTitle").text, "")
    compare(H.find(d, "newMilestoneDescription").text, "")
    d.mode = "spec"
    compare(H.find(d, "newMilestoneSearch").text, "")
  }
}
