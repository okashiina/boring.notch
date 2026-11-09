#!/bin/bash
# TwoTabs Notch hook: forwards Claude Code hook events (JSON on stdin) to the notch app over a Unix socket.
# Never blocks and never fails Claude Code: always exits 0, silently does nothing if the app is not running.
# Ported in spirit from Notchi's notchi-hook.sh (sk-ruban/notchi, GPL-3.0), but pure shell + nc, no Python.
#
# Socket (inside the sandboxed app's container):
#   ~/Library/Containers/com.okashiina.twotabsnotch/Data/tmp/twotabs-claude-pet.sock
# Override for tests with TWOTABS_PET_SOCKET.

trap 'exit 0' EXIT

SOCK="${TWOTABS_PET_SOCKET:-$HOME/Library/Containers/com.okashiina.twotabsnotch/Data/tmp/twotabs-claude-pet.sock}"

# App not running (no socket file): drain nothing, exit quietly.
[ -S "$SOCK" ] || exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# Headless `claude -p` runs must not animate the pet: look for -p / --print on this process or its parent.
# Only checked on SessionStart / UserPromptSubmit (the app keeps the flag per session).
HEADER=""
case "$INPUT" in
  *'"SessionStart"'*|*'"UserPromptSubmit"'*)
    INTERACTIVE=1
    for CHECK_PID in "$PPID" "$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')"; do
      [ -n "$CHECK_PID" ] || continue
      if ps -o args= -p "$CHECK_PID" 2>/dev/null | grep -qE '(^| )(-p|--print)( |$)'; then
        INTERACTIVE=0
        break
      fi
    done
    HEADER="#twotabs interactive=$INTERACTIVE"
    ;;
esac

# -w 1: give up after one second. The app closes the connection as soon as it has read the JSON.
{
  [ -n "$HEADER" ] && printf '%s\n' "$HEADER"
  printf '%s' "$INPUT"
} | nc -U -w 1 "$SOCK" >/dev/null 2>&1

exit 0
