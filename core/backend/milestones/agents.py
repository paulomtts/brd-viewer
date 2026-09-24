"""Unattended (headless) invocations of the coding agents installed on this machine.

One adapter per agent. `build(prompt)` returns an **argv array** — nothing is ever
passed through a shell, so a spec's text cannot become a command. In every adapter
the prompt is the LAST argv element (either the command's positional prompt or the
value of its prompt option); no adapter needs stdin, so the runner can close it.

`restricted` is True only when the agent can be limited to reading the project plus
running `brd` (a spec is untrusted text the agent follows). Everything else runs with
full auto-approval and says so in `note`, which the dialog shows next to the name.

Each adapter carries the exact `--help` lines that justify its argv in `help`. An agent
whose help does not document a non-interactive prompt mode is NOT in this table
(`openclaw` is not installed here, so it was never checked and stays out).

Flag ordering matters for `claude`: `--allowedTools <tools...>` is variadic, so it is
placed before the other options and the boolean `-p` comes last — otherwise the prompt
would be swallowed as another allowed tool.
"""


class Adapter:
    def __init__(self, prefix, restricted, note, help):
        self.prefix = list(prefix)
        self.restricted = restricted
        self.note = note
        self.help = help

    def build(self, prompt):
        """The full argv for one unattended run; the prompt is the last element."""
        return [*self.prefix, prompt]


FULL = "runs with full auto-approval"
RESTRICTED = "restricted to reading the project and running brd"

