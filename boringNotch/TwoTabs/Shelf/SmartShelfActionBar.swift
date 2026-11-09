//
//  SmartShelfActionBar.swift
//  TwoTabs Notch - Smart Shelf
//
//  Compact row of icon buttons that floats at the top of the shelf panel while items are selected.
//

import SwiftUI

struct SmartShelfActionBar: View {
    @ObservedObject private var selection = ShelfSelectionModel.shared
    @ObservedObject private var shelf = ShelfStateViewModel.shared
    @ObservedObject private var feedback = SmartShelfFeedback.shared
    @State private var info = SmartShelfSelection.empty

    private var showButtons: Bool { selection.hasSelection && info != .empty }

    var body: some View {
        Group {
            if showButtons || feedback.message != nil {
                HStack(spacing: 2) {
                    if showButtons { buttons }
                    if showButtons, feedback.message != nil { divider }
                    if let message = feedback.message { statusView(message) }
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.82))
                        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                )
                .padding(.top, 1)
                .padding(.horizontal, 8)
                // Swallow taps so the panel's "tap to deselect" does not fire from the bar.
                .onTapGesture {}
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showButtons)
        .animation(.easeInOut(duration: 0.15), value: feedback.message)
        .onAppear(perform: refresh)
        .onChange(of: selection.selectedIDs) { refresh() }
        .onChange(of: shelf.items.map(\.id)) { refresh() }
    }

    private func refresh() {
        info = selection.hasSelection ? SmartShelfSelection.current() : .empty
    }

    @ViewBuilder
    private var buttons: some View {
        let actions = SmartShelfActions.shared
        barButton("arrow.down.right.and.arrow.up.left", "Shrink (max side and quality from Settings)", info.canShrink, actions.shrink)
        barButton("arrow.triangle.2.circlepath", "Convert image…", info.canConvert, actions.convert)
        barButton("wand.and.stars", "Remove background", info.canRemoveBackground, actions.removeBackground)
        barButton("text.viewfinder", "Copy text (OCR)", info.canCopyText, actions.copyText)
        barButton("doc.richtext", "Make PDF from images", info.canMakePDF, actions.makePDF)
        barButton("arrow.triangle.merge", "Merge PDFs", info.canMergePDFs, actions.mergePDFs)
        barButton("doc.zipper", "Zip", info.canZip, actions.zip)
        barButton("icloud.and.arrow.up", "Upload and copy public link", info.canUpload, actions.upload)
    }

    @ViewBuilder
    private func barButton(_ symbol: String, _ help: String, _ visible: Bool, _ action: @escaping () -> Void) -> some View {
        if visible {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BarButtonStyle())
            .disabled(feedback.isBusy)
            .help(help)
            .accessibilityLabel(help)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 12).padding(.horizontal, 4)
    }

    private func statusView(_ message: SmartShelfFeedback.Message) -> some View {
        HStack(spacing: 5) {
            if feedback.isBusy, let progress = feedback.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 34)
                    .tint(.white)
            } else if feedback.isBusy {
                ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12)
            } else {
                Image(systemName: message.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color(for: message.style))
            }
            Text(message.text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(message.style == .error ? Color.red.opacity(0.95) : Color.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.trailing, 2)
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
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(isEnabled ? 0.92 : 0.35))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.22 : 0))
            )
    }
}
