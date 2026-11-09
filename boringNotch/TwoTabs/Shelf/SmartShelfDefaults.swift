//
//  SmartShelfDefaults.swift
//  TwoTabs Notch - Smart Shelf
//
//  Settings keys for the smart shelf (kept out of Constants.swift to leave upstream files alone).
//

import Foundation
import Defaults

enum SmartShelfUploadHost: String, CaseIterable, Identifiable, Defaults.Serializable {
    case litterbox
    case catbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .litterbox: return "Litterbox (temporary)"
        case .catbox: return "Catbox (permanent)"
        }
    }
}

enum LitterboxExpiry: String, CaseIterable, Identifiable, Defaults.Serializable {
    case hour1 = "1h"
    case hours12 = "12h"
    case hours24 = "24h"
    case hours72 = "72h"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour1: return "1 hour"
        case .hours12: return "12 hours"
        case .hours24: return "24 hours"
        case .hours72: return "72 hours"
        }
    }
}

extension Defaults.Keys {
    // Upload
    static let smartShelfUploadHost = Key<SmartShelfUploadHost>("smartShelfUploadHost", default: .litterbox)
    static let smartShelfLitterboxExpiry = Key<LitterboxExpiry>("smartShelfLitterboxExpiry", default: .hours72)

    // Screenshots to shelf
    static let smartShelfScreenshotsEnabled = Key<Bool>("smartShelfScreenshotsEnabled", default: false)
    static let smartShelfScreenshotFolderBookmark = Key<Data?>("smartShelfScreenshotFolderBookmark", default: nil)
    static let smartShelfScreenshotFolderPath = Key<String?>("smartShelfScreenshotFolderPath", default: nil)

    // Shrink
    static let smartShelfShrinkMaxDimension = Key<Int>("smartShelfShrinkMaxDimension", default: 1920)
    static let smartShelfShrinkQuality = Key<Double>("smartShelfShrinkQuality", default: 0.8)
}

extension SmartShelfUploadHost {
    /// The upload target for the current settings.
    @MainActor
    static var currentTarget: UploadTarget {
        switch Defaults[.smartShelfUploadHost] {
        case .litterbox: return .litterbox(expiry: Defaults[.smartShelfLitterboxExpiry].rawValue)
        case .catbox: return .catbox
        }
    }
}
