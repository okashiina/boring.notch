//
//  ClaudePetLog.swift
//  TwoTabs Notch - Claude Code pet
//
//  One os.Logger for the whole pet. Read it with:
//      log show --last 5m --predicate 'subsystem == "com.okashiina.twotabsnotch" AND category == "ClaudePet"' --info
//  Values are marked .public (kinds, short session ids, tool names, states): prompts and transcript text are never logged.
//

import Foundation
import os

enum ClaudePetLog {
    static let logger = Logger(subsystem: "com.okashiina.twotabsnotch", category: "ClaudePet")

    /// First 8 characters of a session id, enough to tell sessions apart in the log.
    static func short(_ id: String) -> String { String(id.prefix(8)) }
}
