//
//  SmartShelfActionBar.swift
//  TwoTabs Notch - Smart Shelf
//
//  The smart shelf's action strip. It lives in its OWN row under the shelf panel (ShelfView grows the
//  notch by `SmartShelfBarMetrics.extraHeight` while the strip is shown), so it never covers thumbnails
//  and the pointer can travel from a file to a button without leaving the notch.
//
//  The strip is stable: it stays while something is selected (or a status message is showing) and only
//  goes away when the selection is cleared (click on empty shelf space, the Deselect button) or the
//  notch closes.
//

import Combine
import SwiftUI

/// Sizes shared by the strip and by the places that have to make room for it.
enum SmartShelfBarMetrics {
    /// Strip height. Buttons are 30pt tall, so every hit target is at least 28x28pt.
    static let height: CGFloat = 38
    /// Gap between the shelf panel and the strip.
    static let gap: CGFloat = 6
    /// Height the open notch (and the window) grow by while the strip is shown.
    static var extraHeight: CGFloat { height + gap }
}

/// What the strip should show, derived from the shelf selection and the feedback line.
@MainActor
final class SmartShelfBarState: ObservableObject {
    static let shared = SmartShelfBarState()

    @Published private(set) var info = SmartShelfSelection.empty
    @Published private(set) var selectionCount = 0
    /// True while the strip should be visible: a selection with applicable actions, or a message.
    @Published private(set) var isActive = false

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let selection = ShelfSelectionModel.shared
        let shelf = ShelfStateViewModel.shared
        let feedback = SmartShelfFeedback.shared
        // The publishers fire before the value changes (willSet), so hop to the next main-queue turn
        // and read the settled state.
        Publishers.CombineLatest3(selection.$selectedIDs, shelf.$items, feedback.$message)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        let selection = ShelfSelectionModel.shared
        let newInfo = selection.hasSelection ? SmartShelfSelection.current() : .empty
        let count = selection.selectedIDs.count
        // The strip also stays up whenever the shelf holds items, so "Clear all" is always reachable.
        let active = newInfo != .empty || SmartShelfFeedback.shared.message != nil || !ShelfStateViewModel.shared.isEmpty
        if newInfo != info { info = newInfo }
        if count != selectionCount { selectionCount = count }
        if active != isActive { isActive = active }
    }
}

struct SmartShelfActionBar: View {
    @ObservedObject private var state = SmartShelfBarState.shared
    @ObservedObject private var feedback = SmartShelfFeedback.shared
    @ObservedObject private var shelf = ShelfStateViewModel.shared

    private enum LabelMode { case all, primary, none }

