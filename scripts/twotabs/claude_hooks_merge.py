#!/usr/bin/env python3
"""Merge / remove the TwoTabs Notch hook entries in a Claude Code settings.json.

    claude_hooks_merge.py install   <settings.json> <hook command>
    claude_hooks_merge.py uninstall <settings.json>
    claude_hooks_merge.py status    <settings.json>

install is idempotent and never replaces anything: existing user hooks are preserved, and our entry is only
added to an event if no hook command containing MARKER is there yet (a changed command is updated in place).
uninstall removes only commands containing MARKER and prunes entries/events/"hooks" that become empty.
Standard library only. Backs the file up to <file>.bak-twotabs-<timestamp> before every change and writes atomically; refuses to touch a file that is not a JSON object.
"""
import json
import os
import sys
import shutil
import tempfile
import time

MARKER = "twotabs-notch-hook.sh"
TIMEOUT = 5  # seconds the hook may run at most; "async": true so Claude Code never waits for it at all

# (event, matchers). None = entry without matcher.
EVENTS = [
    ("SessionStart", [None]),
    ("UserPromptSubmit", [None]),
    ("PreToolUse", ["*"]),
    ("PostToolUse", ["*"]),
    ("PermissionRequest", ["*"]),
    ("Notification", [None]),
    ("Stop", [None]),
    ("SubagentStop", [None]),
    ("PreCompact", ["auto", "manual"]),
    ("PostCompact", ["auto", "manual"]),
    ("SessionEnd", [None]),
]


def _entry(matcher, command):
    entry = {"hooks": [{"type": "command", "command": command, "timeout": TIMEOUT, "async": True}]}
    if matcher is not None:
        entry = {"matcher": matcher, **entry}
    return entry


def _is_ours(hook):
    return isinstance(hook, dict) and MARKER in str(hook.get("command", ""))


def merge_install(settings, command):
    """Returns the settings dict with our hooks added. Mutates and returns `settings`."""
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
    for event, matchers in EVENTS:
        entries = hooks.get(event)
        if not isinstance(entries, list):
            entries = []
        found = False
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            for hook in entry.get("hooks", []) if isinstance(entry.get("hooks"), list) else []:
                if _is_ours(hook):
                    found = True
                    if hook.get("command") != command:
                        hook["command"] = command
        if not found:
            entries.extend(_entry(m, command) for m in matchers)
        hooks[event] = entries
    settings["hooks"] = hooks
    return settings


def merge_uninstall(settings):
    """Returns the settings dict without our hooks. Mutates and returns `settings`."""
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return settings
    for event in list(hooks):
        entries = hooks[event]
        if not isinstance(entries, list):
            continue
        kept = []
        for entry in entries:
            inner = entry.get("hooks") if isinstance(entry, dict) else None
            if not isinstance(inner, list):
                kept.append(entry)
                continue
            remaining = [h for h in inner if not _is_ours(h)]
            if len(remaining) == len(inner):
                kept.append(entry)  # nothing of ours in it
            elif remaining:
                entry["hooks"] = remaining
                kept.append(entry)
            # else: the entry only held our hook, drop it
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if not hooks:
        del settings["hooks"]
    return settings


def is_installed(settings):
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return False
    return any(
        _is_ours(h)
        for entries in hooks.values() if isinstance(entries, list)
        for entry in entries if isinstance(entry, dict) and isinstance(entry.get("hooks"), list)
        for h in entry["hooks"]
    )


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    if not raw.strip():
        return {}
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("settings file is not a JSON object")
    return data


def save(path, data):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".settings-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        if os.path.exists(path):
            os.chmod(tmp, os.stat(path).st_mode & 0o777)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def main(argv):
    if len(argv) < 3 or argv[1] not in ("install", "uninstall", "status"):
        sys.stderr.write(__doc__)
        return 2
    action, path = argv[1], argv[2]
    try:
        settings = load(path)
    except (ValueError, OSError) as e:
        sys.stderr.write("cannot read %s: %s\n" % (path, e))
        return 1
    if action == "status":
        print("installed" if is_installed(settings) else "not installed")
        return 0
    if action == "install":
        if len(argv) < 4:
            sys.stderr.write("install needs the hook command\n")
            return 2
        before = json.dumps(settings, sort_keys=True)
        merge_install(settings, argv[3])
        changed = json.dumps(settings, sort_keys=True) != before
    else:
        before = json.dumps(settings, sort_keys=True)
        merge_uninstall(settings)
        changed = json.dumps(settings, sort_keys=True) != before
    if changed:
        if os.path.exists(path):
            backup = "%s.bak-twotabs-%s" % (path, time.strftime("%Y%m%d-%H%M%S"))
            n = 1
            while os.path.exists(backup):  # never overwrite an earlier backup
                n += 1
                backup = "%s.bak-twotabs-%s-%d" % (path, time.strftime("%Y%m%d-%H%M%S"), n)
            shutil.copy2(path, backup)
            print("backup: %s" % backup)
        save(path, settings)
        print("%s: settings updated" % action)
    else:
        print("%s: nothing to change" % action)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
