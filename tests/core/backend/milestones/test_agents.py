"""agents.py: the adapter table (argv per agent, all verified against that agent's --help)."""
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "..", "..", "core", "backend"))
from milestones import agents  # noqa: E402

PROMPT = "# prompt\n\n## This run\nread docs/spec.md; a ; b $(x) 'q'\n"

# The exact argv each adapter must produce (prompt appended last).
EXPECTED = {
    "claude": ["claude", "--allowedTools", "Read Glob Grep Bash(brd *)",
               "--permission-mode", "dontAsk", "--no-session-persistence", "-p"],
    "codex": ["codex", "exec", "--dangerously-bypass-approvals-and-sandbox",
              "--skip-git-repo-check"],
    "crush": ["crush", "run", "--quiet"],
    "copilot": ["copilot", "--allow-all-tools", "--no-ask-user", "--no-color", "-p"],
    "pi": ["pi", "-p", "--tools", "read,grep,find,ls,bash", "--"],
    "hermes": ["hermes", "chat", "--yolo", "-Q", "-q"],
    "gemini": ["gemini", "--approval-mode", "yolo", "-p"],
    "opencode": ["opencode", "run", "--auto"],
    "cursor-agent": ["cursor-agent", "--print", "--force", "--output-format", "text"],
    "grok": ["grok", "--permission-mode", "dontAsk", "--output-format", "plain", "-p"],
    "omp": ["omp", "-p", "--auto-approve"],
    "muse": ["muse", "exec", "--yolo", "--user-input-auto-resolve"],
}


def test_the_table_holds_exactly_the_verified_agents():
    assert sorted(agents.ADAPTERS) == sorted(EXPECTED)


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_argv_is_exact_and_ends_with_the_prompt(name):
    assert agents.ADAPTERS[name].build(PROMPT) == EXPECTED[name] + [PROMPT]


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_argv_is_a_list_of_plain_strings(name):
    argv = agents.ADAPTERS[name].build(PROMPT)
    assert isinstance(argv, list)
    assert all(isinstance(a, str) for a in argv)
    assert argv[0] == name


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_every_adapter_documents_its_help_evidence_and_a_note(name):
    a = agents.ADAPTERS[name]
    assert a.help.strip()
    assert a.note.strip()


def test_only_claude_is_restricted_and_the_rest_say_so():
    for name, a in agents.ADAPTERS.items():
        if name == "claude":
            assert a.restricted is True
            assert "brd" in a.note
        else:
            assert a.restricted is False
            assert a.note == "runs with full auto-approval"


def test_supported():
    assert agents.supported("claude") is True
    assert agents.supported("openclaw") is False
    assert agents.supported("") is False


def test_describe_known_and_unknown():
    assert agents.describe("claude") == {"supported": True, "restricted": True,
                                         "note": agents.ADAPTERS["claude"].note}
    assert agents.describe("openclaw") == {"supported": False, "restricted": False, "note": ""}


def test_build_does_not_mutate_the_adapter():
    first = agents.ADAPTERS["claude"].build("a")
    second = agents.ADAPTERS["claude"].build("b")
    assert first[-1] == "a" and second[-1] == "b"
    assert len(first) == len(second)
