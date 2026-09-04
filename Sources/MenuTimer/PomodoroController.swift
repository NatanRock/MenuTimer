import Foundation

enum PomodoroPhase {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: return "Работа"
        case .shortBreak: return "Перерыв"
        case .longBreak: return "Долгий перерыв"
        }
    }

    var seconds: Int {
        switch self {
        case .work: return Settings.workSeconds
        case .shortBreak: return Settings.shortBreakSeconds
        case .longBreak: return Settings.longBreakSeconds
        }
    }

    var isWork: Bool {
        if case .work = self { return true }
        return false
    }

    var kind: SessionKind { isWork ? .pomodoro : .rest }
}

/// Циклы работа/перерыв поверх TimerEngine.
/// Следующая фаза не стартует автоматически: оповещение у нас только визуальное,
/// и пропущенное мигание иначе съедало бы перерыв.
final class PomodoroController {

    private let engine: TimerEngine

    private(set) var currentPhase: PomodoroPhase?
    private(set) var pendingPhase: PomodoroPhase?
    /// Задача, над которой идёт цикл. Перерывы пишутся под своим именем, а сюда
    /// возвращаются на следующей рабочей фазе.
    private(set) var task: String = Settings.lastPomodoroTask
    private var completedWorkSessions = 0

    init(engine: TimerEngine) {
        self.engine = engine
    }

    var isEngaged: Bool { currentPhase != nil || pendingPhase != nil }

    func start(_ phase: PomodoroPhase, task: String? = nil) {
        if let task {
            self.task = StatsAggregate.displayName(task)
            Settings.lastPomodoroTask = self.task
        }
        currentPhase = phase
        pendingPhase = nil
        engine.start(
            task: phase.isWork ? self.task : phase.title,
            duration: TimeInterval(phase.seconds),
            kind: phase.kind
        )
    }

    func startPending() {
        guard let phase = pendingPhase else { return }
        start(phase)
    }

    /// Вызывается, когда движок перешагнул ноль. Статистику здесь не пишем —
    /// сессия ещё идёт в овертайме, её закроет AppDelegate.
    func handleFinish() {
        guard let phase = currentPhase else { return }

        switch phase {
        case .work:
            completedWorkSessions += 1
            let isLong = completedWorkSessions % Settings.longBreakEvery == 0
            pendingPhase = isLong ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            pendingPhase = .work
        }
    }

    /// Сбрасывается, когда пользователь запускает обычный таймер из пресетов.
    func disengage() {
        currentPhase = nil
        pendingPhase = nil
    }

    func resetCycle() {
        completedWorkSessions = 0
        disengage()
    }
}
