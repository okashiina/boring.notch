//
//  SmartShelfFeedback.swift
//  TwoTabs Notch - Smart Shelf
//
//  Transient status line shown in the action bar (progress, "Copied N characters", errors).
//

import Foundation
import SwiftUI

@MainActor
final class SmartShelfFeedback: ObservableObject {
    static let shared = SmartShelfFeedback()

    enum Style { case info, success, error }

    struct Message: Equatable {
        let id = UUID()
        let text: String
        let style: Style
        let symbol: String
        /// Optional trailing button (e.g. "Undo").
        var actionTitle: String? = nil
        var action: (@MainActor () -> Void)? = nil

        static func == (a: Message, b: Message) -> Bool { a.id == b.id }
    }

    @Published private(set) var message: Message?
    /// 0...1 while a determinate operation runs; nil when indeterminate or idle.
    @Published private(set) var progress: Double?
    @Published private(set) var isBusy = false

    private var clearTask: Task<Void, Never>?

    private init() {}

    func begin(_ text: String) {
        clearTask?.cancel()
        isBusy = true
        progress = nil
        message = Message(text: text, style: .info, symbol: "hourglass")
    }

    func update(_ text: String, progress: Double?) {
        guard isBusy else { return }
        self.progress = progress
        message = Message(text: text, style: .info, symbol: "hourglass")
    }

    func succeed(_ text: String, symbol: String = "checkmark.circle.fill", duration: TimeInterval = 4,
                 actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        finish(Message(text: text, style: .success, symbol: symbol, actionTitle: actionTitle, action: action),
               duration: duration)
    }

    func info(_ text: String, symbol: String = "info.circle.fill", duration: TimeInterval = 3) {
        finish(Message(text: text, style: .info, symbol: symbol), duration: duration)
    }

    func fail(_ text: String, duration: TimeInterval = 9) {
        NSLog("TwoTabs smart shelf error: \(text)")
        finish(Message(text: text, style: .error, symbol: "exclamationmark.triangle.fill"), duration: duration)
    }

    func dismiss() {
        clearTask?.cancel()
        isBusy = false
        progress = nil
        message = nil
    }

    private func finish(_ new: Message, duration: TimeInterval) {
        clearTask?.cancel()
        isBusy = false
        progress = nil
        message = new
        let id = new.id
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.message?.id == id else { return }
                withAnimation(.easeOut(duration: 0.2)) { self.message = nil }
            }
        }
    }
}

enum SmartShelfFormat {
    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
