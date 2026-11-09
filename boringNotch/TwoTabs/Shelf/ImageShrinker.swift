//
//  ImageShrinker.swift
//  TwoTabs Notch - Smart Shelf
//
//  Pure ImageIO based "shrink" (downscale + recompress). No app dependencies,
//  so it can be compiled and tested stand-alone.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageShrinker {

    struct Output {
        let data: Data
        /// Suggested file name: `<name>-small.<ext>`
        let fileName: String
        let fileExtension: String
        let originalBytes: Int
        let originalWidth: Int
        let originalHeight: Int
        let width: Int
        let height: Int
        /// True when the pixel size was reduced.
        let resized: Bool
        /// True when the result was written as PNG because the image really uses transparency.
        let keptPNG: Bool

        var outputBytes: Int { data.count }
    }

    enum ShrinkError: LocalizedError {
        case unreadable
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: return "The file could not be read as an image."
            case .encodeFailed: return "The image could not be re-encoded."
            }
        }
    }

    /// Downscale so the longest side is at most `maxDimension` (never upscales) and re-encode.
    /// - JPEG at `quality` for opaque images (EXIF/GPS metadata is dropped, orientation is applied).
    /// - PNG (scaled, lossless) when the image genuinely contains transparent pixels.
    static func shrink(url: URL, maxDimension: Int, quality: Double) throws -> Output {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let srcW = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let srcH = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              srcW > 0, srcH > 0
        else { throw ShrinkError.unreadable }

        let originalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let longest = max(srcW, srcH)
        let target = min(max(maxDimension, 16), longest)

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw ShrinkError.unreadable
        }

        let declaredAlpha = (props[kCGImagePropertyHasAlpha] as? Bool) ?? false
        let usesAlpha = declaredAlpha && hasTransparentPixels(scaled)

        let baseName = url.deletingPathExtension().lastPathComponent
        let data: Data
        let ext: String

        if usesAlpha {
            ext = "png"
            guard let encoded = encode(scaled, type: .png, quality: nil) else { throw ShrinkError.encodeFailed }
            data = encoded
        } else {
            let original = url.pathExtension.lowercased()
            ext = (original == "jpeg") ? "jpeg" : "jpg"
            let opaque = flattenedOnWhite(scaled) ?? scaled
            let q = min(max(quality, 0.05), 1.0)
            guard let encoded = encode(opaque, type: .jpeg, quality: q) else { throw ShrinkError.encodeFailed }
            data = encoded
        }

        return Output(
            data: data,
            fileName: "\(baseName)-small.\(ext)",
            fileExtension: ext,
            originalBytes: originalBytes,
            originalWidth: srcW,
            originalHeight: srcH,
            width: scaled.width,
            height: scaled.height,
            resized: target < longest,
            keptPNG: usesAlpha
        )
    }

    // MARK: - Helpers

    static func encode(_ image: CGImage, type: UTType, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// True if at least one pixel is not fully opaque.
    static func hasTransparentPixels(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = ctx.data
        else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var i = 3
        let end = w * h * 4
        while i < end {
            if pixels[i] != 255 { return true }
            i += 4
        }
        return false
    }

    /// Renders the image onto an opaque white RGB canvas (JPEG has no alpha channel).
    static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        let space: CGColorSpace
        if let cs = image.colorSpace, cs.model == .rgb { space = cs } else { space = CGColorSpace(name: CGColorSpace.sRGB)! }
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
