//
//  ClaudePetTabView.swift
//  TwoTabs Notch - Claude Code pet
//
//  The "Claude" tab of the open notch: grass island with one pet per session on the left; on the right the selected
//  session's header (title, project, branch, state, time in state, jump button), its live activity feed (prompt
//  bubbles, tool rows, assistant text) and today's usage. Layout idea from Notchi's ExpandedPanelView, ActivityRowView,
//  UserPromptBubbleView and AssistantTextRowView (sk-ruban/notchi, GPL-3.0, see NOTICE.md), condensed to fit the
//  190 pt open notch.
//

import Defaults
import SwiftUI

struct ClaudePetTabView: View {
    @ObservedObject private var store = ClaudePetStore.shared
    @ObservedObject private var access = ClaudePetAccess.shared
    @Default(.claudePetEnabled) private var enabled

    var body: some View {
        HStack(spacing: 10) {
            ClaudePetIslandView(sessions: store.sessions, selectedId: store.selectedSession?.id) { store.selectedSessionId = $0.id }
                .frame(width: 236)
            detail
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.refreshUsage(force: true) }
    }

    @ViewBuilder private var detail: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !enabled {
                Text("The Claude Code pet is switched off in Settings > General.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if let session = store.selectedSession {
                if store.sessions.count > 1 { sessionChips }
                ClaudePetSessionHeader(session: session)
                ClaudePetFeedView(session: session)
            } else {
                emptyState
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No active Claude Code sessions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(store.lastEventDate == nil
                 ? "Start `claude` in a terminal. If nothing shows up, run scripts/twotabs/install-claude-hooks.sh once."
                 : "Sessions appear here as soon as Claude Code starts working, and go away when it exits.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var sessionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.sessions) { s in
                    let selected = s.id == store.selectedSession?.id
                    Button { store.selectedSessionId = s.id } label: {
                        HStack(spacing: 4) {
                            Circle().fill(ClaudePetStyle.color(for: s.task)).frame(width: 5, height: 5)
                            Text(s.projectName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.18) : Color.white.opacity(0.07)))
                        .foregroundStyle(selected ? .white : .gray)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 18)
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 6) {
            if let usage = store.usage, access.isGranted {
                Image(systemName: "chart.bar.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                Text("Today ~\(usage.costText) · \(usage.tokensText)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .help("Estimate from local transcripts at list prices (no long-context surcharge).")
            } else if !access.isGranted {
                Button { access.requestAccess() } label: {
                    Label("Give access to ~/.claude", systemImage: "lock.open")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .help("One-time, read only. Adds the assistant's replies, session titles, git branch and today's usage. Without it the tab still shows prompts and tool activity.")
            }
            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }
}

enum ClaudePetStyle {
    static func color(for task: ClaudePetTask) -> Color {
        switch task {
        case .working: return Color(red: 0.85, green: 0.47, blue: 0.34) // Claude orange
        case .waiting: return .orange
        case .compacting: return .purple
        case .done: return .green
        case .idle: return .gray
        case .sleeping: return Color.gray.opacity(0.5)
        }
    }
    static let assistantBlue = Color(red: 0.0, green: 0.48, blue: 1.0)

    static func elapsed(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}

struct ClaudePetSessionHeader: View {
    let session: ClaudePetSession

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack(spacing: 4) {
                        Circle().fill(ClaudePetStyle.color(for: session.task)).frame(width: 6, height: 6)
                        Text(subtitle(now: timeline.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            Button { ClaudePetActions.jump(to: session) } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help(session.hostApp.map { "Bring \(($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")) to the front" } ?? "Bring the terminal to the front")
        }
    }

    private func subtitle(now: Date) -> String {
        var parts = [session.projectName]
        if let branch = session.gitBranch { parts.append(branch) }
        var state = session.task.label
        if session.task == .working || session.task == .waiting, let tool = session.lastTool { state += " · \(tool)" }
        parts.append("\(state) \(ClaudePetStyle.elapsed(now.timeIntervalSince(session.taskSince)))")
        return parts.joined(separator: "  ·  ")
    }
}

struct ClaudePetFeedView: View {
    let session: ClaudePetSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if session.activity.isEmpty {
                        Text(session.lastPrompt.map { "> \($0)" } ?? "Waiting for activity...")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    ForEach(session.activity) { item in
                        ClaudePetActivityRow(item: item).id(item.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.activity.last?.id) { _, last in
                if let last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) } }
            }
            .onAppear { if let last = session.activity.last?.id { proxy.scrollTo(last, anchor: .bottom) } }
        }
        .frame(maxHeight: .infinity)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08)], startPoint: .top, endPoint: .bottom))
    }
}

struct ClaudePetActivityRow: View {
    let item: ClaudePetActivity
    @State private var expanded = false

    var body: some View {
        switch item.kind {
        case .prompt(let text):
            // Notchi's user prompt bubble: a soft rounded rectangle.
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.12)))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .tool(let name, let detail, let finished):
            HStack(spacing: 5) {
                Circle()
                    .fill(finished ? Color.green.opacity(0.8) : ClaudePetStyle.color(for: .working))
                    .frame(width: 5, height: 5)
                    .opacity(finished ? 1 : 0.9)
                Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                if let detail {
                    Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        case .assistant(let text):
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(ClaudePetStyle.assistantBlue).frame(width: 5, height: 5).padding(.top, 4)
                Text(text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white)
                    .lineLimit(expanded ? 12 : 2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
        }
    }
}
