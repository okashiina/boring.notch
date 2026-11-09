//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @ObservedObject private var bar = SmartShelfBarState.shared // TwoTabs
    @ObservedObject private var capturePeek = CapturePeekModel.shared // TwoTabs
    @State private var barVisible = false // TwoTabs
    private let spacing: CGFloat = 8

    var body: some View {
        // TwoTabs: the action strip gets its own row under the shelf panel; the notch grows to make room.
        VStack(spacing: 0) {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        SmartShelfActionBar()
            .frame(height: barVisible ? SmartShelfBarMetrics.extraHeight : 0, alignment: .bottom)
            .clipped()
            .opacity(barVisible ? 1 : 0)
            .allowsHitTesting(barVisible)
        }
        .onChange(of: bar.isActive, initial: true) { _, active in setBarVisible(active) }
        // Something (e.g. a drag entering the notch region) re-opened the notch at its base size: re-apply.
        .onChange(of: vm.notchSize) { _, size in
            if barVisible, vm.notchState == .open, size.height < openNotchSize.height + SmartShelfBarMetrics.extraHeight {
                setBarVisible(true, force: true)
            }
        }
        .onDisappear {
            // Leaving the shelf tab (not closing the notch) must give the extra height back.
            if vm.notchState == .open { vm.notchSize = openNotchSize }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    /// TwoTabs: show/hide the strip and grow/shrink the open notch in one transaction, so the shelf panel
    /// keeps its height while the notch moves.
    private func setBarVisible(_ visible: Bool, force: Bool = false) {
        guard force || visible != barVisible else { return }
        withAnimation(.smooth(duration: 0.28)) {
            barVisible = visible
            if vm.notchState == .open {
                vm.notchSize = CGSize(
                    width: openNotchSize.width,
                    height: openNotchSize.height + (visible ? SmartShelfBarMetrics.extraHeight : 0))
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clearFromEmptySpaceTap() } // TwoTabs: items are not "empty space"
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollViewReader { proxy in // TwoTabs: scroll a fresh capture into view
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                                .id(item.id) // TwoTabs
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onChange(of: capturePeek.reveal, initial: true) { _, request in // TwoTabs
                    guard let request else { return }
                    DispatchQueue.main.async { withAnimation(.smooth) { proxy.scrollTo(request.itemID, anchor: .center) } }
                }
                }
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
