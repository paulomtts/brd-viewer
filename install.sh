#!/usr/bin/env bash
# Installs the brd-viewer Omarchy plugin from this checkout, and optionally
# the `brd` CLI it reads from. The two are separate projects: the plugin
# works with whatever `brd` is on PATH, so installing brd is opt-in.
set -euo pipefail

PLUGIN_ID="paulomtts.brd-viewer"
BRD_SOURCE="${BRD_SOURCE:-git+https://github.com/paulomtts/brd.git}"

usage() {
  cat <<EOF
Usage: ./install.sh [--with-brd | --no-brd] [--dry-run]

Links this checkout into ~/.config/omarchy/plugins/, rescans, and enables the
plugin. Nothing is copied: updating the checkout updates the plugin.

  --with-brd   install the brd CLI first if it is not on PATH (needs uv or
               pipx, and access to $BRD_SOURCE)
  --no-brd     never install brd (the default when not run interactively)
  --dry-run    print what would happen without changing anything

Without --with-brd/--no-brd and with brd missing, you are asked.
EOF
}

with_brd=ask
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --with-brd) with_brd=yes ;;
    --no-brd) with_brd=no ;;
    --dry-run) dry_run=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

run() {
  if ((dry_run)); then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

if ! command -v omarchy >/dev/null 2>&1; then
  echo "The omarchy CLI was not found; brd-viewer is an Omarchy shell plugin." >&2
  exit 1
fi

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
plugins_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
dest="$plugins_dir/$PLUGIN_ID"

install_brd() {
  if command -v uv >/dev/null 2>&1; then
    run uv tool install "$BRD_SOURCE"
  elif command -v pipx >/dev/null 2>&1; then
    run pipx install "$BRD_SOURCE"
  else
    warn "neither uv nor pipx is installed; install brd yourself from $BRD_SOURCE"
    return 1
  fi
}

if command -v brd >/dev/null 2>&1; then
  say "brd found: $(command -v brd)"
else
  want="$with_brd"
  if [[ "$want" == ask ]]; then
    want=no
    if [[ -t 0 ]]; then
      read -r -p "brd is not installed. Install it now? [y/N] " answer || answer=""
      if [[ "$answer" =~ ^[Yy] ]]; then want=yes; fi
    fi
  fi
  if [[ "$want" == yes ]]; then
    say "installing brd from $BRD_SOURCE"
    if ! install_brd; then
      warn "brd was not installed (if the repository is private you need access to it)"
    fi
  else
    warn "brd is not installed; the plugin will report an error until it is"
  fi
fi

if [[ -e "$dest" || -L "$dest" ]]; then
  if [[ "$(cd "$dest" 2>/dev/null && pwd -P)" == "$src" ]]; then
    say "plugin already linked at $dest"
  else
    echo "$dest already exists and is not this checkout; leaving it alone." >&2
    exit 1
  fi
else
  say "linking $src -> $dest"
  run mkdir -p "$plugins_dir"
  run ln -s "$src" "$dest"
fi

run omarchy-shell shell rescanPlugins

if omarchy plugin list 2>/dev/null | grep -Eq "^${PLUGIN_ID}[[:space:]]+enabled"; then
  say "plugin already enabled"
else
  say "enabling $PLUGIN_ID"
  run omarchy plugin enable "$PLUGIN_ID"
fi

say "done. If the plugin was already loaded, run omarchy-restart-shell to pick up changes."
