//
//  ClaudePetEngine.swift
//  TwoTabs Notch - Claude Code pet
//
//  Pure per-session state machine (no UI, no timers: the caller passes `now`).
//  Event to state mapping follows Notchi's NotchiStateMachine / SessionStore (sk-ruban/notchi, GPL-3.0),
//  trimmed to the Claude Code path. See NOTICE.md.
//

import Foundation

enum ClaudePetTask: String, CaseIterable {
    case idle
    case working
    case waiting
    case compacting
    case done
    case sleeping

    /// Higher wins when several sessions compete for the one pet: waiting > working > compacting > done > idle > sleeping.
    var urgency: Int {
        switch self {
        case .waiting: return 6
        case .working: return 5
        case .compacting: return 4
        case .done: return 3
        case .idle: return 2
        case .sleeping: return 1
        }
    }

    /// States that deserve attention while music is playing (pet takes the visualizer slot only then).
    var isAttention: Bool {
        switch self {
        case .waiting, .working, .compacting, .done: return true
        case .idle, .sleeping: return false
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waiting: return "Needs you"
        case .compacting: return "Compacting"
        case .done: return "Done"
        case .sleeping: return "Asleep"
        }
    }
}

struct ClaudePetSession: Identifiable, Equatable {
    let id: String
    var cwd: String?
    var task: ClaudePetTask = .idle
    /// True between a prompt and its Stop. Decides what a SessionStart(compact) or idle notification means.
    var isProcessing = false
    var lastTool: String?
    var lastActivity: Date
    var taskSince: Date
    var interactive = true

    var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "Session" }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}

struct ClaudePetTuning {
    /// How long the happy "done" reaction plays after Stop.
    var doneDuration: TimeInterval = 3
    /// Idle for this long becomes sleeping (Notchi uses 300 s too).
    var sleepDelay: TimeInterval = 300
    /// A manual /compact has no end event: give up on "compacting" after this.
    var compactTimeout: TimeInterval = 180
    /// Esc / crashes send no Stop: working with no events for this long falls back to idle.
    var workingStaleAfter: TimeInterval = 20 * 60
    /// A permission prompt nobody answered for this long falls back to idle.
    var waitingStaleAfter: TimeInterval = 60 * 60
    /// A session that never sent SessionEnd and has been silent this long is forgotten.
    var forgetAfter: TimeInterval = 6 * 60 * 60
}

struct ClaudePetEngine {
    private(set) var sessions: [String: ClaudePetSession] = [:]
    var tuning = ClaudePetTuning()

    /// Commands Claude Code handles locally (no model turn, so no Stop follows).
    static let localSlashCommands: Set<String> = [
        "clear", "help", "status", "model", "cost", "config", "context", "usage", "doctor", "mcp", "hooks",
        "permissions", "memory", "resume", "exit", "quit", "login", "logout", "theme", "stats", "add-dir",
        "rewind", "output-style", "statusline", "ide", "agents", "vim", "terminal-setup", "release-notes",
    ]

    static func isLocalSlashCommand(_ prompt: String?) -> Bool {
        guard let prompt, prompt.hasPrefix("/") else { return false }
        let token = prompt.dropFirst().prefix { !$0.isWhitespace }
        return localSlashCommands.contains(String(token))
    }

