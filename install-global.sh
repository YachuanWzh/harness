#!/usr/bin/env bash
# Global superharness installer (macOS / Linux). Counterpart of install-global.ps1.
# Copies bin/, lib/, template/ to a permanent location (~/.local/superharness/)
# and adds its bin/ to the user PATH. After this, "superharness" works from any
# directory and survives deletion of the source clone.
#
# Usage: bash install-global.sh
#
# Update:  re-run this script from an updated clone to refresh the global install.
# Remove:  delete ~/.local/superharness/ and remove its bin/ from your shell rc.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="$HOME/.local/superharness"

# ---------- verify source ----------

REQUIRED=(
    "$REPO_ROOT/bin/superharness"
    "$REPO_ROOT/lib/install.sh"
    "$REPO_ROOT/template/.claude-plugin/marketplace.json"
)
for f in "${REQUIRED[@]}"; do
    if [ ! -e "$f" ]; then
        echo "Missing required source file: $f" >&2
        exit 1
    fi
done

# ---------- copy to install root ----------

echo "Installing superharness to: $INSTALL_ROOT"

# remove previous install (if any) so stale files don't linger
if [ -d "$INSTALL_ROOT" ]; then
    rm -rf "$INSTALL_ROOT"
    echo "  Removed previous install."
fi

mkdir -p "$INSTALL_ROOT"
for d in bin lib template; do
    cp -R "$REPO_ROOT/$d" "$INSTALL_ROOT/$d"
    echo "  Copied $d/"
done

# ensure the CLI entry point is executable
chmod +x "$INSTALL_ROOT/bin/superharness"

# ---------- PATH ----------

BIN_DIR="$INSTALL_ROOT/bin"
CLONE_BIN="$REPO_ROOT/bin"

# pick the shell rc file to update
detect_rc() {
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash)
            if [ -f "$HOME/.bash_profile" ]; then echo "$HOME/.bash_profile"
            else echo "$HOME/.bashrc"; fi ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

RC_FILE="$(detect_rc)"
PATH_LINE="export PATH=\"$BIN_DIR:\$PATH\""
MARKER='# added by superharness install-global.sh'

touch "$RC_FILE"

# clean up any old path pointing at a different clone location
if grep -qF "$CLONE_BIN" "$RC_FILE"; then
    tmp="$RC_FILE.tmp.$$"
    grep -vF "$CLONE_BIN" "$RC_FILE" > "$tmp" || true
    mv "$tmp" "$RC_FILE"
    echo "  Removed old clone-based PATH entry from $RC_FILE."
fi

if grep -qF "$BIN_DIR" "$RC_FILE"; then
    echo "Already in $RC_FILE: $BIN_DIR"
else
    {
        printf '\n%s\n%s\n' "$MARKER" "$PATH_LINE"
    } >> "$RC_FILE"
    echo "Added to $RC_FILE: $BIN_DIR"
fi

# ---------- done ----------

echo ""
echo "Global install complete!"
echo ""
echo "Next steps:"
echo "  1. Open a NEW terminal (or run: source $RC_FILE)."
echo "  2. cd into any project and run:  superharness"
echo "  3. Then start Claude Code in that project:  claude"
echo ""
echo "Update:  re-run this script from an updated clone to refresh."
echo "Remove:  delete $INSTALL_ROOT and remove $BIN_DIR from $RC_FILE."
