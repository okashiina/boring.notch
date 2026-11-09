#!/bin/bash
# Removes only the TwoTabs Notch hook entries from Claude Code's settings.json and deletes the hook script.
# Other hooks and settings are left alone. settings.json is backed up first (only when something changes).
#
# <claude dir> is $TWOTABS_CLAUDE_DIR, else $CLAUDE_CONFIG_DIR, else ~/.claude.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${TWOTABS_CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_DEST="$CLAUDE_DIR/hooks/twotabs-notch-hook.sh"

command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }

python3 -I "$HERE/claude_hooks_merge.py" uninstall "$SETTINGS"
rm -f "$HOOK_DEST"
echo "removed: $HOOK_DEST"
