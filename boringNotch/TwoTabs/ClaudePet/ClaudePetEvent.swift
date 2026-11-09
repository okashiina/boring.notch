//
//  ClaudePetEvent.swift
//  TwoTabs Notch - Claude Code pet
//
//  Parses Claude Code hook payloads (as forwarded by twotabs-notch-hook.sh) into a small event value.
//  Foundation only, so it can be compiled and tested outside the app.
//
//  Wire format, one message per socket connection:
//      optional header lines, each starting with "#":
//          "#twotabs interactive=0|1"
//          "#twotabs-host /Applications/iTerm.app"   (app bundle that hosts the terminal running Claude Code)
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
    /// Short human summary of the tool input (file name, command, pattern, ...), for the activity feed.
    var toolSummary: String?
    /// Path of the session transcript (JSONL), when the payload carries one.
    var transcriptPath: String?
    /// Bundle path of the app hosting the session's terminal, from the hook's ancestor walk (SessionStart / UserPromptSubmit only).
    var hostApp: String?

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
        var hostApp: String?
        for line in header {
            if let range = line.range(of: "interactive=") {
                interactive = line[range.upperBound...].first == "1"
            } else if line.hasPrefix("#twotabs-host ") {
                let path = String(line.dropFirst("#twotabs-host ".count))
                if path.hasSuffix(".app") { hostApp = path }
            }
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
            interactive: interactive,
            toolSummary: toolSummary(tool: object["tool_name"] as? String, input: object["tool_input"] as? [String: Any]),
            transcriptPath: object["transcript_path"] as? String,
            hostApp: hostApp
        )
    }

    /// One short line describing what a tool is about to do, without ever carrying large payloads.
    static func toolSummary(tool: String?, input: [String: Any]?) -> String? {
        guard let input else { return nil }
        func str(_ k: String) -> String? { (input[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func clip(_ t: String, _ n: Int = 80) -> String {
            let line = t.split(whereSeparator: \.isNewline).first.map(String.init) ?? t
            return line.count > n ? String(line.prefix(n)) + "..." : line
        }
        if let path = str("file_path") ?? str("notebook_path") ?? str("path") { return (path as NSString).lastPathComponent }
        if let command = str("command") { return clip(command) }
        if let pattern = str("pattern") { return clip(pattern) }
        if let url = str("url") { return clip(url) }
        if let query = str("query") { return clip(query) }
        if let description = str("description") ?? str("prompt") ?? str("skill") { return clip(description) }
        return nil
    }

    /// True once `buffer` holds a full message, so a server can answer without waiting for EOF.
    static func isComplete(_ buffer: Data) -> Bool {
        guard let (_, body) = split(buffer), !body.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: body)) != nil
    }

    /// Splits leading "#..." header lines from the JSON body. nil while a header line is still incomplete.
    private static func split(_ data: Data) -> (header: [String], body: Data)? {
        guard data.first != nil else { return nil }
        var header: [String] = []
        var rest = data[...]
        while rest.first == UInt8(ascii: "#") {
            guard let newline = rest.firstIndex(of: UInt8(ascii: "\n")) else { return nil } // header line not complete yet
            header.append(String(decoding: rest[rest.startIndex..<newline], as: UTF8.self))
            rest = rest[rest.index(after: newline)...]
        }
        return (header, Data(rest))
    }
}
