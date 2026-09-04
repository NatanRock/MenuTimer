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
}

/// Циклы работа/перерыв поверх TimerEngine.
/// Следующая фаза не стартует автоматически: оповещение у нас только визуальное,
/// и пропущенное мигание иначе съедало бы перерыв.
final class PomodoroController {

    private let engine: TimerEngine

    private(set) var currentPhase: PomodoroPhase?
    private(set) var pendingPhase: PomodoroPhase?
    private var completedWorkSessions = 0

    init(engine: TimerEngine) {
        self.engine = engine
    }

    var isEngaged: Bool { currentPhase != nil || pendingPhase != nil }

    func start(_ phase: PomodoroPhase) {
        currentPhase = phase
        pendingPhase = nil
        engine.start(duration: TimeInterval(phase.seconds), label: phase.title)
    }

    func startPending() {
        guard let phase = pendingPhase else { return }
        start(phase)
    }

    /// Вызывается, когда движок досчитал до нуля.
    func handleFinish() {
        guard let phase = currentPhase else { return }
        currentPhase = nil

        switch phase {
        case .work:
            Settings.record(pomodoro: true, focusedSeconds: phase.seconds)
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
