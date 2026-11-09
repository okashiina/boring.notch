//
//  ClaudePetSprites.swift
//  TwoTabs Notch - Claude Code pet
//
//  Loads Notchi's `claude_*` sprite sheets (Aseprite art by sk-ruban, GPL-3.0, see NOTICE.md) from the app
//  bundle and slices each sheet (square frames laid out in one row) into CGImages.
//  Loaded from files, not from Assets.xcassets, so the shared asset catalog stays untouched.
//

import AppKit
import SwiftUI

enum ClaudePetSprites {
    struct Sheet {
        let frames: [CGImage]
        let fps: Double
        /// "done" plays once, everything else loops.
        let loops: Bool
    }

    /// Notchi's per-task frame rates (NotchiTask.loopDuration); the happy idle sheet runs at 7 fps (expressive).
    private static func spec(for task: ClaudePetTask) -> (file: String, fps: Double, loops: Bool) {
        switch task {
        case .idle: return ("claude_idle_neutral", 3, true)
        case .working: return ("claude_working_neutral", 4, true)
        case .waiting: return ("claude_waiting_neutral", 3, true)
        case .compacting: return ("claude_compacting_neutral", 6, true)
        case .sleeping: return ("claude_sleeping_neutral", 2, true)
        case .done: return ("claude_idle_happy", 7, false)
        }
    }

    private static var cache: [ClaudePetTask: Sheet] = [:]

    @MainActor
    static func sheet(for task: ClaudePetTask) -> Sheet? {
        if let cached = cache[task] { return cached }
        let spec = spec(for: task)
        guard let url = Bundle.main.url(forResource: spec.file, withExtension: "png")
                ?? Bundle.main.url(forResource: spec.file, withExtension: "png", subdirectory: "Sprites"),
              let frames = slice(url: url), !frames.isEmpty
        else { return nil }
        let sheet = Sheet(frames: frames, fps: spec.fps, loops: spec.loops)
        cache[task] = sheet
        return sheet
    }

    static func slice(url: URL) -> [CGImage]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.height > 0
        else { return nil }
        let size = image.height
        let count = max(1, Int((Double(image.width) / Double(size)).rounded()))
        return (0..<count).compactMap { i in
            image.cropping(to: CGRect(x: i * size, y: 0, width: size, height: size))
        }
    }
}

/// One animated sprite. `since` anchors the one-shot "done" animation.
struct ClaudePetSpriteView: View {
    let task: ClaudePetTask
    var since: Date = .distantPast
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let sheet = ClaudePetSprites.sheet(for: task) {
            TimelineView(.animation(minimumInterval: 1.0 / sheet.fps, paused: reduceMotion)) { timeline in
                Image(decorative: sheet.frames[frameIndex(sheet, at: timeline.date)], scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        } else {
            // Sprites missing from the bundle: show a plain glyph instead of nothing.
            Image(systemName: "sparkle")
                .foregroundStyle(.orange)
                .frame(width: size, height: size)
        }
    }

    private func frameIndex(_ sheet: ClaudePetSprites.Sheet, at date: Date) -> Int {
        let count = sheet.frames.count
        if reduceMotion { return 0 }
        if sheet.loops { return Int(date.timeIntervalSinceReferenceDate * sheet.fps) % count }
        return min(count - 1, max(0, Int(date.timeIntervalSince(since) * sheet.fps)))
    }
}
