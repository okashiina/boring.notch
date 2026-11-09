//
//  ClaudePetStore.swift
//  TwoTabs Notch - Claude Code pet
//
//  Main-actor owner of the engine: receives events from the socket, ticks timers, publishes what the UI needs.
//

import Combine
import Defaults
import Foundation

@MainActor
final class ClaudePetStore: ObservableObject {
    static let shared = ClaudePetStore()

    enum ServerStatus: Equatable {
        case stopped
        case listening(String)
        case failed(String)
    }

    @Published private(set) var sessions: [ClaudePetSession] = []
    @Published private(set) var serverStatus: ServerStatus = .stopped
    @Published private(set) var lastEventDate: Date?
    @Published private(set) var eventCount = 0

    private var engine = ClaudePetEngine()
    private var server: ClaudePetSocketServer?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Settings changes must re-evaluate visibility in ContentView.
        Defaults.publisher(.claudePetEnabled, options: []).map { _ in () }
            .merge(with: Defaults.publisher(.claudePetHideWhenIdle, options: []).map { _ in () })
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Starts the socket server (idempotent). Called once from applicationDidFinishLaunching.
    func start() {
        guard server == nil else { return }
        let server = ClaudePetSocketServer()
        do {
            try server.start { event in
                DispatchQueue.main.async { ClaudePetStore.shared.handle(event) }
            }
            self.server = server
            serverStatus = .listening(server.path)
        } catch {
            serverStatus = .failed("\(error)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        serverStatus = .stopped
    }

    func handle(_ event: ClaudePetEvent, now: Date = Date()) {
        lastEventDate = now
        eventCount += 1
        engine.apply(event, now: now)
        refresh()
    }

    // MARK: Display

    /// The session the pet shows: most urgent first.
    var displaySession: ClaudePetSession? { sessions.first }
    var sessionCount: Int { sessions.count }

    /// `duringMusic`: the music live activity is on screen. Then the pet only takes the visualizer slot while
    /// something needs attention (working, waiting, compacting, done), so idle sessions never hide the music.
    func isVisible(duringMusic: Bool) -> Bool {
        guard Defaults[.claudePetEnabled], let top = displaySession else { return false }
        if duringMusic { return top.task.isAttention }
        if top.task == .sleeping && Defaults[.claudePetHideWhenIdle] { return false }
        return true
    }

    private func refresh() {
        let visible = engine.visibleSessions
        if visible != sessions { sessions = visible }
        updateTimer()
    }

    private func updateTimer() {
        if engine.sessions.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { _ in
                Task { @MainActor in ClaudePetStore.shared.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick() {
        if engine.tick(now: Date()) { refresh() } else { updateTimer() }
    }
}
