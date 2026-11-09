//
//  OCRService.swift
//  TwoTabs Notch - Smart Shelf
//
//  Text recognition (Vision) for images and the first pages of PDFs.
//  No app dependencies; synchronous and CPU heavy, call it off the main thread.
//

import Foundation
import AppKit
import Vision
import PDFKit
import ImageIO
import UniformTypeIdentifiers

enum OCRService {
    static let maxPDFPages = 10
    static let preferredLanguages = ["en-US", "id-ID"]

    enum OCRError: LocalizedError {
        case unreadable
        var errorDescription: String? { "The file could not be read for text recognition." }
    }

    /// Recognizes text in an image file or a PDF (first `maxPDFPages` pages).
    /// - Parameter preferEmbeddedPDFText: use a PDF page's own text layer when it has one (faster, exact).
    static func recognizeText(at url: URL, preferEmbeddedPDFText: Bool = true) throws -> String {
        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let isPDF = (type?.conforms(to: .pdf) ?? false) || url.pathExtension.lowercased() == "pdf"
        if isPDF {
            return try recognizePDF(at: url, preferEmbeddedText: preferEmbeddedPDFText)
        }
        guard let image = loadImage(at: url) else { throw OCRError.unreadable }
        return try recognize(cgImage: image)
    }

    static func recognize(cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let languages = supportedPreferredLanguages(for: request), !languages.isEmpty {
            request.recognitionLanguages = languages
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// The preferred languages that this Vision revision supports, or nil to keep Vision's default.
    static func supportedPreferredLanguages(for request: VNRecognizeTextRequest) -> [String]? {
        guard let supported = try? request.supportedRecognitionLanguages() else { return nil }
        let wanted = preferredLanguages.filter { supported.contains($0) }
        return wanted.isEmpty ? nil : wanted
    }

    static func recognizePDF(at url: URL, preferEmbeddedText: Bool) throws -> String {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { throw OCRError.unreadable }
        var pages: [String] = []
        for index in 0..<min(doc.pageCount, maxPDFPages) {
            guard let page = doc.page(at: index) else { continue }
            if preferEmbeddedText,
               let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !embedded.isEmpty {
                pages.append(embedded)
                continue
            }
            if let image = render(page: page) {
                let text = try recognize(cgImage: image)
                if !text.isEmpty { pages.append(text) }
            }
        }
        return pages.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Renders a PDF page to a bitmap with a ~2400px long side, on white.
    static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(4.0, max(1.0, 2400.0 / max(bounds.width, bounds.height)))
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}
