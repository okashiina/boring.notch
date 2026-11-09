# Claude Code pet: attribution

The Claude Code pet in TwoTabs Notch is ported from **Notchi**, a macOS notch companion for Claude Code,
by sk-ruban: <https://github.com/sk-ruban/notchi>, licensed under the **GNU General Public License v3.0**.
TwoTabs Notch (a fork of Boring Notch) is GPL-3.0 as well, so the two are compatible; this notice keeps the credit.

## What comes from Notchi

- **Sprite art**: the files in `Sprites/` (`claude_idle_neutral.png`, `claude_working_neutral.png`,
  `claude_waiting_neutral.png`, `claude_compacting_neutral.png`, `claude_sleeping_neutral.png`,
  `claude_idle_happy.png`) are Notchi's own Aseprite sprite sheets, copied unchanged from its asset catalog
  (`claude_<task>_<emotion>.imageset/sprite_sheet.png`). Each sheet is a single row of square 64 px frames.
  The art remains the work of Notchi's author; GPL-3.0 applies to it here as it does upstream.
- **Ported logic** (reimplemented and trimmed to the Claude Code path, not copied verbatim):
  - the event to state mapping and sleep timer (Notchi's `NotchiStateMachine`, `SessionStore`, `SessionData`),
  - the hook-to-Unix-socket design and socket server structure (`notchi-hook.sh`, `SocketServer`),
  - the idea of detecting `claude -p` runs from the process tree so headless runs do not animate the pet,
  - the hook installer's merge/prune approach (`HookInstaller`), here in `scripts/twotabs/claude_hooks_merge.py`,
  - per-task animation rates (`NotchiTask.loopDuration`).

- **Island art**: `Sprites/claude_island_grass.png` is Notchi's `GrassIsland` texture
  (`GrassIsland.imageset/grass.png`), copied unchanged.
- **Ported ideas** (reimplemented): the grass island scene with a wandering pet per session and its per-state walk/bob
  parameters (`GrassIslandView`, `NotchiTask`), the activity feed rows (`ActivityRowView`, `UserPromptBubbleView`,
  `AssistantTextRowView`), the incremental transcript reader and "[Request interrupted by user" detection
  (`ConversationParser`), today's token/cost estimate and the per-family prices (`ClaudeCostScanner`,
  `claude-pricing-fallback.json`), the terminal jump (`TerminalJumpService`, here via the app bundle that hosts the
  terminal, found by the hook), notification sound on waiting (`SoundService`).

## What is not ported

Emotion/sentiment analysis, Codex and Devin support, the network usage quota (OAuth / keychain), water and ground
island themes, Notchi's own panel and window code, custom sounds and the updater.

## What is new here

Late-delivery guard for async hooks, silence fallbacks per last event, os.Logger diagnostics (category ClaudePet),
~/.claude access through one security-scoped bookmark, the Claude tab in the open notch, "Claude needs you" peek under the
closed notch. Pure `ClaudePetEngine` (no timers, testable), sandbox-safe socket inside the app container, a pure shell + `nc` hook
(no Python at run time), closed-notch and music-slot placement, open-notch session list, settings section.
