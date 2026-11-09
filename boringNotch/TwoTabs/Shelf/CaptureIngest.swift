//
//  CaptureIngest.swift
//  TwoTabs Notch - Smart Shelf
//
//  The one place a finished capture (screenshot file, screen recording, clipboard image) becomes a shelf
//  item: adds it, remembers it as "auto-added", drops the oldest auto-added ones past the keep limit,
//  and tells the closed notch to show its preview.
//
//  Pruning only ever removes shelf entries that were auto-added. Originals on disk are never deleted;
//  the only file that can be deleted is a clipboard PNG this app wrote into its own temp folder.
//

import AppKit
import Defaults
import Foundation

/// What the closed-notch preview shows.
struct CaptureEvent: Equatable, Identifiable {
    enum Kind: Equatable {
        case screenshot
        case recording(duration: TimeInterval?)
        case copiedImage
    }

    let id = UUID()
    let itemID: UUID
    let kind: Kind
    let thumbnail: NSImage?

    static func == (a: CaptureEvent, b: CaptureEvent) -> Bool { a.id == b.id }

    var label: String {
        switch kind {
        case .screenshot: return "Screenshot"
        case .copiedImage: return "Copied image"
        case .recording(let duration):
            if let duration, duration.isFinite, duration > 0 { return "Recording " + CaptureLabel.duration(duration) }
            return "Recording"
        }
    }

    var isRecording: Bool {
        if case .recording = kind { return true }
        return false
    }
}

@MainActor
enum CaptureIngest {
    // MARK: - Entry points

    /// A screenshot or recording file that appeared in the watched folder. Waits until it is finished.
    static func addFile(_ url: URL, kind: CaptureFileKind) async {
        switch kind {
        case .image:
            guard await CaptureFileStability.waitUntilFinalized(url, pollInterval: 0.4, stablePolls: 1, timeout: 20) else { return }
        case .video:
            // Stable for ~1.5 s and the movie opens (its index is written when the recording is finalized).
            var ready = await CaptureFileStability.waitUntilFinalized(
                url, pollInterval: 0.5, stablePolls: 3, timeout: 60, finalCheck: CaptureMedia.movieIsPlayable)
            if !ready {
                // Not playable for this system's codecs, but the file stopped growing: still hand it over.
                ready = await CaptureFileStability.waitUntilFinalized(url, pollInterval: 0.5, stablePolls: 3, timeout: 10)
            }
            guard ready else { return }
        }
        guard let bookmark = try? Bookmark(url: url) else { return }
        let item = ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: false)
        let event: CaptureEvent.Kind
        let thumbnail: NSImage?
        switch kind {
        case .image:
            event = .screenshot
            thumbnail = await CaptureMedia.imageThumbnail(url)
        case .video:
            let result = await CaptureMedia.videoInfo(url)
            event = .recording(duration: result.duration)
            thumbnail = result.thumbnail
        }
        register(item, kind: event, thumbnail: thumbnail)
    }

    /// A new image on the pasteboard: written as a PNG into the temp folder and added as a temporary item.
    static func addClipboardImage(_ image: ClipboardImage) async {
        let name = "Clipboard \(Self.timestamp()).png"
        guard let url = await TemporaryFileStorageService.shared.createTempFile(
            for: .data(image.png, suggestedName: name)) else { return }
        guard let bookmark = try? Bookmark(url: url) else {
            TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
            return
        }
        let item = ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true)
        let thumbnail = await CaptureMedia.imageThumbnail(url)
        register(item, kind: .copiedImage, thumbnail: thumbnail)
    }

    // MARK: - Shelf bookkeeping

    private static func register(_ item: ShelfItem, kind: CaptureEvent.Kind, thumbnail: NSImage?) {
        let shelf = ShelfStateViewModel.shared
        shelf.add([item])
        // add() skips duplicates (the same file already on the shelf): then there is nothing new to announce.
        guard shelf.items.contains(where: { $0.id == item.id }) else {
            item.cleanupStoredData()
            return
        }
        var ids = Defaults[.smartShelfAutoCaptureIDs].compactMap(UUID.init(uuidString:))
        ids.append(item.id)
        Defaults[.smartShelfAutoCaptureIDs] = ids.map(\.uuidString)
        applyKeepLimit()

        let event = CaptureEvent(itemID: item.id, kind: kind, thumbnail: thumbnail)
        SmartShelfFeedback.shared.info("\(event.label) added to shelf", symbol: "camera.viewfinder")
        CapturePeekModel.shared.announce(event)
    }

    /// Drops the oldest auto-added captures from the shelf when there are more than the keep limit.
    static func applyKeepLimit() {
        let shelf = ShelfStateViewModel.shared
        let order = Defaults[.smartShelfAutoCaptureIDs].compactMap(UUID.init(uuidString:))
        let result = CapturePruner.prune(
            order: order, present: Set(shelf.items.map(\.id)), keep: Defaults[.smartShelfCaptureKeepCount])
        for id in result.remove {
            // remove() deletes nothing but this app's own temp files (isTemporary), never the original capture.
            if let item = shelf.items.first(where: { $0.id == id }) { shelf.remove(item) }
        }
        Defaults[.smartShelfAutoCaptureIDs] = result.kept.map(\.uuidString)
    }

    // MARK: - Metadata

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }
}
