#!/bin/bash
# Installs the TwoTabs Notch hook for Claude Code:
#   1. copies twotabs-notch-hook.sh to <claude dir>/hooks/
#   2. backs up settings.json to settings.json.bak-twotabs-<timestamp> (only when something changes)
#   3. MERGES our hook entries into settings.json (idempotent, user hooks untouched)
# Re-running is safe. Undo with uninstall-claude-hooks.sh. Needs python3 (stdlib only).
#
# <claude dir> is $TWOTABS_CLAUDE_DIR, else $CLAUDE_CONFIG_DIR, else ~/.claude.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${TWOTABS_CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_DEST="$CLAUDE_DIR/hooks/twotabs-notch-hook.sh"
# Same form Claude Code users write by hand; the shell expands it when the hook runs.
HOOK_COMMAND='"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/twotabs-notch-hook.sh"'
# A test run with a custom dir must reference that dir, not ~/.claude.
if [ -n "${TWOTABS_CLAUDE_DIR:-}" ]; then HOOK_COMMAND="\"$HOOK_DEST\""; fi

command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }
[ -d "$CLAUDE_DIR" ] || { echo "Claude config dir not found: $CLAUDE_DIR" >&2; exit 1; }

mkdir -p "$CLAUDE_DIR/hooks"
install -m 755 "$HERE/twotabs-notch-hook.sh" "$HOOK_DEST"
echo "hook script: $HOOK_DEST"

python3 -I "$HERE/claude_hooks_merge.py" install "$SETTINGS" "$HOOK_COMMAND"
echo "Done. Start a new Claude Code session (or run /hooks to review). TwoTabs Notch must be running."
