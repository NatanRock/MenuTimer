import Foundation

enum TimerState {
    case idle
    case running(endDate: Date)
    case paused(remaining: TimeInterval)
    case finished
}

/// Обратный отсчёт, привязанный к абсолютной дате окончания.
/// Остаток всегда вычисляется от `endDate`, поэтому сон системы и дрейф таймера
/// не влияют на точность.
final class TimerEngine {

    private(set) var state: TimerState = .idle
    private(set) var label: String = ""
    private(set) var totalDuration: TimeInterval = 0

    var onTick: (() -> Void)?
    var onFinish: (() -> Void)?

    private var ticker: Timer?

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var isActive: Bool { isRunning || isPaused }

    var remaining: TimeInterval {
        switch state {
        case .running(let endDate): return max(0, endDate.timeIntervalSinceNow)
        case .paused(let value): return value
        case .idle, .finished: return 0
        }
    }

    func start(duration: TimeInterval, label: String) {
        self.label = label
        self.totalDuration = duration
        state = .running(endDate: Date().addingTimeInterval(duration))
        startTicker()
        onTick?()
    }

    func pause() {
        guard isRunning else { return }
        state = .paused(remaining: remaining)
        stopTicker()
        onTick?()
    }

    func resume() {
        guard case .paused(let value) = state else { return }
        state = .running(endDate: Date().addingTimeInterval(value))
        startTicker()
        onTick?()
    }

    /// Продлить идущий или поставленный на паузу таймер.
    func extend(by interval: TimeInterval) {
        switch state {
        case .running(let endDate):
            state = .running(endDate: endDate.addingTimeInterval(interval))
        case .paused(let value):
            state = .paused(remaining: value + interval)
        case .idle, .finished:
            return
        }
        // Правим и totalDuration — иначе в статистику уйдёт исходная длительность.
        totalDuration += interval
        onTick?()
    }

    func reset() {
        state = .idle
        label = ""
        totalDuration = 0
        stopTicker()
        onTick?()
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common — иначе отсчёт замирает, пока открыто меню статус-бара.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard case .running(let endDate) = state else { return }
        if endDate.timeIntervalSinceNow <= 0 {
            state = .finished
            stopTicker()
            onTick?()
            onFinish?()
        } else {
            onTick?()
        }
    }
}
