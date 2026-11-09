//
//  ShelfSelectionModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import Foundation
import Combine

private let _shelfTypeAnchor: Bool = {
    _ = String(describing: ShelfItem.self)
    return true
}()

@MainActor
final class ShelfSelectionModel: ObservableObject {
    static let shared = ShelfSelectionModel()

    @Published private(set) var selectedIDs: Set<UUID> = [] {
        didSet { updateSelectionOrder(previous: oldValue) }
    }

    /// TwoTabs: IDs in the order they were selected (used e.g. for merging PDFs in click order).
    private(set) var selectionOrder: [UUID] = []

    private func updateSelectionOrder(previous: Set<UUID>) {
        selectionOrder.removeAll { !selectedIDs.contains($0) }
        let added = selectedIDs.subtracting(previous)
        guard !added.isEmpty else { return }
        // Several IDs at once (shift-range): keep their shelf order.
        let shelfOrder = ShelfStateViewModel.shared.items.map(\.id)
        selectionOrder.append(contentsOf: shelfOrder.filter { added.contains($0) })
        selectionOrder.append(contentsOf: added.filter { !shelfOrder.contains($0) })
    }

    /// Selected items in selection (click) order rather than shelf order.
    func orderedSelectedItems(in allItems: [ShelfItem]) -> [ShelfItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selectionOrder.compactMap { byID[$0] }
    }

    // Anchor for shift-range selection
    private var lastAnchorID: UUID? = nil

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    var hasSelection: Bool { !selectedIDs.isEmpty }

    var firstSelectedItem: ShelfItem? {
        guard let firstID = selectedIDs.first else { return nil }
        return ShelfStateViewModel.shared.items.first(where: { $0.id == firstID })
    }

    func selectedItems(in allItems: [ShelfItem]) -> [ShelfItem] {
        allItems.filter { selectedIDs.contains($0.id) }
    }

    func selectSingle(_ item: ShelfItem) {
        selectedIDs = [item.id]
        lastAnchorID = item.id
    }

    func toggle(_ item: ShelfItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        lastAnchorID = item.id
    }

    func shiftSelect(to item: ShelfItem, in allItems: [ShelfItem]) {
        // Determine anchor
        let anchorID = lastAnchorID ?? selectedIDs.first ?? item.id
        guard let startIndex = allItems.firstIndex(where: { $0.id == anchorID }),
              let endIndex = allItems.firstIndex(where: { $0.id == item.id }) else {
            // Fallback to single select if indices not found
            return selectSingle(item)
        }
        let lower = min(startIndex, endIndex)
        let upper = max(startIndex, endIndex)
        let rangeIDs = allItems[lower...upper].map { $0.id }
        selectedIDs = Set(rangeIDs)
    }

    func clear() {
        selectedIDs.removeAll()
        lastAnchorID = nil
    }

    // Keep anchor sane if items array changed drastically (optional helper)
    func ensureValidAnchor(in allItems: [ShelfItem]) {
        if let anchor = lastAnchorID, !allItems.contains(where: { $0.id == anchor }) {
            lastAnchorID = selectedIDs.first
        }
    }

    @Published private(set) var isDragging: Bool = false

    func beginDrag() {
        isDragging = true
    }

    func endDrag() {
        isDragging = false
    }
}
