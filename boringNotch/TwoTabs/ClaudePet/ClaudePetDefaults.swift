//
//  ClaudePetDefaults.swift
//  TwoTabs Notch - Claude Code pet
//
//  Settings keys for the Claude Code pet (kept out of Constants.swift to leave upstream files alone).
//

import Defaults
import Foundation

extension Defaults.Keys {
    /// Show the pet beside the closed notch while a Claude Code session is active.
    static let claudePetEnabled = Key<Bool>("claudePetEnabled", default: true)
    /// Hide the pet once every session has fallen asleep (5 minutes without activity).
    static let claudePetHideWhenIdle = Key<Bool>("claudePetHideWhenIdle", default: true)

    /// Security-scoped bookmark to ~/.claude (granted once with an open panel). Unlocks transcripts: assistant text,
    /// session title, git branch, Esc detection and today's usage. nil = not granted.
    static let claudePetClaudeDirBookmark = Key<Data?>("claudePetClaudeDirBookmark", default: nil)
    /// Play a sound when a session starts waiting for you (permission prompt, question).
    static let claudePetSoundWaiting = Key<Bool>("claudePetSoundWaiting", default: true)
    /// Play a sound when a turn finishes.
    static let claudePetSoundDone = Key<Bool>("claudePetSoundDone", default: false)
    /// Show the "Claude needs you" line under the closed notch while a session waits.
    static let claudePetPeek = Key<Bool>("claudePetPeek", default: true)
}
