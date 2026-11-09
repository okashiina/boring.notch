//
//  ClaudePetStore.swift
//  TwoTabs Notch - Claude Code pet
//
//  Main-actor owner of the engine: receives events from the socket, ticks timers, publishes what the UI needs.
//

import Combine
import Defaults
import Foundation
import os

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
    /// Today's usage estimate (nil until the first scan, or without the ~/.claude grant).
    @Published private(set) var usage: ClaudePetUsageTotals?
    /// Session shown in the Claude tab. nil = the most urgent one.
    @Published var selectedSessionId: String?
    /// True for a few seconds after a session starts waiting: the closed notch shows "Claude needs you".
    @Published private(set) var attentionPeek = false
    /// Bumps on every transition into waiting: the closed-notch pet bounces.
    @Published private(set) var bounceTrigger = 0

    private var engine = ClaudePetEngine()
    private var server: ClaudePetSocketServer?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let transcripts = ClaudePetTranscriptReader()
    private let usageScanner = ClaudePetUsageScanner()
    private var previousTasks: [String: ClaudePetTask] = [:]
    private var lastTranscriptRead: [String: Date] = [:]
    private var transcriptInFlight = Set<String>()
    private var lastUsageScan = Date.distantPast
    private var peekTask: Task<Void, Never>?

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
            ClaudePetLog.logger.error("server start failed: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        serverStatus = .stopped
        ClaudePetLog.logger.info("store stopped")
    }

    func handle(_ event: ClaudePetEvent, now: Date = Date()) {
        lastEventDate = now
        eventCount += 1
        engine.apply(event, now: now)
        refresh()
        if event.kind != .sessionEnd { refreshTranscript(event.sessionId, force: event.kind == .stop || event.kind == .userPromptSubmit) }
    }

    /// Selected session (falls back to the most urgent one).
    var selectedSession: ClaudePetSession? {
        sessions.first { $0.id == selectedSessionId } ?? sessions.first
    }

    // MARK: Transcripts and usage (need the ~/.claude grant)

    func accessChanged() {
        lastTranscriptRead = [:]
        if ClaudePetAccess.shared.isGranted {
            for s in sessions { refreshTranscript(s.id, force: true) }
            refreshUsage(force: true)
        } else {
            usage = nil
        }
        objectWillChange.send()
    }

    /// Reads the new part of the transcript off the main thread and merges it into the engine. Throttled per session.
    func refreshTranscript(_ sessionId: String, force: Bool = false) {
        guard ClaudePetAccess.shared.isGranted,
              let path = engine.sessions[sessionId]?.transcriptPath, ClaudePetAccess.shared.covers(path),
              !transcriptInFlight.contains(sessionId) else { return }
        let now = Date()
        if !force, let last = lastTranscriptRead[sessionId], now.timeIntervalSince(last) < 1.5 { return }
        lastTranscriptRead[sessionId] = now
        transcriptInFlight.insert(sessionId)
        Task { [transcripts] in
            let update = await transcripts.read(path: path)
            await MainActor.run {
                let store = ClaudePetStore.shared
                store.transcriptInFlight.remove(sessionId)
                store.merge(update, sessionId: sessionId)
            }
        }
    }

    private func merge(_ update: ClaudePetTranscriptUpdate, sessionId: String) {
        let now = Date()
        for t in update.texts { engine.addAssistantText(sessionId: sessionId, text: t.text, date: t.date) }
        if update.interrupted { ClaudePetLog.logger.info("transcript: user interrupt in session=\(ClaudePetLog.short(sessionId), privacy: .public)") }
        engine.applyTranscript(sessionId: sessionId, title: update.title, gitBranch: update.gitBranch, interrupted: update.interrupted, now: now)
        refresh()
    }

    /// Rescans today's transcripts (at most every 60 s unless forced).
    func refreshUsage(force: Bool = false) {
        guard let dir = ClaudePetAccess.shared.directory else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastUsageScan) > 60 else { return }
        lastUsageScan = now
        Task { [usageScanner] in
            let totals = await usageScanner.today(claudeDir: dir)
            await MainActor.run { ClaudePetStore.shared.usage = totals }
        }
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
        notifyTransitions(visible)
    }

    /// Sound, bounce and closed-notch peek on the moment a session starts waiting (or finishes a turn).
    private func notifyTransitions(_ visible: [ClaudePetSession]) {
        var tasks: [String: ClaudePetTask] = [:]
        for s in visible {
            tasks[s.id] = s.task
            let old = previousTasks[s.id]
            guard old != s.task else { continue }
            if s.task == .waiting {
                bounceTrigger += 1
                ClaudePetActions.playSound(.waiting, for: s)
                if Defaults[.claudePetPeek] { showPeek() }
            } else if s.task == .done, old == .working || old == .waiting {
                ClaudePetActions.playSound(.done, for: s)
            }
        }
        previousTasks = tasks
    }

    private func showPeek() {
        attentionPeek = true
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.attentionPeek = false }
        }
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

    private var tickCount = 0

    private func tick() {
        if engine.tick(now: Date()) { refresh() } else { updateTimer() }
        tickCount += 1
        // Esc sends no Stop hook: while something is "working", look at the transcript every few seconds.
        if tickCount % 4 == 0 {
            for s in sessions where s.task == .working || s.task == .waiting { refreshTranscript(s.id) }
        }
        if attentionPeek, sessions.allSatisfy({ $0.task != .waiting }) { attentionPeek = false }
    }
}
