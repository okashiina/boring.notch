//
//  SmartShelfActions.swift
//  TwoTabs Notch - Smart Shelf
//
//  What the shelf's quick-action bar and the extra context-menu items actually do.
//  Every result is added back to the shelf as a new temporary item (like Compress does).
//

import AppKit
import Defaults
import Foundation
import UniformTypeIdentifiers

/// The shelf selection, resolved to URLs and sorted into the kinds the actions care about.
struct SmartShelfSelection: Equatable {
    /// All selected file items, in selection order (folders included).
    var fileURLs: [URL] = []
    var imageURLs: [URL] = []
    var pdfURLs: [URL] = []
    /// Regular files only (no folders).
    var uploadableURLs: [URL] = []
    /// Images and PDFs, in selection order.
    var textSourceURLs: [URL] = []

    static let empty = SmartShelfSelection()

    var canShrink: Bool { !imageURLs.isEmpty }
    var canConvert: Bool { imageURLs.count == 1 }
    var canRemoveBackground: Bool { imageURLs.count == 1 }
    var canCopyText: Bool { !textSourceURLs.isEmpty }
    var canMakePDF: Bool { !imageURLs.isEmpty }
    var canMergePDFs: Bool { pdfURLs.count >= 2 }
    var canZip: Bool { !fileURLs.isEmpty }
    var canUpload: Bool { !uploadableURLs.isEmpty }

    @MainActor
    static func current() -> SmartShelfSelection {
        let items = ShelfSelectionModel.shared.orderedSelectedItems(in: ShelfStateViewModel.shared.items)
        var result = SmartShelfSelection()
        for item in items {
            guard case .file = item.kind, let url = ShelfStateViewModel.shared.resolveFileURL(for: item) else { continue }
            let values = url.accessSecurityScopedResource { scoped in
                try? scoped.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
            }
            result.fileURLs.append(url)
            if values?.isDirectory == true { continue }
            result.uploadableURLs.append(url)
            let type = values?.contentType
            if type?.conforms(to: .image) == true {
                result.imageURLs.append(url)
                result.textSourceURLs.append(url)
            } else if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
                result.pdfURLs.append(url)
                result.textSourceURLs.append(url)
            }
        }
        return result
    }
}

@MainActor
final class SmartShelfActions {
    static let shared = SmartShelfActions()

    enum MenuTitle {
        static let shrink = "Shrink Image"
        static let copyText = "Copy Text (OCR)"
        static let mergePDFs = "Merge PDFs"
        static let upload = "Upload & Copy Link"
    }

    private let feedback = SmartShelfFeedback.shared
    /// Keeps the view model alive while the (modal) Convert dialog runs.
    private var convertHost: ShelfItemViewModel?

    private init() {}

    var isBusy: Bool { feedback.isBusy }

    /// Handles the extra context-menu titles. Returns false for titles it does not own.
    @discardableResult
    func performMenuTitle(_ title: String) -> Bool {
        switch title {
        case MenuTitle.shrink: shrink()
        case MenuTitle.copyText: copyText()
        case MenuTitle.mergePDFs: mergePDFs()
        case MenuTitle.upload: upload()
        default: return false
        }
        return true
    }

    // MARK: - Shrink

