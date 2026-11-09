//
//  ClaudePetUsage.swift
//  TwoTabs Notch - Claude Code pet
//
//  Today's token and cost estimate, scanned from the local transcripts (needs the ~/.claude grant). Ported in spirit
//  from Notchi's ClaudeCostScanner + claude-pricing-fallback.json (sk-ruban/notchi, GPL-3.0). It is an estimate:
//  list prices per model family, no long-context surcharge. Notchi's network usage API (OAuth / keychain) is not ported.
//

import Foundation

struct ClaudePetUsageTotals: Equatable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var cost = 0.0
    var messages = 0

    var totalTokens: Int { input + output + cacheWrite + cacheRead }

    var costText: String { cost < 10 ? String(format: "$%.2f", cost) : String(format: "$%.0f", cost) }
    var tokensText: String {
        let t = Double(totalTokens)
        if t >= 1_000_000 { return String(format: "%.1fM tokens", t / 1_000_000) }
        if t >= 1_000 { return String(format: "%.0fk tokens", t / 1_000) }
        return "\(totalTokens) tokens"
    }
}

enum ClaudePetPricing {
    /// USD per token: (input, output, cache write, cache read). Same numbers as Notchi's fallback table, by family.
    static func rates(model: String) -> (Double, Double, Double, Double) {
        let m = model.lowercased()
        if m.contains("fable") { return (10e-6, 50e-6, 12.5e-6, 1e-6) }
        if m.contains("opus") { return (5e-6, 25e-6, 6.25e-6, 0.5e-6) }
        if m.contains("haiku") { return (1e-6, 5e-6, 1.25e-6, 0.1e-6) }
        return (3e-6, 15e-6, 3.75e-6, 0.3e-6) // sonnet and anything unknown
    }
}

actor ClaudePetUsageScanner {
    private struct Entry { var model: String; var input: Int; var output: Int; var write: Int; var read: Int }
    private struct FileCache { var size: UInt64; var day: Date; var entries: [String: Entry] }
    private var cache: [String: FileCache] = [:]

    /// `claudeDir` is the granted ~/.claude folder.
    func today(claudeDir: URL) -> ClaudePetUsageTotals {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let projects = claudeDir.appendingPathComponent("projects")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: projects, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return .init() }
        var merged: [String: Entry] = [:]
        var live = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate, modified >= startOfDay else { continue }
            let size = UInt64(values.fileSize ?? 0)
            live.insert(url.path)
            if let c = cache[url.path], c.size == size, c.day == startOfDay {
                merged.merge(c.entries) { _, new in new }
                continue
            }
            let entries = Self.scan(url: url, since: startOfDay)
            cache[url.path] = FileCache(size: size, day: startOfDay, entries: entries)
            merged.merge(entries) { _, new in new }
        }
        cache = cache.filter { live.contains($0.key) }

        var totals = ClaudePetUsageTotals()
        for e in merged.values {
            let r = ClaudePetPricing.rates(model: e.model)
            totals.input += e.input; totals.output += e.output; totals.cacheWrite += e.write; totals.cacheRead += e.read
            totals.cost += Double(e.input) * r.0 + Double(e.output) * r.1 + Double(e.write) * r.2 + Double(e.read) * r.3
            totals.messages += 1
        }
        return totals
    }

    /// Assistant lines of one file from today, keyed by message id (a message is written once per content block with
    /// the same usage; the last one wins).
    private static func scan(url: URL, since: Date) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [:] }
        var out: [String: Entry] = [:]
        let marker = Data("\"usage\"".utf8)
        for lineData in data.split(separator: UInt8(ascii: "\n")) {
            guard lineData.range(of: marker) != nil,
                  let o = (try? JSONSerialization.jsonObject(with: Data(lineData))) as? [String: Any],
                  o["type"] as? String == "assistant",
                  let ts = ClaudePetTranscriptReader.parseDate(o["timestamp"] as? String), ts >= since,
                  let message = o["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }
            let id = (message["id"] as? String) ?? (o["uuid"] as? String) ?? UUID().uuidString
            out[id] = Entry(
                model: message["model"] as? String ?? "",
                input: usage["input_tokens"] as? Int ?? 0,
                output: usage["output_tokens"] as? Int ?? 0,
                write: usage["cache_creation_input_tokens"] as? Int ?? 0,
                read: usage["cache_read_input_tokens"] as? Int ?? 0)
        }
        return out
    }
}
