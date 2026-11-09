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
    @Default(.claudePetSoundWaiting) private var soundWaiting
    @Default(.claudePetSoundDone) private var soundDone
    @Default(.claudePetPeek) private var peek
    @ObservedObject private var access = ClaudePetAccess.shared

    var body: some View {
        Section {
            Toggle("Show Claude Code pet beside the notch", isOn: $enabled)
            Toggle("Hide when idle (after 5 minutes asleep)", isOn: $hideWhenIdle)
                .disabled(!enabled)

            Toggle("Sound when Claude waits for you", isOn: $soundWaiting).disabled(!enabled)
            Toggle("Sound when a turn finishes", isOn: $soundDone).disabled(!enabled)
            Toggle("Show \"Claude needs you\" under the closed notch", isOn: $peek).disabled(!enabled)

            LabeledContent("Transcripts (~/.claude)") {
                HStack {
                    Text(access.isGranted ? "Access granted" : "Not granted").foregroundStyle(access.isGranted ? .green : .orange)
                    if access.isGranted {
                        Button("Revoke") { access.revoke() }
                    } else {
                        Button("Give access...") { access.requestAccess() }
                    }
                }
            }
            if !access.isGranted {
                Text("Optional, read only. Adds Claude's replies, session titles, git branch, interrupt detection and today's usage to the Claude tab. Pick your .claude folder in the dialog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