    private struct ActionSpec: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let help: String
        let primary: Bool
        let perform: () -> Void
    }

    private var specs: [ActionSpec] {
        let info = state.info
        let actions = SmartShelfActions.shared
        var list: [ActionSpec] = []
        if info.canShrink {
            list.append(.init(id: "shrink", symbol: "arrow.down.right.and.arrow.up.left", title: "Shrink",
                              help: "Shrink (max side and quality from Settings)", primary: true, perform: actions.shrink))
        }
        if info.canConvert {
            list.append(.init(id: "convert", symbol: "arrow.triangle.2.circlepath", title: "Convert",
                              help: "Convert image…", primary: false, perform: actions.convert))
        }
        if info.canRemoveBackground {
            list.append(.init(id: "removebg", symbol: "wand.and.stars", title: "Remove BG",
                              help: "Remove background", primary: false, perform: actions.removeBackground))
        }
        if info.canCopyText {
            list.append(.init(id: "ocr", symbol: "text.viewfinder", title: "Copy text",
                              help: "Copy text (OCR)", primary: true, perform: actions.copyText))
        }
        if info.canMakePDF {
            list.append(.init(id: "pdf", symbol: "doc.richtext", title: "PDF",
                              help: "Make PDF from images", primary: false, perform: actions.makePDF))
        }
        if info.canMergePDFs {
            list.append(.init(id: "merge", symbol: "arrow.triangle.merge", title: "Merge",
                              help: "Merge PDFs", primary: true, perform: actions.mergePDFs))
        }
        if info.canZip {
            list.append(.init(id: "zip", symbol: "doc.zipper", title: "Zip",
                              help: "Zip", primary: true, perform: actions.zip))
        }
        if info.canUpload {
            list.append(.init(id: "upload", symbol: "icloud.and.arrow.up", title: "Upload",
                              help: "Upload and copy public link", primary: true, perform: actions.upload))
        }
        return list
    }

    var body: some View {
        // Widest layout that fits the notch wins; the last one is the compact fallback.
        ViewThatFits(in: .horizontal) {
            row(labels: .all, showCount: true)
            row(labels: .primary, showCount: true)
            row(labels: .primary, showCount: false)
            row(labels: .none, showCount: false)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: SmartShelfBarMetrics.height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.top, SmartShelfBarMetrics.gap)
    }

    private func row(labels: LabelMode, showCount: Bool) -> some View {
        HStack(spacing: 2) {
            if showCount, state.selectionCount > 0 {
                Text(state.selectionCount == 1 ? "1 selected" : "\(state.selectionCount) selected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                dividerView
            }
            ForEach(specs) { spec in
                actionButton(spec, labelled: labels == .all || (labels == .primary && spec.primary))
            }
            Spacer(minLength: 4)
            if let message = feedback.message {
                statusView(message)
                    .padding(.horizontal, 4)
            }
            if state.selectionCount > 0 {
                deselectButton
            }
            if !shelf.isEmpty {
                clearAllButton(labelled: labels != .none)
            }
        }
    }

    private func clearAllButton(labelled: Bool) -> some View {
        Button(action: SmartShelfClear.perform) {
            HStack(spacing: 5) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18, height: 18)
                if labelled {
                    Text("Clear all")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, labelled ? 9 : 6)
            .frame(minWidth: 30, minHeight: 30)
        }
        .buttonStyle(BarButtonStyle())
        .disabled(feedback.isBusy)
        .help(SmartShelfClear.shortcutHint.isEmpty ? "Clear all" : "Clear all (\(SmartShelfClear.shortcutHint))")
        .accessibilityLabel("Clear all shelf items")
    }

    private func actionButton(_ spec: ActionSpec, labelled: Bool) -> some View {
        Button(action: spec.perform) {
            HStack(spacing: 5) {
                Image(systemName: spec.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18, height: 18)
                if labelled {
                    Text(spec.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, labelled ? 9 : 6)
            .frame(minWidth: 30, minHeight: 30)
        }
        .buttonStyle(BarButtonStyle())
        .disabled(feedback.isBusy)
        .help(spec.help)
        .accessibilityLabel(spec.help)
    }

    private var deselectButton: some View {
        Button {
            ShelfSelectionModel.shared.clear()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(BarButtonStyle())
        .help("Deselect (or click empty space in the shelf)")
        .accessibilityLabel("Deselect")
    }

    private var dividerView: some View {
        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 16).padding(.horizontal, 2)
    }

    private func statusView(_ message: SmartShelfFeedback.Message) -> some View {
        HStack(spacing: 6) {
            if feedback.isBusy, let progress = feedback.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 44)
                    .tint(.white)
            } else if feedback.isBusy {
                ProgressView().controlSize(.small).frame(width: 16, height: 16)
            } else {
                Image(systemName: message.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color(for: message.style))
            }
            Text(message.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(message.style == .error ? Color.red.opacity(0.95) : Color.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .truncationMode(.middle)
                .frame(maxWidth: 240, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            if let title = message.actionTitle, let action = message.action {
                Button(title, action: action)
                    .buttonStyle(BarButtonStyle())
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 30)
            }
        }
        .help(message.text)
    }

    private func color(for style: SmartShelfFeedback.Style) -> Color {
        switch style {
        case .info: return .white.opacity(0.8)
        case .success: return .green
        case .error: return .red
        }
    }
}

private struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BarButtonBody(configuration: configuration)
    }
}

/// Own view so the hover state can live in @State (a ButtonStyle itself cannot hold it).
private struct BarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(isEnabled ? 0.95 : 0.35))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
            .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
    }

    private var fillOpacity: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed { return 0.28 }
        return hovering ? 0.16 : 0
    }
}