    /// Returns true when anything visible changed.
    @discardableResult
    mutating func apply(_ event: ClaudePetEvent, now: Date) -> Bool {
        if event.kind == .sessionEnd {
            return sessions.removeValue(forKey: event.sessionId) != nil
        }

        let before = sessions[event.sessionId]
        var s = before ?? ClaudePetSession(id: event.sessionId, cwd: event.cwd, lastActivity: now, taskSince: now)
        if let cwd = event.cwd, !cwd.isEmpty { s.cwd = cwd }
        if let interactive = event.interactive { s.interactive = interactive }
        s.lastActivity = now

        switch event.kind {
        case .sessionStart:
            if event.source == "compact" {
                // Compaction finished: back to whatever the session was doing.
                setTask(&s, s.isProcessing ? .working : .idle, now: now)
            } else if before == nil {
                setTask(&s, .idle, now: now)
            }

        case .userPromptSubmit:
            if Self.isLocalSlashCommand(event.promptHead) {
                s.isProcessing = false
                setTask(&s, .idle, now: now)
            } else {
                s.isProcessing = true
                s.lastTool = nil
                setTask(&s, .working, now: now)
            }

        case .preToolUse:
            s.isProcessing = true
            s.lastTool = event.tool ?? s.lastTool
            // AskUserQuestion blocks on the user, like a permission prompt.
            setTask(&s, event.tool == "AskUserQuestion" ? .waiting : .working, now: now)

        case .postToolUse:
            s.isProcessing = true
            s.lastTool = event.tool ?? s.lastTool
            setTask(&s, .working, now: now)

        case .permissionRequest:
            s.isProcessing = true
            s.lastTool = event.tool ?? s.lastTool
            setTask(&s, .waiting, now: now)

        case .notification:
            switch event.notificationType {
            case "permission_prompt", "elicitation_dialog":
                setTask(&s, .waiting, now: now)
            case "idle_prompt":
                // Claude has been waiting for the next prompt; a pending permission prompt stays "waiting".
                if s.task != .waiting && s.task != .sleeping {
                    s.isProcessing = false
                    setTask(&s, .idle, now: now)
                }
            case nil:
                // Older Claude Code builds: only the message text is available.
                let text = (event.message ?? "").lowercased()
                if text.contains("permission") {
                    setTask(&s, .waiting, now: now)
                }
            default:
                break // auth_success and friends do not change the pet
            }

        case .preCompact:
            // isProcessing is left alone: auto-compact runs mid-turn (already true), manual /compact is not a turn.
            setTask(&s, .compacting, now: now)

        case .postCompact:
            setTask(&s, s.isProcessing ? .working : .idle, now: now)

        case .stop:
            s.isProcessing = false
            setTask(&s, .done, now: now)

        case .subagentStop:
            break // the main agent is still going; only the activity time moves

        case .sessionEnd:
            break // handled above
        }

        sessions[event.sessionId] = s
        return s != before
    }

    /// Time-based transitions. Returns true when anything visible changed.
    @discardableResult
    mutating func tick(now: Date) -> Bool {
        var changed = false
        for (id, var s) in sessions {
            let original = s
            let inTask = now.timeIntervalSince(s.taskSince)
            let silent = now.timeIntervalSince(s.lastActivity)

            if silent >= tuning.forgetAfter {
                sessions.removeValue(forKey: id)
                changed = true
                continue
            }

            switch s.task {
            case .done where inTask >= tuning.doneDuration:
                setTask(&s, .idle, now: now)
            case .compacting where inTask >= tuning.compactTimeout:
                s.isProcessing = false
                setTask(&s, .idle, now: now)
            case .working where silent >= tuning.workingStaleAfter:
                s.isProcessing = false
                setTask(&s, .idle, now: now)
            case .waiting where silent >= tuning.waitingStaleAfter:
                s.isProcessing = false
                setTask(&s, .idle, now: now)
            case .idle where silent >= tuning.sleepDelay:
                setTask(&s, .sleeping, now: now)
            default:
                break
            }

            if s != original {
                sessions[id] = s
                changed = true
            }
        }
        return changed
    }

    // MARK: Queries

    /// Interactive sessions, most urgent first (then most recently active).
    var visibleSessions: [ClaudePetSession] {
        sessions.values
            .filter { $0.interactive }
            .sorted {
                $0.task.urgency != $1.task.urgency ? $0.task.urgency > $1.task.urgency : $0.lastActivity > $1.lastActivity
            }
    }

    private func setTask(_ s: inout ClaudePetSession, _ task: ClaudePetTask, now: Date) {
        guard s.task != task else { return }
        s.task = task
        s.taskSince = now
    }
}
