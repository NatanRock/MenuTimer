import Foundation

/// Отсчёт, привязанный к абсолютным датам. И остаток, и фактически проведённое
/// время считаются от временных меток, поэтому сон системы и дрейф таймера не
/// сбивают ни то, ни другое.
///
/// Ключевое отличие от простого обратного отсчёта: на нуле движок не гаснет, а
/// уходит в овертайм и продолжает считать вверх. В статистику попадает `elapsed`
/// — сколько времени задача заняла на самом деле, а не сколько на неё ставили.
final class TimerEngine {

    private(set) var task: String = ""
    private(set) var kind: SessionKind = .timer
    private(set) var plannedDuration: TimeInterval = 0
    private(set) var startedAt: Date?

    /// Время завершённых сегментов: всё, что натикало до текущей паузы.
    private var accumulated: TimeInterval = 0
    /// Начало текущего сегмента; nil — стоим на паузе.
    private var segmentStart: Date?

    var onTick: (() -> Void)?
    /// Ноль пройден — самое время мигать.
    var onFinish: (() -> Void)?
    /// Овертайм упёрся в потолок: похоже, про таймер просто забыли.
    var onOvertimeLimit: (() -> Void)?

    private var ticker: Timer?
    /// onFinish должен сработать один раз за отрезок, а не на каждом тике.
    private var didNotifyFinish = false

    var isActive: Bool { startedAt != nil }
    var isRunning: Bool { isActive && segmentStart != nil }
    var isPaused: Bool { isActive && segmentStart == nil }

    /// Фактически проведённое время: паузы вычтены, овертайм включён.
    var elapsed: TimeInterval {
        guard isActive else { return 0 }
        guard let segmentStart else { return accumulated }
        // Для прошедшей даты timeIntervalSinceNow отрицателен.
        return accumulated - segmentStart.timeIntervalSinceNow
    }

    var remaining: TimeInterval { max(0, plannedDuration - elapsed) }
    var overtime: TimeInterval { max(0, elapsed - plannedDuration) }

    /// Ноль перешагнули — дальше идёт овертайм. Считается от времени, а не
    /// выставляется тикером: иначе на границе нуля (или при выходе из
    /// приложения между тиками) флаг отставал бы от факта.
    var isOvertime: Bool { isActive && elapsed >= plannedDuration }

    // MARK: - Управление

    func start(task: String, duration: TimeInterval, kind: SessionKind) {
        self.task = task
        self.kind = kind
        plannedDuration = duration
        startedAt = Date()
        accumulated = 0
        segmentStart = Date()
        didNotifyFinish = false
        startTicker()
        onTick?()
    }

    func pause() {
        guard isRunning, let segmentStart else { return }
        accumulated -= segmentStart.timeIntervalSinceNow
        self.segmentStart = nil
        stopTicker()
        onTick?()
    }

    func resume() {
        guard isPaused else { return }
        segmentStart = Date()
        startTicker()
        onTick?()
    }

    /// Продлить таймер. Из овертайма это возвращает обратно в обычный отсчёт —
    /// «дай мне ещё пять минут» должно работать и после сигнала.
    func extend(by interval: TimeInterval) {
        guard isActive else { return }
        plannedDuration += interval
        // Вышли обратно в обычный отсчёт — значит, следующий ноль снова событие.
        if remaining > 0 { didNotifyFinish = false }
        onTick?()
    }

    /// Останавливает таймер и отдаёт сессию для журнала. Слишком короткие
    /// отрезки отсеиваются здесь же — движок в любом случае сбрасывается.
    func stopAndCollect(minimumSeconds: Int = SessionStore.minimumSeconds) -> Session? {
        guard let startedAt else { return nil }
        let seconds = Int(elapsed.rounded())
        // Помидор засчитывается только если досидели до нуля; брошенный на
        // середине — обычный отрезок времени, в счётчик 🍅 он не идёт.
        let recordedKind: SessionKind = (kind == .pomodoro && !isOvertime) ? .timer : kind
        let session = Session(
            task: task,
            start: startedAt,
            seconds: seconds,
            planned: Int(plannedDuration.rounded()),
            kind: recordedKind
        )
        reset()
        return seconds >= minimumSeconds ? session : nil
    }

    func reset() {
        task = ""
        kind = .timer
        plannedDuration = 0
        startedAt = nil
        accumulated = 0
        segmentStart = nil
        didNotifyFinish = false
        stopTicker()
        onTick?()
    }

    // MARK: - Тикер

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
        guard isRunning else { return }

        if !didNotifyFinish && isOvertime {
            didNotifyFinish = true
            onTick?()
            onFinish?()
            return
        }

        if overtime >= Settings.overtimeLimitSeconds {
            onOvertimeLimit?()
            return
        }

        onTick?()
    }
}
