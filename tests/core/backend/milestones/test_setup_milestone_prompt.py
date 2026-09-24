"""setup-milestone.md: the prompt handed to the agent (plain prompt, no orchestrator hooks)."""
import os

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..",
                    "core", "backend", "milestones", "setup-milestone.md")


def text():
    with open(PATH, encoding="utf-8") as f:
        return f.read()


def test_exists_and_has_no_frontmatter():
    t = text()
    assert t.strip()
    assert not t.startswith("---")


def test_keeps_the_brd_guidance():
    t = text()
    for needle in ("brd add", "--blocked-by", "brd block", "brd tree <milestone id>"):
        assert needle in t


def test_drops_orchestrator_and_brainstorming_hooks():
    t = text()
    for needle in ("superpowers:brainstorming", "Workflow({", "dryRun", "taskScript", "Dry run"):
        assert needle not in t