    func shrink() {
        let info = SmartShelfSelection.current()
        guard info.canShrink, !feedback.isBusy else { return }
        let maxDimension = Defaults[.smartShelfShrinkMaxDimension]
        let quality = Defaults[.smartShelfShrinkQuality]
        feedback.begin("Shrinking…")

        Task { @MainActor in
            let results: [Result<ImageShrinker.Output, Error>] = await info.imageURLs.accessSecurityScopedResources { urls in
                await Task.detached(priority: .userInitiated) {
                    urls.map { url in
                        Result { try ImageShrinker.shrink(url: url, maxDimension: maxDimension, quality: quality) }
                    }
                }.value
            }

            var before = 0, after = 0, added = 0, skipped = 0
            var lastName = ""
            var firstError: String?
            for result in results {
                switch result {
                case .failure(let error):
                    firstError = firstError ?? error.localizedDescription
                case .success(let out):
                    // Nothing gained: same pixels and not smaller.
                    if !out.resized && out.outputBytes >= out.originalBytes {
                        skipped += 1
                        continue
                    }
                    guard let tempURL = await TemporaryFileStorageService.shared.createTempFile(
                        for: .data(out.data, suggestedName: out.fileName)),
                          addTemporaryFile(tempURL) else {
                        firstError = firstError ?? "The smaller copy could not be saved."
                        continue
                    }
                    added += 1
                    before += out.originalBytes
                    after += out.outputBytes
                    lastName = out.fileName
                }
            }

            if added == 1 {
                feedback.succeed("\(lastName): \(SmartShelfFormat.bytes(before)) → \(SmartShelfFormat.bytes(after))")
            } else if added > 1 {
                feedback.succeed("Shrunk \(added) images: \(SmartShelfFormat.bytes(before)) → \(SmartShelfFormat.bytes(after))")
            } else if let firstError {
                feedback.fail("Shrink failed: \(firstError)")
            } else if skipped > 0 {
                feedback.info("Already small, nothing to shrink")
            } else {
                feedback.dismiss()
            }
        }
    }

    // MARK: - Convert (existing dialog, now with WebP)

    func convert() {
        let info = SmartShelfSelection.current()
        guard info.canConvert,
              let item = ShelfSelectionModel.shared
                .orderedSelectedItems(in: ShelfStateViewModel.shared.items)
                .first(where: { $0.fileURL.map { info.imageURLs.contains($0) } ?? false })
        else { return }
        let host = ShelfItemViewModel(item: item)
        convertHost = host
        host.presentConvertImageDialog()
        convertHost = nil
    }

    // MARK: - Remove background

