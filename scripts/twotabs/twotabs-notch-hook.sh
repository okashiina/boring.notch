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
# The same walk finds the app bundle hosting the terminal (Terminal.app, iTerm, Ghostty, Claude.app, VS Code, ...)
# so the notch can bring it to the front: sent as a second header line "#twotabs-host <path to .app>".
HEADER=""
HOSTLINE=""
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
    CUR="$PPID"
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
      [ -n "$CUR" ] && [ "$CUR" -gt 1 ] 2>/dev/null || break
      LINE=$(ps -o ppid=,comm= -p "$CUR" 2>/dev/null) || break
      [ -n "$LINE" ] || break
      LINE="${LINE#"${LINE%%[![:space:]]*}"}"
      NEXT="${LINE%%[[:space:]]*}"
      COMM="${LINE#"$NEXT"}"; COMM="${COMM#"${COMM%%[![:space:]]*}"}"
      case "$COMM" in
        */claude-code/*) ;; # the Claude Code binary itself ships as claude.app: not a host, keep walking up
        *.app/*) HOSTLINE="#twotabs-host ${COMM%%.app/*}.app"; break ;;
      esac
      CUR="$NEXT"
    done
    ;;
esac

# -w 1: give up after one second. The app closes the connection as soon as it has read the JSON.
{
  [ -n "$HEADER" ] && printf '%s\n' "$HEADER"
  [ -n "$HOSTLINE" ] && printf '%s\n' "$HOSTLINE"
  printf '%s' "$INPUT"
} | nc -U -w 1 "$SOCK" >/dev/null 2>&1

exit 0
