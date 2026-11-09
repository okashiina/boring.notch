//
//  ClaudePetActions.swift
//  TwoTabs Notch - Claude Code pet
//
//  Sound and "jump to terminal". Both work in the sandbox with the existing entitlements: the hook (unsandboxed)
//  walks the process tree and sends the .app bundle path hosting the terminal, and NSWorkspace opens that app,
//  which brings it to the front (no Apple Events, no Accessibility permission). The jump goes to the app, not to the
//  exact tab or window: the sandbox has no way to focus a specific tab. Notchi's TerminalJumpService uses the host
//  process id and NSRunningApplication.activate(); same idea, but it runs unsandboxed.
//

import AppKit
import Defaults

@MainActor
enum ClaudePetActions {
    private static let terminalBundleIds = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "co.zeit.hyper", "com.github.wez.wezterm", "org.alacritty", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.anthropic.claudefordesktop",
    ]

    /// Brings the terminal (or Claude desktop app) that hosts the session to the front.
    @discardableResult
    static func jump(to session: ClaudePetSession) -> Bool {
        if let host = session.hostApp {
            let url = URL(fileURLWithPath: host)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { ClaudePetLog.logger.error("jump failed: \(error.localizedDescription, privacy: .public)") }
            }
            ClaudePetLog.logger.info("jump session=\(ClaudePetLog.short(session.id), privacy: .public) host=\(url.lastPathComponent, privacy: .public)")
            return true
        }
        // Hook script without the host line (installed before this feature): first running known terminal.
        for id in terminalBundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                ClaudePetLog.logger.info("jump fallback to \(id, privacy: .public)")
                return app.activate()
            }
        }
        return false
    }

    private static var lastSound: [String: Date] = [:]

    enum Cue { case waiting, done }

    /// Plays a system sound unless the session's own terminal is already in front. 2 s cooldown per session.
    static func playSound(_ cue: Cue, for session: ClaudePetSession) {
        switch cue {
        case .waiting: guard Defaults[.claudePetSoundWaiting] else { return }
        case .done: guard Defaults[.claudePetSoundDone] else { return }
        }
        guard session.interactive else { return }
        if let host = session.hostApp, NSWorkspace.shared.frontmostApplication?.bundleURL?.path == host { return }
        let now = Date()
        if let last = lastSound[session.id], now.timeIntervalSince(last) < 2 { return }
        lastSound[session.id] = now
        NSSound(named: cue == .waiting ? "Glass" : "Hero")?.play()
    }
}
