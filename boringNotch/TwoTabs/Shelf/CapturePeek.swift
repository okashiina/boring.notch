//
//  CapturePeek.swift
//  TwoTabs Notch - Smart Shelf
//
//  What the notch does when a capture lands:
//   - closed: a small thumbnail + label ("Screenshot", "Recording 0:12") for ~3 s next to the camera cut-out
//   - then, when the notch is opened within a short window (hover, click or gesture), it opens straight on
//     the Shelf tab with that capture selected, so the action strip (Shrink, Upload, ...) is ready.
//
//  It deliberately does not use `BoringViewCoordinator.sneakPeek`: that one blocks open-on-hover while it is
//  showing and is gated by the HUD-replacement setting.
//
//  Also owns the one-time "Let TwoTabs Notch catch your screenshots?" prompt, shown in the shelf's status
//  line the first time the shelf is on screen without a screenshot folder.
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class CapturePeekModel: ObservableObject {
    static let shared = CapturePeekModel()

    /// How long the closed-notch preview stays.
    static let peekDuration: TimeInterval = 3
    /// How long after a capture opening the notch still jumps to it.
    static let jumpWindow: TimeInterval = 12

    struct RevealRequest: Equatable {
        let itemID: UUID
        let token = UUID()
    }

    @Published private(set) var current: CaptureEvent?
    /// The shelf scrolls this item into view when it changes.
    @Published private(set) var reveal: RevealRequest?

    private var hideTask: Task<Void, Never>?
    private var pending: (itemID: UUID, expires: Date)?
    private var notchIsOpen = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        BoringViewCoordinator.shared.$currentView
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] view in if view == .shelf { self?.shelfTabSelected() } }
            .store(in: &cancellables)
    }

    // MARK: - Capture landed

    func announce(_ event: CaptureEvent) {
        guard Defaults[.smartShelfCapturePreview] else { return }
        pending = (event.itemID, Date().addingTimeInterval(Self.jumpWindow))
        guard !notchIsOpen else { return } // the notch is open: the shelf is right there
        hideTask?.cancel()
        withAnimation(.smooth) { current = event }
        let id = event.id
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.peekDuration))
            guard !Task.isCancelled else { return }
            self?.hide(ifShowing: id)
        }
    }

    private func hide(ifShowing id: UUID) {
        guard current?.id == id else { return }
        withAnimation(.smooth) { current = nil }
    }

    // MARK: - Notch opened / closed (called from BoringViewModel.open() and close())

    func notchWillOpen() {
        notchIsOpen = true
        hideTask?.cancel()
        if current != nil { current = nil }
        if let pending, pending.expires > Date(),
           let item = ShelfStateViewModel.shared.items.first(where: { $0.id == pending.itemID }) {
            self.pending = nil
            BoringViewCoordinator.shared.currentView = .shelf
            ShelfSelectionModel.shared.selectSingle(item)
            reveal = RevealRequest(itemID: item.id)
        }
        // Give the shelf a moment to appear, then offer the folder prompt if it is on screen.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.promptForFolderIfNeeded()
        }
    }

    func notchDidClose() {
        notchIsOpen = false
        reveal = nil
    }

    /// The tab changed while the notch is open (the shelf tab may just have been selected).
    func shelfTabSelected() {
        guard notchIsOpen else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.promptForFolderIfNeeded()
        }
    }

    // MARK: - One-time folder prompt

    static var needsFolder: Bool {
        Defaults[.smartShelfScreenshotsEnabled] && Defaults[.smartShelfScreenshotFolderBookmark] == nil
    }

    private func promptForFolderIfNeeded() {
        guard notchIsOpen, BoringViewCoordinator.shared.currentView == .shelf,
              Self.needsFolder, !Defaults[.smartShelfFolderPromptShown] else { return }
        Defaults[.smartShelfFolderPromptShown] = true
        SmartShelfFeedback.shared.info(
            "Let TwoTabs Notch catch your screenshots?", symbol: "camera.viewfinder", duration: 30,
            actionTitle: "Choose screenshot folder…", action: { Self.chooseFolderFromNotch() })
    }

    /// Opens the folder picker (prefilled with the real screenshot location) without the notch closing under it.
    static func chooseFolderFromNotch() {
        SmartShelfFeedback.shared.dismiss()
        if ScreenshotWatcher.chooseFolder() {
            Defaults[.smartShelfScreenshotsEnabled] = true
            SmartShelfFeedback.shared.info(
                "Catching screenshots and recordings from \(Defaults[.smartShelfScreenshotFolderPath].map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "your folder")",
                symbol: "checkmark.circle.fill", duration: 5)
        }
    }
}

// MARK: - Closed notch view

/// Thumbnail on the left of the camera cut-out, label on the right. Both sides have the same width so the
/// cut-out stays centered.
struct CapturePeekClosedActivity: View {
    let event: CaptureEvent
    @EnvironmentObject var vm: BoringViewModel

    private let sideWidth: CGFloat = 92

    var body: some View {
        let height = vm.effectiveClosedNotchHeight
        let thumb = max(0, height - 10)
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                thumbnail(size: thumb)
            }
            .frame(width: sideWidth, alignment: .trailing)
            .padding(.trailing, 6)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, vm.closedNotchSize.width - cornerRadiusInsets.closed.top))

            HStack(spacing: 5) {
                if event.isRecording {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                }
                Text(event.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(width: sideWidth, alignment: .leading)
            .padding(.leading, 6)
        }
        .frame(height: height, alignment: .center)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.label + " added to shelf")
    }

    @ViewBuilder
    private func thumbnail(size: CGFloat) -> some View {
        if let image = event.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        } else {
            Image(systemName: event.isRecording ? "video.fill" : "camera.viewfinder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: size, height: size)
        }
    }
}
