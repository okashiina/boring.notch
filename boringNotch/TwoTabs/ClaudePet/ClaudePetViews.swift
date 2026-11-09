//
//  ClaudePetViews.swift
//  TwoTabs Notch - Claude Code pet
//
//  Closed-notch activity, music-slot sprite, open-notch session list and header button.
//

import Defaults
import SwiftUI

/// Sprite for the session that currently needs the pet most, with a count badge when several are active.
struct ClaudePetBadgedSprite: View {
    @ObservedObject private var store = ClaudePetStore.shared
    /// Layout slot (what the surrounding HStack reserves). The sprite may be larger and overflows centered.
    let slot: CGFloat
    let spriteSize: CGFloat

    var body: some View {
        if let top = store.displaySession {
            ClaudePetSpriteView(task: top.task, since: top.taskSince, size: spriteSize)
                .id(top.task) // restart the one-shot "done" animation per state
                .overlay(alignment: .topTrailing) {
                    if store.sessionCount > 1 {
                        Text("\(store.sessionCount)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 11, minHeight: 11)
                            .background(Capsule().fill(top.task == .waiting ? Color.orange : Color.gray.opacity(0.85)))
                            .offset(x: 3, y: 0)
                    }
                }
                // Gentle hop whenever a session starts waiting for you.
                .keyframeAnimator(initialValue: CGFloat(0), trigger: store.bounceTrigger) { content, lift in
                    content.offset(y: lift)
                } keyframes: { _ in
                    LinearKeyframe(-7, duration: 0.14)
                    SpringKeyframe(0, duration: 0.45, spring: .bouncy)
                    LinearKeyframe(-4, duration: 0.12)
                    SpringKeyframe(0, duration: 0.35, spring: .bouncy)
                }
                .frame(width: slot, height: slot)
                .help("\(top.projectName): \(top.task.label)")
        }
    }
}

/// Closed notch with only the pet: mirrors BoringFaceAnimation's geometry (empty left slot, notch, pet on the right).
struct ClaudePetClosedActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var store = ClaudePetStore.shared

    var body: some View {
        let slot = max(0, vm.effectiveClosedNotchHeight - 12)
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Rectangle().fill(.clear).frame(width: slot, height: slot)
                    Rectangle().fill(.black).frame(width: vm.closedNotchSize.width - 20)
                    ClaudePetBadgedSprite(slot: slot, spriteSize: max(slot, vm.effectiveClosedNotchHeight - 4))
                }
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)

            // Sneak peek: the notch grows a line while a session waits for you.
            if store.attentionPeek, let waiting = store.sessions.first(where: { $0.task == .waiting }) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.orange)
                    Text("Claude needs you · \(waiting.projectName)").lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: vm.closedNotchSize.width, alignment: .center)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth, value: store.attentionPeek)
    }
}

/// Replaces the music visualizer in MusicLiveActivity while a session needs attention.
struct ClaudePetMusicSlot: View {
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        let slot = max(0, vm.effectiveClosedNotchHeight - 12)
        ClaudePetBadgedSprite(slot: slot, spriteSize: max(slot, vm.effectiveClosedNotchHeight - 4))
    }
}

// MARK: - Open notch

struct ClaudePetSessionRow: View {
    let session: ClaudePetSession

    var body: some View {
        HStack(spacing: 8) {
            ClaudePetSpriteView(task: session.task, since: session.taskSince, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
    }

    private var detail: String {
        if let tool = session.lastTool, session.task == .working || session.task == .waiting {
            return "\(session.task.label) · \(tool)"
        }
        return session.task.label
    }
}

struct ClaudePetSessionList: View {
    @ObservedObject private var store = ClaudePetStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.sessions.isEmpty {
                Text("No active Claude Code sessions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.sessions) { ClaudePetSessionRow(session: $0) }
            }
        }
        .padding(12)
        .frame(minWidth: 200, alignment: .leading)
    }
}

/// Small pet button for the open notch header; click lists the active sessions.
struct ClaudePetHeaderButton: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var store = ClaudePetStore.shared
    @Default(.claudePetEnabled) private var enabled
    @State private var showList = false

    var body: some View {
        if enabled, let top = store.displaySession {
            Button {
                showList.toggle()
            } label: {
                ClaudePetBadgedSprite(slot: 30, spriteSize: 28)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showList, arrowEdge: .bottom) { ClaudePetSessionList() }
            // Same trick as the battery popover: keep the notch open while the popover is up.
            .onChange(of: showList) { vm.isBatteryPopoverActive = showList }
            .help("\(top.projectName): \(top.task.label)")
        }
    }
}