    func removeBackground() {
        let info = SmartShelfSelection.current()
        guard info.canRemoveBackground, let imageURL = info.imageURLs.first, !feedback.isBusy else { return }
        feedback.begin("Removing background…")
        Task { @MainActor in
            do {
                let resultURL = try await imageURL.accessSecurityScopedResource { url in
                    try await ImageProcessingService.shared.removeBackground(from: url)
                }
                if let resultURL, addTemporaryFile(resultURL) {
                    feedback.succeed("Background removed")
                } else {
                    feedback.fail("Background removal produced no file.")
                }
            } catch {
                feedback.fail("Background removal failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Copy text (OCR)

    func copyText() {
        let info = SmartShelfSelection.current()
        guard info.canCopyText, !feedback.isBusy else { return }
        feedback.begin("Reading text…")

        Task { @MainActor in
            let result: Result<[String], Error> = await info.textSourceURLs.accessSecurityScopedResources { urls in
                await Task.detached(priority: .userInitiated) {
                    Result { try urls.map { try OCRService.recognizeText(at: $0) } }
                }.value
            }
            switch result {
            case .failure(let error):
                feedback.fail("Text recognition failed: \(error.localizedDescription)")
            case .success(let texts):
                let text = texts
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                guard !text.isEmpty else {
                    feedback.info("No text found", symbol: "text.magnifyingglass")
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                ShelfStateViewModel.shared.add([ShelfItem(kind: .text(string: text), isTemporary: false)])
                feedback.succeed("Copied \(SmartShelfFormat.count(text.count)) characters", symbol: "doc.on.clipboard.fill")
            }
        }
    }

    // MARK: - Make PDF (images -> PDF, same as the menu's Create PDF)

    func makePDF() {
        let info = SmartShelfSelection.current()
        guard info.canMakePDF, !feedback.isBusy else { return }
        feedback.begin("Creating PDF…")
        Task { @MainActor in
            do {
                let resultURL = try await info.imageURLs.accessSecurityScopedResources { urls in
                    try await ImageProcessingService.shared.createPDF(from: urls)
                }
                if let resultURL, addTemporaryFile(resultURL) {
                    feedback.succeed("PDF created from \(info.imageURLs.count) image\(info.imageURLs.count == 1 ? "" : "s")")
                } else {
                    feedback.fail("PDF creation produced no file.")
                }
            } catch {
                feedback.fail("PDF creation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Merge PDFs

    func mergePDFs() {
        let info = SmartShelfSelection.current()
        guard info.canMergePDFs, !feedback.isBusy else { return }
        feedback.begin("Merging PDFs…")
        let firstName = info.pdfURLs.first?.deletingPathExtension().lastPathComponent ?? "merged"

        Task { @MainActor in
            let result: Result<PDFMerger.Merged, Error> = await info.pdfURLs.accessSecurityScopedResources { urls in
                await Task.detached(priority: .userInitiated) {
                    Result { try PDFMerger.merge(urls: urls) }
                }.value
            }
            switch result {
            case .failure(let error):
                feedback.fail("Merge failed: \(error.localizedDescription)")
            case .success(let merged):
                guard let tempURL = await TemporaryFileStorageService.shared.createTempFile(
                    for: .data(merged.data, suggestedName: "\(firstName)-merged.pdf")),
                      addTemporaryFile(tempURL) else {
                    feedback.fail("The merged PDF could not be saved.")
                    return
                }
                feedback.succeed("Merged \(merged.documentCount) PDFs, \(merged.pageCount) pages")
            }
        }
    }

    // MARK: - Zip

    func zip() {
        let info = SmartShelfSelection.current()
        guard info.canZip, !feedback.isBusy else { return }
        feedback.begin("Compressing…")
        Task { @MainActor in
            let zipURL = await info.fileURLs.accessSecurityScopedResources { urls in
                await TemporaryFileStorageService.shared.createZip(from: urls)
            }
            if let zipURL, addTemporaryFile(zipURL) {
                feedback.succeed("Created \(zipURL.lastPathComponent)")
            } else {
                feedback.fail("Compression failed.")
            }
        }
    }

    // MARK: - Upload

    func upload() {
        let info = SmartShelfSelection.current()
        guard info.canUpload, !feedback.isBusy else { return }
        let target = SmartShelfUploadHost.currentTarget
        let files = info.uploadableURLs

        // Size check up front so nothing is sent if any file is too big.
        for url in files {
            let size = url.accessSecurityScopedResource { scoped in
                (try? scoped.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
            }
            do {
                try target.checkSize(size ?? 0, fileName: url.lastPathComponent)
            } catch {
                feedback.fail(error.localizedDescription)
                return
            }
        }

        feedback.begin("Uploading to \(target.name)…")
        Task { @MainActor in
            var links: [URL] = []
            var failure: String?
            for (index, url) in files.enumerated() {
                let label = files.count > 1 ? "Uploading \(index + 1)/\(files.count)" : "Uploading"
                feedback.update("\(label) \(url.lastPathComponent)", progress: 0)
                do {
                    let link = try await url.accessSecurityScopedResource { scoped in
                        try await UploadService.upload(fileURL: scoped, target: target) { fraction in
                            Task { @MainActor in
                                SmartShelfFeedback.shared.update("\(label) \(url.lastPathComponent) \(Int(fraction * 100))%",
                                                                 progress: fraction)
                            }
                        }
                    }
                    links.append(link)
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }

            if !links.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(links.map(\.absoluteString).joined(separator: "\n"), forType: .string)
            }
            if let failure {
                let done = links.isEmpty ? "" : " (\(links.count) link\(links.count == 1 ? "" : "s") copied)"
                feedback.fail("Upload failed: \(failure)\(done)")
            } else {
                let what = links.count == 1 ? "Link copied" : "\(links.count) links copied"
                feedback.succeed("\(what) (\(target.lifetimeNote))", symbol: "link.circle.fill")
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func addTemporaryFile(_ url: URL) -> Bool {
        guard let bookmark = try? Bookmark(url: url) else { return false }
        ShelfStateViewModel.shared.add([ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true)])
        return true
    }
}
