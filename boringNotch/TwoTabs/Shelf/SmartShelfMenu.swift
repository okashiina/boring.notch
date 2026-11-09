//
//  SmartShelfMenu.swift
//  TwoTabs Notch - Smart Shelf
//
//  Extra right-click items. Called from ShelfItemViewModel.presentContextMenu before the
//  menu's targets are wired, so the items below get the same target/action as the others.
//

import AppKit

enum SmartShelfMenu {
    @MainActor
    static func appendItems(to menu: NSMenu) {
        let selection = SmartShelfSelection.current()
        var items: [NSMenuItem] = []

        func make(_ title: String, symbol: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }

        if selection.canShrink {
            items.append(make(SmartShelfActions.MenuTitle.shrink, symbol: "arrow.down.right.and.arrow.up.left"))
        }
        if selection.canCopyText {
            items.append(make(SmartShelfActions.MenuTitle.copyText, symbol: "text.viewfinder"))
        }
        if selection.canMergePDFs {
            items.append(make(SmartShelfActions.MenuTitle.mergePDFs, symbol: "arrow.triangle.merge"))
        }
        if selection.canUpload {
            items.append(make(SmartShelfActions.MenuTitle.upload, symbol: "icloud.and.arrow.up"))
        }
        guard !items.isEmpty else { return }

        if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(NSMenuItem.separator()) }
        items.forEach { menu.addItem($0) }
        menu.addItem(NSMenuItem.separator())
    }
}
