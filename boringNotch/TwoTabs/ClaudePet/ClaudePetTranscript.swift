//
//  ClaudePetTranscript.swift
//  TwoTabs Notch - Claude Code pet
//
//  Incremental reader for a Claude Code session transcript (JSONL). Ported in spirit from Notchi's
//  ConversationParser (sk-ruban/notchi, GPL-3.0): offset based, so a growing file is only read once. Pulls out
//  assistant text, the session title, the git branch and "[Request interrupted by user" (Esc sends no Stop hook).
//  Foundation only.
//

import Foundation

struct ClaudePetTranscriptUpdate {
    struct Text { let id: String; let text: String; let date: Date }
    var texts: [Text] = []
    var title: String?
    var gitBranch: String?
    var interrupted = false
}

actor ClaudePetTranscriptReader {
    private struct State { var offset: UInt64 = 0; var seen = Set<String>(); var primed = false }
    private var states: [String: State] = [:]

    /// First read only looks at the tail, so a huge old transcript is not parsed.
    static let initialTailBytes: UInt64 = 400 * 1024
    static let maxInitialTexts = 6

    func read(path: String) -> ClaudePetTranscriptUpdate {
        var update = ClaudePetTranscriptUpdate()
        guard let handle = FileHandle(forReadingAtPath: path) else { return update }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return update }

        var state = states[path] ?? State()
        let firstRead = !state.primed
        if size < state.offset { state = State() }
        if firstRead && size > Self.initialTailBytes { state.offset = size - Self.initialTailBytes }
        guard size > state.offset else { state.primed = true; states[path] = state; return update }

        try? handle.seek(toOffset: state.offset)
        guard let data = try? handle.readToEnd() else { return update }
        // Only consume complete lines; a half-written last line is picked up next time.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return update }
        var chunk = data[data.startIndex...lastNewline]
        if firstRead && state.offset > 0, let firstNewline = chunk.firstIndex(of: UInt8(ascii: "\n")) {
            chunk = chunk[chunk.index(after: firstNewline)...] // drop the partial first line of a tail read
        }
        state.offset += UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)

        for lineData in chunk.split(separator: UInt8(ascii: "\n")) {
            guard !lineData.isEmpty else { continue }
            let line = String(decoding: lineData, as: UTF8.self)
            let isUser = line.contains("\"type\":\"user\"")
            if !firstRead, isUser, line.contains("[Request interrupted by user") { update.interrupted = true }
            guard let object = (try? JSONSerialization.jsonObject(with: Data(lineData))) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            if let branch = object["gitBranch"] as? String, !branch.isEmpty { update.gitBranch = branch }
            switch type {
            case "custom-title":
                if let t = object["customTitle"] as? String, !t.isEmpty { update.title = t }
            case "assistant":
                guard object["isSidechain"] as? Bool != true,
                      let uuid = object["uuid"] as? String, !state.seen.contains(uuid),
                      let message = object["message"] as? [String: Any],
                      let content = message["content"] as? [[String: Any]] else { continue }
                state.seen.insert(uuid)
                let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                update.texts.append(.init(id: uuid, text: text, date: Self.parseDate(object["timestamp"] as? String) ?? Date()))
            default: break
            }
        }
        if firstRead, update.texts.count > Self.maxInitialTexts { update.texts = Array(update.texts.suffix(Self.maxInitialTexts)) }
        state.primed = true
        states[path] = state
        return update
    }

    func forget(path: String) { states.removeValue(forKey: path) }

    nonisolated static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