ADAPTERS = {
    # claude 2.1.280 — `claude --help`:
    #   "Usage: claude [options] [command] [prompt]"
    #   "-p, --print   Print response and exit (useful for pipes)."
    #   "--permission-mode <mode>  ... (choices: "acceptEdits", "auto",
    #    "bypassPermissions", "manual", "dontAsk", "plan")"
    #   "--allowedTools, --allowed-tools <tools...>  Comma or space-separated list of
    #    tool names to allow (e.g. "Bash(git *) Edit")"
    #   "--no-session-persistence  Disable session persistence ... (only works with --print)"
    "claude": Adapter(
        ["claude", "--allowedTools", "Read Glob Grep Bash(brd *)",
         "--permission-mode", "dontAsk", "--no-session-persistence", "-p"],
        True, RESTRICTED,
        "claude --help: -p/--print; --permission-mode dontAsk; "
        "--allowedTools <tools...>; --no-session-persistence",
    ),
    # codex 0.154.0 — `codex exec --help`:
    #   "Run Codex non-interactively"  /  "Usage: codex exec [OPTIONS] [PROMPT]"
    #   "[PROMPT]  Initial instructions for the agent."
    #   "--dangerously-bypass-approvals-and-sandbox  Skip all confirmation prompts and
    #    execute commands without sandboxing."
    #   "--skip-git-repo-check  Allow running Codex outside a Git repository"
    # (the sandboxed modes cannot write brd's database outside the workspace, and
    # `codex exec` has no tool allow-list, so the run is unrestricted.)
    "codex": Adapter(
        ["codex", "exec", "--dangerously-bypass-approvals-and-sandbox",
         "--skip-git-repo-check"],
        False, FULL,
        "codex exec --help: 'Run Codex non-interactively', 'Usage: codex exec [OPTIONS] "
        "[PROMPT]', --dangerously-bypass-approvals-and-sandbox, --skip-git-repo-check",
    ),
    # crush 0.96.1 — `crush run --help`:
    #   "Run a single prompt in non-interactive mode and exit."
    #   "USAGE  crush run [prompt...] [--flags]"
    #   "-q --quiet  Hide spinner"
    # (--yolo is a root-only flag: `crush run --yolo` fails with "Unknown flag: --yolo",
    # and `crush run` offers no allow-list, so the run is unrestricted.)
    "crush": Adapter(
        ["crush", "run", "--quiet"],
        False, FULL,
        "crush run --help: 'Run a single prompt in non-interactive mode and exit.', "
        "'crush run [prompt...]', -q/--quiet",
    ),
    # copilot 1.0.88 — `copilot --help`:
    #   "-p, --prompt <text>  Execute a prompt in non-interactive mode (exits after completion)"
    #   "--allow-all-tools  Allow all tools to run automatically without confirmation;
    #    required for non-interactive mode."
    #   "--no-ask-user  Disable the ask_user tool (agent works autonomously ...)"
    #   "--no-color  Disable all color output"
    "copilot": Adapter(
        ["copilot", "--allow-all-tools", "--no-ask-user", "--no-color", "-p"],
        False, FULL,
        "copilot --help: -p/--prompt <text> (non-interactive), --allow-all-tools "
        "('required for non-interactive mode'), --no-ask-user, --no-color",
    ),
    # pi 0.87.1 — `pi --help`:
    #   "Usage: pi [options] [--] [@files...] [messages...]"
    #   "--print, -p  Non-interactive mode: process prompt and exit"
    #   "--tools, -t <tools>  Comma-separated allowlist of tool names to enable"
    #   "--  End option parsing; treat remaining arguments as messages/files"
    # (the allow-list can drop write/edit but `bash` cannot be narrowed to brd, so the
    # run is not "restricted" in this table's sense.)
    "pi": Adapter(
        ["pi", "-p", "--tools", "read,grep,find,ls,bash", "--"],
        False, FULL,
        "pi --help: --print/-p (non-interactive), --tools/-t <tools> allowlist, "
        "'--  End option parsing; treat remaining arguments as messages/files'",
    ),
    # hermes — `hermes chat --help`:
    #   "-q, --query QUERY  Single query (non-interactive mode)"
    #   "-Q, --quiet  Quiet mode for programmatic use ..."
    #   "--yolo  Bypass all dangerous command approval prompts"
    "hermes": Adapter(
        ["hermes", "chat", "--yolo", "-Q", "-q"],
        False, FULL,
        "hermes chat --help: -q/--query QUERY 'Single query (non-interactive mode)', "
        "-Q/--quiet, --yolo",
    ),
    # gemini 0.61.0 — `gemini --help`:
    #   "-p, --prompt  Run in non-interactive (headless) mode with the given prompt."
    #   "--approval-mode  Set the approval mode: ... yolo (auto-approve all tools)"
    "gemini": Adapter(
        ["gemini", "--approval-mode", "yolo", "-p"],
        False, FULL,
        "gemini --help: -p/--prompt 'Run in non-interactive (headless) mode with the "
        "given prompt', --approval-mode yolo",
    ),
    # opencode 1.18.32 — `opencode run --help`:
    #   "opencode run [message..]  run opencode with a message"
    #   "--auto  auto-approve permissions that are not explicitly denied (dangerous!)"
    "opencode": Adapter(
        ["opencode", "run", "--auto"],
        False, FULL,
        "opencode run --help: 'opencode run [message..]', --auto auto-approve permissions",
    ),
    # cursor-agent — `cursor-agent --help`:
    #   "Usage: agent [options] [command] [prompt...]"  /  "prompt  Initial prompt for the agent"
    #   "-p, --print  Print responses to console (for scripts or non-interactive use)."
    #   "-f, --force  Force allow commands unless explicitly denied"
    #   "--output-format <format>  Output format (only works with --print): text | json | stream-json"
    "cursor-agent": Adapter(
        ["cursor-agent", "--print", "--force", "--output-format", "text"],
        False, FULL,
        "cursor-agent --help: 'agent [options] [command] [prompt...]', -p/--print "
        "'(for scripts or non-interactive use)', -f/--force, --output-format text",
    ),
    # grok 1.0.41 — `grok --help`:
    #   "-p, --single <PROMPT>  Single-turn prompt. Prints the response to stdout and exits"
    #   "--permission-mode <MODE>  [possible values: default, acceptEdits, auto, dontAsk,
    #    bypassPermissions, plan]"
    #   "--output-format <OUTPUT_FORMAT>  Output format for headless mode ... plain"
    # (--allow <RULE> exists but its rule syntax is not documented in --help, so no
    # allow-list is asserted here and the run counts as unrestricted.)
    "grok": Adapter(
        ["grok", "--permission-mode", "dontAsk", "--output-format", "plain", "-p"],
        False, FULL,
        "grok --help: -p/--single <PROMPT> 'Single-turn prompt ... and exits', "
        "--permission-mode dontAsk, --output-format plain",
    ),
    # omp (oh-my-pi 18.3.0) — `omp --help`:
    #   "-p, --print  Non-interactive mode: process prompt and exit"
    #   "--auto-approve  Auto-approve all tool calls (skip approval prompts)"
    #   example: "# Non-interactive mode (process and exit)  omp -p "List all .ts files in src/""
    "omp": Adapter(
        ["omp", "-p", "--auto-approve"],
        False, FULL,
        "omp --help: -p/--print 'Non-interactive mode: process prompt and exit', "
        "--auto-approve, example 'omp -p \"List all .ts files in src/\"'",
    ),
    # muse — `muse exec --help`:
    #   "muse exec — run one prompt non-interactively (headless)"
    #   "Usage: muse exec [OPTIONS] [PROMPT]"
    #   "--yolo  Disable approval and sandbox and trust this workspace (this run)"
    #   "--user-input-auto-resolve  Offer request_user_input and auto-cancel prompts (headless)"
    "muse": Adapter(
        ["muse", "exec", "--yolo", "--user-input-auto-resolve"],
        False, FULL,
        "muse exec --help: 'run one prompt non-interactively (headless)', "
        "'muse exec [OPTIONS] [PROMPT]', --yolo, --user-input-auto-resolve",
    ),
}


def supported(name):
    return bool(name) and name in ADAPTERS


def describe(name):
    a = ADAPTERS.get(name) if name else None
    if a is None:
        return {"supported": False, "restricted": False, "note": ""}
    return {"supported": True, "restricted": a.restricted, "note": a.note}
