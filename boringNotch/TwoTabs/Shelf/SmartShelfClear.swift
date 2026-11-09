//
//  SmartShelfClear.swift
//  TwoTabs Notch - Smart Shelf
//
//  "Clear all": removes every shelf item (button + global shortcut) with a 6 s Undo.
//
//  Shelf items are references (security-scoped bookmarks) to the user's files, so clearing never touches
//  the originals. Only items the app itself created in the temp directory (isTemporary: shrunk, zipped,
//  merged copies) are deleted, through the same ShelfItem.cleanupStoredData() path as "Remove", but after
//  the undo window so Undo can bring them back intact.
//

import Foundation
import KeyboardShortcuts

@MainActor
enum SmartShelfClear {
    static let undoWindow: TimeInterval = 6

    private static var pending: [ShelfItem] = []
    private static var finalizeTask: Task<Void, Never>?

    static var shortcutHint: String {
        KeyboardShortcuts.getShortcut(for: .clearShelf)?.description ?? ""
    }

    static func perform() {
        let shelf = ShelfStateViewModel.shared
        guard !shelf.isEmpty else { return }
        // A previous clear still waiting for its undo window is final now.
        finalize()
        let removed = shelf.detachAll()
        ShelfSelectionModel.shared.clear()
        pending = removed
        let count = removed.count
        SmartShelfFeedback.shared.succeed(
            count == 1 ? "Cleared 1 item" : "Cleared \(count) items",
            symbol: "trash.circle.fill", duration: undoWindow,
            actionTitle: "Undo", action: { undo() })
        finalizeTask = Task {
            try? await Task.sleep(for: .seconds(undoWindow))
            guard !Task.isCancelled else { return }
            finalize()
        }
    }

    static func undo() {
        guard !pending.isEmpty else { return }
        finalizeTask?.cancel()
        let items = pending
        pending = []
        ShelfStateViewModel.shared.restore(items)
        SmartShelfFeedback.shared.info(
            items.count == 1 ? "Restored 1 item" : "Restored \(items.count) items",
            symbol: "arrow.uturn.backward.circle.fill", duration: 3)
    }

    private static func finalize() {
        finalizeTask?.cancel()
        let items = pending
        pending = []
        for item in items { item.cleanupStoredData() }
    }
}
