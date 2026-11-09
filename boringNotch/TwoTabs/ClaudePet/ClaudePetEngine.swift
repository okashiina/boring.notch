//
//  ClaudePetEngine.swift
//  TwoTabs Notch - Claude Code pet
//
//  Pure per-session state machine (no UI, no timers: the caller passes `now`).
//  Event to state mapping follows Notchi's NotchiStateMachine / SessionStore (sk-ruban/notchi, GPL-3.0),
//  trimmed to the Claude Code path. See NOTICE.md.
//

import Foundation
import os

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

/// One row of the live activity feed.
struct ClaudePetActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case prompt(String)
        case tool(name: String, detail: String?, finished: Bool)
        case assistant(String)
    }
    let id: Int
    var kind: Kind
    var date: Date

    var kindLabel: String {
        switch kind {
        case .prompt: return "prompt"
        case .tool(let name, _, _): return name
        case .assistant: return "assistant"
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
    /// Kind of the last event that counted (the stale-working fallback depends on it).
    var lastEventKind: ClaudePetEventKind?
    /// When the last Stop arrived. Cleared by the next UserPromptSubmit; guards against late tool events.
    var lastStopAt: Date?
    /// True once a PreToolUse (or permission request) was accepted after the last Stop, i.e. a PostToolUse is no straggler.
    var toolStartedSinceStop = false
    var transcriptPath: String?
    /// Bundle path of the app hosting the terminal (for "jump to terminal").
    var hostApp: String?
    /// First ~80 characters of the latest user prompt, and of the first one of the session.
    var lastPrompt: String?
    var firstPrompt: String?
    /// Newest last. Capped at `ClaudePetEngine.maxActivity`.
    var activity: [ClaudePetActivity] = []
    var nextActivityId = 0
    /// From the transcript, when ~/.claude access was granted.
    var title: String?
    var gitBranch: String?

    /// Session title if Claude Code gave one, else the first prompt, else the project.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let firstPrompt, !firstPrompt.isEmpty { return firstPrompt }
        return projectName
    }

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
    /// Esc / crashes send no Stop (Claude Code documents that Stop hooks do not run on a user interrupt), so a
    /// "working" session needs a silence fallback. How long depends on the last event, because what legitimately
    /// happens next differs:
    /// - after PostToolUse the model is thinking or streaming: the next event normally follows within seconds,
    ///   90 s of nothing means Claude is finished, interrupted or waiting for the user. A long single generation can
    ///   flip the pet to idle early, the next tool event flips it straight back.
    var workingStaleAfterPostTool: TimeInterval = 90
    /// - after PreToolUse a tool is running (builds, tests, sub-agents can take minutes): be patient. An interrupt
    ///   during a tool leaves this as the last event, so it still must not stay forever.
    var workingStaleAfterPreTool: TimeInterval = 5 * 60
    /// - after a prompt (or anything else) the model may think for a while before the first tool.
    var workingStaleAfterOther: TimeInterval = 3 * 60
    /// A PreToolUse within this long after a Stop is a late async delivery (all hooks run `async`, so delivery order
    /// is not guaranteed): ignored.
    var lateToolWindow: TimeInterval = 3
    /// A PostToolUse after a Stop with no PreToolUse accepted since is a straggler for this long.
    var latePostToolWindow: TimeInterval = 15
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

    static let maxActivity = 40

    private static func appendActivity(_ s: inout ClaudePetSession, _ kind: ClaudePetActivity.Kind, _ date: Date) {
        s.activity.append(ClaudePetActivity(id: s.nextActivityId, kind: kind, date: date))
        s.nextActivityId += 1
        if s.activity.count > maxActivity { s.activity.removeFirst(s.activity.count - maxActivity) }
    }

    /// Assistant text found in the transcript. `date` is the transcript timestamp, so the row lands in order.
    mutating func addAssistantText(sessionId: String, text: String, date: Date) {
        guard var s = sessions[sessionId] else { return }
        Self.appendActivity(&s, .assistant(text), date)
        s.activity.sort { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }
        sessions[sessionId] = s
    }

    /// Transcript facts: title, git branch, and "the user pressed Esc" (Claude Code sends no Stop for that).
    @discardableResult
    mutating func applyTranscript(sessionId: String, title: String?, gitBranch: String?, interrupted: Bool, now: Date) -> Bool {
        guard var s = sessions[sessionId] else { return false }
        let before = s
        if let title, !title.isEmpty { s.title = title }
        if let gitBranch, !gitBranch.isEmpty { s.gitBranch = gitBranch }
        if interrupted, s.task == .working || s.task == .waiting || s.task == .compacting {
            s.isProcessing = false
            setTask(&s, .idle, now: now, why: "interrupted (transcript)")
        }
        if s != before { sessions[sessionId] = s }
        return s != before
    }

    /// Returns true when anything visible changed.
    @discardableResult
    mutating func apply(_ event: ClaudePetEvent, now: Date) -> Bool {
        let log = ClaudePetLog.logger
        let sid = ClaudePetLog.short(event.sessionId)
        if event.kind == .sessionEnd {
            let removed = sessions.removeValue(forKey: event.sessionId) != nil
            log.info("event SessionEnd session=\(sid, privacy: .public) removed=\(removed, privacy: .public)")
            return removed
        }

        let before = sessions[event.sessionId]
        var s = before ?? ClaudePetSession(id: event.sessionId, cwd: event.cwd, lastActivity: now, taskSince: now)

        // Late-delivery guard: hooks are async, so a PreToolUse/PostToolUse that belongs to the turn that just
        // ended can arrive after its Stop. Ignoring it keeps "done" from flipping back to "working" with nothing
        // left to end it. A UserPromptSubmit clears lastStopAt, so a real new turn is never blocked.
        if let stopAt = s.lastStopAt {
            let age = now.timeIntervalSince(stopAt)
            let late: Bool
            switch event.kind {
            case .preToolUse: late = age < tuning.lateToolWindow
            case .postToolUse: late = !s.toolStartedSinceStop && age < tuning.latePostToolWindow
            default: late = false
            }
            if late {
                log.info("event \(event.kind.rawValue, privacy: .public) session=\(sid, privacy: .public) tool=\(event.tool ?? "-", privacy: .public) IGNORED late \(String(format: "%.1f", age), privacy: .public)s after Stop")
                return false
            }
        }

        let tool = event.tool ?? "-"
        log.info("event \(event.kind.rawValue, privacy: .public) session=\(sid, privacy: .public) tool=\(tool, privacy: .public) notif=\(event.notificationType ?? "-", privacy: .public) state=\(s.task.rawValue, privacy: .public)")

        if let cwd = event.cwd, !cwd.isEmpty { s.cwd = cwd }
        if let interactive = event.interactive { s.interactive = interactive }
        if let path = event.transcriptPath, !path.isEmpty { s.transcriptPath = path }
        if let host = event.hostApp { s.hostApp = host }
        s.lastActivity = now
        let why = event.kind.rawValue

        switch event.kind {
        case .sessionStart:
            s.lastEventKind = .sessionStart
            if event.source == "compact" {
                // Compaction finished: back to whatever the session was doing.
                setTask(&s, s.isProcessing ? .working : .idle, now: now, why: why)
            } else if before == nil {
                setTask(&s, .idle, now: now, why: why)
            }

        case .userPromptSubmit:
            s.lastEventKind = .userPromptSubmit
            s.lastStopAt = nil
            s.toolStartedSinceStop = false
            if let head = event.promptHead, !head.isEmpty {
                s.lastPrompt = head
                if s.firstPrompt == nil { s.firstPrompt = head }
                Self.appendActivity(&s, .prompt(head), now)
            }
            if Self.isLocalSlashCommand(event.promptHead) {
                s.isProcessing = false
                setTask(&s, .idle, now: now, why: why + " (local slash command)")
            } else {
                s.isProcessing = true
                s.lastTool = nil
                setTask(&s, .working, now: now, why: why)
            }

        case .preToolUse:
            s.lastEventKind = .preToolUse
            s.isProcessing = true
            s.toolStartedSinceStop = true
            s.lastTool = event.tool ?? s.lastTool
            if let tool = event.tool { Self.appendActivity(&s, .tool(name: tool, detail: event.toolSummary, finished: false), now) }
            // AskUserQuestion blocks on the user, like a permission prompt.
            setTask(&s, event.tool == "AskUserQuestion" ? .waiting : .working, now: now, why: why)

        case .postToolUse:
            s.lastEventKind = .postToolUse
            s.isProcessing = true
            s.lastTool = event.tool ?? s.lastTool
            if let tool = event.tool {
                if let i = s.activity.lastIndex(where: { if case .tool(let n, _, false) = $0.kind { return n == tool } else { return false } }),
                   case .tool(let n, let d, _) = s.activity[i].kind {
                    s.activity[i].kind = .tool(name: n, detail: d, finished: true)
                } else {
                    Self.appendActivity(&s, .tool(name: tool, detail: event.toolSummary, finished: true), now)
                }
            }
            setTask(&s, .working, now: now, why: why)

        case .permissionRequest:
            s.lastEventKind = .permissionRequest
            s.isProcessing = true
            s.toolStartedSinceStop = true
            s.lastTool = event.tool ?? s.lastTool
            setTask(&s, .waiting, now: now, why: why)

        case .notification:
            s.lastEventKind = .notification
            switch event.notificationType {
            case "permission_prompt", "elicitation_dialog":
                setTask(&s, .waiting, now: now, why: why + " " + (event.notificationType ?? ""))
            case "idle_prompt":
                // Claude has been waiting for the next prompt; a pending permission prompt stays "waiting".
                if s.task != .waiting && s.task != .sleeping {
                    s.isProcessing = false
                    setTask(&s, .idle, now: now, why: why + " idle_prompt")
                }
            case nil:
                // Older Claude Code builds: only the message text is available.
                let text = (event.message ?? "").lowercased()
                if text.contains("permission") {
                    setTask(&s, .waiting, now: now, why: why + " (message)")
                }
            default:
                break // auth_success and friends do not change the pet
            }

        case .preCompact:
            s.lastEventKind = .preCompact
            // isProcessing is left alone: auto-compact runs mid-turn (already true), manual /compact is not a turn.
            setTask(&s, .compacting, now: now, why: why)

        case .postCompact:
            s.lastEventKind = .postCompact
            setTask(&s, s.isProcessing ? .working : .idle, now: now, why: why)

        case .stop:
            s.lastEventKind = .stop
            s.isProcessing = false
            s.lastStopAt = now
            s.toolStartedSinceStop = false
            setTask(&s, .done, now: now, why: why)

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
                ClaudePetLog.logger.info("forget session=\(ClaudePetLog.short(id), privacy: .public) silent \(Int(silent))s")
                sessions.removeValue(forKey: id)
                changed = true
                continue
            }

            switch s.task {
            case .done where inTask >= tuning.doneDuration:
                setTask(&s, .idle, now: now, why: "done reaction over")
            case .compacting where inTask >= tuning.compactTimeout:
                s.isProcessing = false
                setTask(&s, .idle, now: now, why: "compact timeout")
            case .working where silent >= staleWorkingLimit(for: s):
                s.isProcessing = false
                setTask(&s, .idle, now: now, why: "STALE working: silent \(Int(silent))s after \(s.lastEventKind?.rawValue ?? "?")")
            case .waiting where silent >= tuning.waitingStaleAfter:
                s.isProcessing = false
                setTask(&s, .idle, now: now, why: "STALE waiting: silent \(Int(silent))s")
            case .idle where silent >= tuning.sleepDelay:
                setTask(&s, .sleeping, now: now, why: "idle for \(Int(silent))s")
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

    private func staleWorkingLimit(for s: ClaudePetSession) -> TimeInterval {
        switch s.lastEventKind {
        case .postToolUse: return tuning.workingStaleAfterPostTool
        case .preToolUse: return tuning.workingStaleAfterPreTool
        default: return tuning.workingStaleAfterOther
        }
    }

    private func setTask(_ s: inout ClaudePetSession, _ task: ClaudePetTask, now: Date, why: String) {
        guard s.task != task else { return }
        let sid = ClaudePetLog.short(s.id), from = s.task.rawValue
        ClaudePetLog.logger.info("state session=\(sid, privacy: .public) \(from, privacy: .public) -> \(task.rawValue, privacy: .public) (\(why, privacy: .public))")
        s.task = task
        s.taskSince = now
    }
}
