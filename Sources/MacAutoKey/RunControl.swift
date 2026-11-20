import Foundation

/// One control per run. Paused tasks suspend without timers or idle polling.
@MainActor
final class RunControl {
    private(set) var isPaused = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var sleeper: Task<Void, any Error>?
    private var interruptedAt: ContinuousClock.Instant?
    private let startedAt = ContinuousClock.now
    private var pausedAt: ContinuousClock.Instant?
    private var pausedDuration = Duration.zero

    var elapsedActiveTime: Duration { startedAt.duration(to: pausedAt ?? .now) - pausedDuration }

    func pause() {
        guard !isPaused else { return }
        pausedAt = .now
        isPaused = true
        if sleeper != nil { interruptedAt = .now; sleeper?.cancel() }
    }
    func resume() {
        if let pausedAt { pausedDuration += pausedAt.duration(to: .now) }
        pausedAt = nil
        isPaused = false
        let pending = waiter
        waiter = nil
        pending?.resume()
    }
    func cancel() {
        sleeper?.cancel()
        resume()
    }
    func waitIfPaused() async throws {
        try Task.checkCancellation()
        if isPaused {
            await withCheckedContinuation { waiter = $0 }
        }
        try Task.checkCancellation()
    }
    func sleep(ms: Int) async throws {
        try await sleep(for: .milliseconds(ms))
    }
    func sleep(for duration: Duration) async throws {
        var remaining = duration
        while remaining > .zero {
            try await waitIfPaused()
            let started = ContinuousClock.now
            interruptedAt = nil
            let duration = remaining
            let pending = Task { try await Task.sleep(for: duration) }
            sleeper = pending
            do { try await pending.value }
            catch {
                sleeper = nil
                try Task.checkCancellation()
                guard interruptedAt != nil else { throw error }
            }
            sleeper = nil
            try Task.checkCancellation()
            let elapsed = started.duration(to: interruptedAt ?? .now)
            remaining -= min(remaining, elapsed)
        }
        try await waitIfPaused()
    }
}
