//
//  ClaudePetSettingsSection.swift
//  TwoTabs Notch - Claude Code pet
//
//  "Claude Code Pet" section of the General settings pane.
//

import Defaults
import SwiftUI

struct ClaudePetSettingsSection: View {
    @ObservedObject private var store = ClaudePetStore.shared
    @Default(.claudePetEnabled) private var enabled
    @Default(.claudePetHideWhenIdle) private var hideWhenIdle

    var body: some View {
        Section {
            Toggle("Show Claude Code pet beside the notch", isOn: $enabled)
            Toggle("Hide when idle (after 5 minutes asleep)", isOn: $hideWhenIdle)
                .disabled(!enabled)

            LabeledContent("Socket") { Text(socketText).foregroundStyle(socketColor) }
            LabeledContent("Hooks") { Text(hookText).foregroundStyle(store.lastEventDate == nil ? .orange : .green) }

            if store.lastEventDate == nil {
                Text("The app is sandboxed and cannot read ~/.claude/settings.json, so hooks count as installed once an event arrives. To install them, run scripts/twotabs/install-claude-hooks.sh from the repo, then start a new Claude Code session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(store.sessions) { ClaudePetSessionRow(session: $0) }
        } header: {
            Text("Claude Code Pet")
        }
    }

    private var socketText: String {
        switch store.serverStatus {
        case .stopped: return "Not running"
        case .listening: return "Listening"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }

    private var socketColor: Color {
        if case .listening = store.serverStatus { return .green }
        return .red
    }

    private var hookText: String {
        guard let last = store.lastEventDate else { return "No events received yet" }
        let seconds = max(0, Int(Date().timeIntervalSince(last)))
        return "Receiving events (last \(seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m") ago)"
    }
}
