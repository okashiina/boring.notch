//
//  WebPEncoder.swift
//  TwoTabs Notch - Smart Shelf
//
//  WebP output through ImageIO, only when the running OS can encode it.
//

import Foundation
import CoreGraphics
import ImageIO

enum WebPEncoder {
    static let typeIdentifier = "org.webmproject.webp"

    /// ImageIO can only encode WebP on newer macOS releases; ask the system.
    static var isAvailable: Bool {
        let ids = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return ids.contains(typeIdentifier)
    }

    static func encode(_ image: CGImage, quality: Double) -> Data? {
        guard isAvailable else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, typeIdentifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
