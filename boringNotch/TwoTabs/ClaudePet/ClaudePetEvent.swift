//
//  ClaudePetEvent.swift
//  TwoTabs Notch - Claude Code pet
//
//  Parses Claude Code hook payloads (as forwarded by twotabs-notch-hook.sh) into a small event value.
//  Foundation only, so it can be compiled and tested outside the app.
//
//  Wire format, one message per socket connection:
//      optional first line  "#twotabs interactive=0|1"
//      then the raw JSON object Claude Code passed to the hook on stdin.
//  Ported in spirit from Notchi (sk-ruban/notchi, GPL-3.0): see NOTICE.md.
//

import Foundation

enum ClaudePetEventKind: String {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case sessionEnd = "SessionEnd"
}

struct ClaudePetEvent: Equatable {
    var sessionId: String
    var kind: ClaudePetEventKind
    var cwd: String?
    var tool: String?
    /// Claude Code `notification_type` (permission_prompt, idle_prompt, elicitation_dialog, auth_success).
    var notificationType: String?
    var message: String?
    /// SessionStart `source` (startup, resume, clear, compact).
    var source: String?
    /// First characters of the user prompt, only used to spot local slash commands.
    var promptHead: String?
    /// nil = unknown (hook did not say). false = headless `claude -p`.
    var interactive: Bool?

    static let maxMessageBytes = 8 * 1024 * 1024

    /// Decodes a complete wire message. Returns nil for malformed JSON, unknown events or missing session id.
    static func decode(_ data: Data) -> ClaudePetEvent? {
        guard let (header, body) = split(data), let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        guard let name = object["hook_event_name"] as? String,
              let kind = ClaudePetEventKind(rawValue: name),
              let sessionId = object["session_id"] as? String, !sessionId.isEmpty
        else { return nil }

        var interactive: Bool?
        if let header, let range = header.range(of: "interactive=") {
            interactive = header[range.upperBound...].first == "1"
        }

        return ClaudePetEvent(
            sessionId: sessionId,
            kind: kind,
            cwd: object["cwd"] as? String,
            tool: object["tool_name"] as? String,
            notificationType: object["notification_type"] as? String,
            message: object["message"] as? String,
            source: object["source"] as? String,
            promptHead: (object["prompt"] as? String).map { String($0.prefix(80)) },
            interactive: interactive
        )
    }

    /// True once `buffer` holds a full message, so a server can answer without waiting for EOF.
    static func isComplete(_ buffer: Data) -> Bool {
        guard let (_, body) = split(buffer), !body.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: body)) != nil
    }

    private static func split(_ data: Data) -> (header: String?, body: Data)? {
        guard let first = data.first else { return nil }
        guard first == UInt8(ascii: "#") else { return (nil, data) }
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else { return nil } // header line not complete yet
        let header = String(decoding: data[data.startIndex..<newline], as: UTF8.self)
        return (header, data[data.index(after: newline)...])
    }
}
