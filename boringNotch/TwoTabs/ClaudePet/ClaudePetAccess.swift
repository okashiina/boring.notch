//
//  ClaudePetAccess.swift
//  TwoTabs Notch - Claude Code pet
//
//  The app is sandboxed and cannot read ~/.claude. One open-panel grant (security-scoped bookmark kept in Defaults,
//  uses the existing user-selected.read-write + bookmarks.app-scope entitlements) unlocks session transcripts and
//  today's usage. Without it the pet still works from hook events alone.
//

import AppKit
import Defaults
import Foundation
import os

@MainActor
final class ClaudePetAccess: ObservableObject {
    static let shared = ClaudePetAccess()

    @Published private(set) var directory: URL?
    var isGranted: Bool { directory != nil }

    private init() { restore() }

    /// The real home directory (NSHomeDirectory() is the container when sandboxed).
    static var realHome: String {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    private func restore() {
        guard let data = Defaults[.claudePetClaudeDirBookmark] else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else {
            ClaudePetLog.logger.error("~/.claude bookmark could not be resolved")
            return
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) { Defaults[.claudePetClaudeDirBookmark] = fresh }
        directory = url
        ClaudePetLog.logger.info("~/.claude access restored: \(url.path, privacy: .public)")
    }

    /// Shows the open panel, prefilled to ~/.claude.
    func requestAccess() {
        let panel = NSOpenPanel()
        panel.message = "Choose your .claude folder so TwoTabs Notch can read session transcripts (read only)."
        panel.prompt = "Allow"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: Self.realHome).appendingPathComponent(".claude")
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.grant(url) }
        }
    }

    private func grant(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            ClaudePetLog.logger.error("could not create a bookmark for \(url.path, privacy: .public)")
            return
        }
        directory?.stopAccessingSecurityScopedResource()
        Defaults[.claudePetClaudeDirBookmark] = data
        _ = url.startAccessingSecurityScopedResource()
        directory = url
        ClaudePetLog.logger.info("~/.claude access granted: \(url.path, privacy: .public)")
        ClaudePetStore.shared.accessChanged()
    }

    func revoke() {
        directory?.stopAccessingSecurityScopedResource()
        directory = nil
        Defaults[.claudePetClaudeDirBookmark] = nil
        ClaudePetLog.logger.info("~/.claude access revoked")
        ClaudePetStore.shared.accessChanged()
    }

    /// True when `path` lies inside the granted folder.
    func covers(_ path: String) -> Bool {
        guard let directory else { return false }
        return path.hasPrefix(directory.path + "/")
    }
}
