//
//  ClaudePetIsland.swift
//  TwoTabs Notch - Claude Code pet
//
//  The grass island of the Claude tab: one wandering pet per session on Notchi's grass texture (sk-ruban/notchi,
//  GPL-3.0, see NOTICE.md). Walk and bob parameters follow Notchi's NotchiTask (walkFrequencyRange, bobDuration,
//  bobAmplitude, canWalk). Pixel art stays crisp (.interpolation(.none)).
//

import SwiftUI

enum ClaudePetIslandLayout {
    static let spriteSize: CGFloat = 64
    static let walkSpeed: CGFloat = 20 // points per second

    static func canWalk(_ task: ClaudePetTask) -> Bool { task == .idle || task == .working || task == .done }

    /// Seconds between walks.
    static func walkDelay(_ task: ClaudePetTask) -> ClosedRange<Double> {
        switch task {
        case .working: return 4...9
        case .idle, .done: return 6...14
        default: return 30...60
        }
    }

    static func bob(_ task: ClaudePetTask) -> (duration: Double, amplitude: CGFloat) {
        switch task {
        case .sleeping: return (4, 0)
        case .idle: return (1.5, 1.5)
        case .waiting: return (1.5, 0.5)
        case .working: return (0.4, 0.5)
        case .compacting: return (0.5, 0)
        case .done: return (0.5, 2)
        }
    }

    /// Stable 0...1 values per session id (FNV-1a), so a session keeps its spot on the island.
    static func hash01(_ id: String, salt: UInt64) -> CGFloat {
        var h: UInt64 = 0xcbf29ce484222325 ^ salt
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return CGFloat(h % 10_000) / 10_000
    }
}

struct ClaudePetIslandView: View {
    let sessions: [ClaudePetSession]
    let selectedId: String?
    var onSelect: (ClaudePetSession) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                grass
                if sessions.isEmpty {
                    Text("No Claude Code session")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // Back to front: pets lower on the island draw last.
                ForEach(sessions.sorted { depth($0) < depth($1) }) { s in
                    IslandPet(session: s, size: geo.size, showName: sessions.count > 1, selected: s.id == selectedId, depth: depth(s),
                              startX: startX(of: s)) {
                        onSelect(s)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func depth(_ s: ClaudePetSession) -> CGFloat { ClaudePetIslandLayout.hash01(s.id, salt: 7) }

    /// Sessions start spread evenly (in id order, so a session keeps its spot as others come and go) instead of piling up.
    private func startX(of s: ClaudePetSession) -> CGFloat {
        let ids = sessions.map(\.id).sorted()
        let rank = ids.firstIndex(of: s.id) ?? 0
        return (CGFloat(rank) + 0.5) / CGFloat(max(1, ids.count))
    }

    @ViewBuilder private var grass: some View {
        if let image = ClaudePetSprites.image(named: "claude_island_grass") {
            Rectangle()
                .fill(ImagePaint(image: Image(decorative: image, scale: 1).interpolation(.none), scale: 1))
        } else {
            Color(red: 0.55, green: 0.78, blue: 0.65)
        }
    }
}

private struct IslandPet: View {
    let session: ClaudePetSession
    let size: CGSize
    let showName: Bool
    let selected: Bool
    let depth: CGFloat
    var onTap: () -> Void

    @State private var x: CGFloat
    @State private var flipped = false
    @State private var hovering = false
    @State private var tapScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(session: ClaudePetSession, size: CGSize, showName: Bool, selected: Bool, depth: CGFloat, startX: CGFloat, onTap: @escaping () -> Void) {
        self.session = session; self.size = size; self.showName = showName; self.selected = selected; self.depth = depth; self.onTap = onTap
        _x = State(initialValue: min(0.95, max(0.05, startX)))
    }

    var body: some View {
        let sprite = ClaudePetIslandLayout.spriteSize
        let usable = max(0, size.width - sprite)
        // Row on the island: 0 = back (higher up), 1 = front. Keeps the feet inside the strip.
        let slack = max(0, size.height - sprite - (showName ? 12 : 4))
        let bob = ClaudePetIslandLayout.bob(session.task)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || bob.amplitude == 0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let dy = reduceMotion ? 0 : CGFloat(sin(t / bob.duration * 2 * .pi)) * bob.amplitude
            VStack(spacing: 0) {
                ClaudePetSpriteView(task: session.task, since: session.taskSince, size: sprite)
                    .scaleEffect(x: flipped ? -1 : 1, y: 1)
                    .background(alignment: .bottom) {
                        Ellipse()
                            .fill(Color(red: 0.4, green: 0.7, blue: 1.0).opacity(selected ? 0.7 : (hovering ? 0.35 : 0)))
                            .frame(width: sprite * 0.8, height: sprite * 0.2)
                            .blur(radius: 7)
                            .offset(y: 3)
                    }
                    .offset(y: dy)
                if showName {
                    Text(session.projectName)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .frame(maxWidth: 80)
                        .padding(.top, -4)
                }
            }
            .scaleEffect(tapScale)
            .offset(x: x * usable, y: -(1 - depth) * slack - 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { tapScale = 1.12 }
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { tapScale = 1 }
            }
            onTap()
        }
        .onHover { hovering = $0 }
        .help("\(session.displayTitle): \(session.task.label)")
        .task(id: session.task) { await wander() }
    }

    /// Walks to a random spot every few seconds while idle or working; waiting, sleeping and compacting stay put.
    private func wander() async {
        guard ClaudePetIslandLayout.canWalk(session.task), !reduceMotion else { return }
        let usable = max(1, size.width - ClaudePetIslandLayout.spriteSize)
        while !Task.isCancelled {
            let delay = Double.random(in: ClaudePetIslandLayout.walkDelay(session.task))
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let target = CGFloat.random(in: 0.05...0.95)
            let distance = abs(target - x) * usable
            guard distance > 8 else { continue }
            let duration = Double(distance / ClaudePetIslandLayout.walkSpeed)
            flipped = target < x
            withAnimation(.linear(duration: duration)) { x = target }
            try? await Task.sleep(for: .seconds(duration))
        }
    }
}
