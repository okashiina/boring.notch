//
//  ScreenshotWatcher.swift
//  TwoTabs Notch - Smart Shelf
//
//  Watches one user-chosen folder (security-scoped bookmark) and drops new screenshots and screen
//  recordings (.mov/.mp4) on the shelf. Finished-file detection, shelf bookkeeping and the notch preview
//  live in CaptureCore / CaptureIngest / CapturePeek.
//

import AppKit
import Combine
import Defaults
import Foundation
import KeyboardShortcuts
import UniformTypeIdentifiers
import Darwin

@MainActor
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    private var source: DispatchSourceFileSystemObject?
    private var watchedFolder: URL?
    private var isAccessingScope = false
    private var knownNames: Set<String> = []
    private var startedAt = Date()
    private var scanWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var didBootstrap = false

    private init() {}

    // MARK: - Lifecycle

    /// Call once at launch: resumes the watcher if enabled and follows setting changes.
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        Publishers.Merge(
            Defaults.publisher(.smartShelfScreenshotsEnabled, options: []).map { _ in () },
            Defaults.publisher(.smartShelfScreenshotFolderBookmark, options: []).map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
        refresh()
    }

    var isRunning: Bool { source != nil }

    /// Re-reads the settings and (re)starts or stops the watcher.
    func refresh() {
        stop()
        guard Defaults[.smartShelfScreenshotsEnabled], let folder = resolveFolder() else { return }
        start(watching: folder)
    }

    func stop() {
        scanWork?.cancel()
        scanWork = nil
        source?.cancel() // the cancel handler closes the descriptor
        source = nil
        if isAccessingScope, let folder = watchedFolder {
            folder.stopAccessingSecurityScopedResource()
        }
        isAccessingScope = false
        watchedFolder = nil
        knownNames.removeAll()
    }

    // MARK: - Folder choice

    /// Shows the folder picker. Returns true when a folder was stored.
    @discardableResult
    static func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Screenshot Folder"
        panel.message = "Choose the folder your screenshots are saved to."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = suggestedFolder()
        // The notch is an accessory window: bring the picker to the front and keep the notch from closing
        // when the pointer leaves it for the panel.
        SharingStateManager.shared.beginInteraction()
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        SharingStateManager.shared.endInteraction()
        guard response == .OK, let url = panel.url else { return false }
        return store(folder: url)
    }

    @discardableResult
    static func store(folder: URL) -> Bool {
        guard let data = try? folder.bookmarkData(options: .withSecurityScope,
                                                  includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }
        Defaults[.smartShelfScreenshotFolderPath] = folder.path
        Defaults[.smartShelfScreenshotFolderBookmark] = data
        return true
    }

    /// The folder macOS saves screenshots to (`defaults read com.apple.screencapture location`), else ~/Desktop.
    static func suggestedFolder() -> URL {
        let home = realHomeDirectory()
        if let location = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !location.isEmpty {
            let expanded = location.hasPrefix("~")
                ? home.path + location.dropFirst()
                : location
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// The real home folder (FileManager's answer is the sandbox container).
    private static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private func resolveFolder() -> URL? {
        guard let data = Defaults[.smartShelfScreenshotFolderBookmark] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let refreshed = try? url.bookmarkData(options: .withSecurityScope) {
            // Written without triggering a restart: the publisher is dropped via refresh() below.
            Defaults[.smartShelfScreenshotFolderBookmark] = refreshed
        }
        return url
    }

    // MARK: - Watching

    private func start(watching folder: URL) {
        isAccessingScope = folder.startAccessingSecurityScopedResource()
        watchedFolder = folder

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("TwoTabs screenshot watcher: cannot open \(folder.path) (errno \(errno))")
            if isAccessingScope { folder.stopAccessingSecurityScopedResource() }
            isAccessingScope = false
            watchedFolder = nil
            return
        }

        startedAt = Date()
        knownNames = Set(listCaptureNames(in: folder))

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .link], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleScan() {
        scanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        scanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func listCaptureNames(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { CaptureFileKind.kind(forFileName: $0) != nil }
    }

    private func scan() {
        guard let folder = watchedFolder else { return }
        for name in listCaptureNames(in: folder) where !knownNames.contains(name) {
            guard let kind = CaptureFileKind.kind(forFileName: name) else { continue }
            knownNames.insert(name)
            let url = folder.appendingPathComponent(name)
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
            guard values?.isRegularFile ?? true else { continue }
            // Only files created after the watcher started (a little slack for clock rounding).
            if let created = values?.creationDate, created < startedAt.addingTimeInterval(-2) { continue }
            // One task per file: a long recording must not hold up a screenshot taken meanwhile.
            Task { await CaptureIngest.addFile(url, kind: kind) }
        }
    }
}

/// One entry point for app start-up (called from the app delegate).
enum SmartShelfBootstrap {
    @MainActor
    static func start() {
        ScreenshotWatcher.shared.bootstrap()
        ClipboardImageWatcher.shared.bootstrap()
        KeyboardShortcuts.onKeyDown(for: .clearShelf) { SmartShelfClear.perform() }
    }
}
