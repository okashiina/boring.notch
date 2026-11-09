//
//  CaptureMedia.swift
//  TwoTabs Notch - Smart Shelf
//
//  Reads what the notch preview needs from a capture file: a small thumbnail, and for a recording its
//  duration and whether the movie is finished (its index is written, so it opens). No app state, so the
//  standalone tests compile this file too.
//

import AppKit
import AVFoundation
import Foundation
import ImageIO

enum CaptureMedia {
    @Sendable
    static func movieIsPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        return playable && seconds.isFinite && seconds > 0
    }

    static func imageThumbnail(_ url: URL, maxPixel: Int = 128) async -> NSImage? {
        await Task.detached(priority: .utility) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }

    static func videoInfo(_ url: URL) async -> (duration: TimeInterval?, thumbnail: NSImage?) {
        let asset = AVURLAsset(url: url)
        let seconds = try? await asset.load(.duration).seconds
        let duration = (seconds?.isFinite ?? false) ? seconds : nil
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 256, height: 256)
        var thumbnail: NSImage?
        if let result = try? await generator.image(at: CMTime(seconds: min(0.3, (duration ?? 0) / 2), preferredTimescale: 600)) {
            let cg = result.image
            thumbnail = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        return (duration, thumbnail)
    }
}
