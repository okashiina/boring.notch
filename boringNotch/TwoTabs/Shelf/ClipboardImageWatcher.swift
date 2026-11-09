//
//  ClipboardImageWatcher.swift
//  TwoTabs Notch - Smart Shelf
//
//  Screenshots taken with Control held (⌃⌘⇧3 / ⌃⌘⇧4) and every other image you copy go to the pasteboard,
//  not to a file. While "Also catch copied images" is on, this polls the pasteboard's change count (a
//  cheap integer read) and adds each new image to the shelf as a temporary PNG.
//

import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class ClipboardImageWatcher {
    static let shared = ClipboardImageWatcher()

    static let pollInterval: TimeInterval = 0.75

    private var timer: Timer?
    private var monitor: PasteboardImageMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var didBootstrap = false

    private init() {}

    /// Call once at launch: follows the two settings that control it.
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        Publishers.Merge(
            Defaults.publisher(.smartShelfScreenshotsEnabled, options: []).map { _ in () },
            Defaults.publisher(.smartShelfCatchCopiedImages, options: []).map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
        refresh()
    }

    var isRunning: Bool { timer != nil }

    func refresh() {
        stop()
        guard Defaults[.smartShelfScreenshotsEnabled], Defaults[.smartShelfCatchCopiedImages] else { return }
        // Whatever is on the pasteboard now was copied before the feature was on: not a new capture.
        monitor = PasteboardImageMonitor(pasteboard: .general)
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        monitor = nil
    }

    private func poll() {
        guard let monitor else { return }
        // Copying inside TwoTabs Notch itself (its own windows) is not a capture.
        if NSApp.isActive {
            monitor.rebaseline()
            return
        }
        guard let image = monitor.poll() else { return }
        Task { await CaptureIngest.addClipboardImage(image) }
    }
}
