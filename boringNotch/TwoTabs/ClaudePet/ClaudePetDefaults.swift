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
}
