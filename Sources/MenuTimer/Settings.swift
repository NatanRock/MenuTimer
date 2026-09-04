import Foundation

/// Обёртка над UserDefaults. Длительности Pomodoro хранятся в секундах,
/// чтобы их можно было менять руками для проверки:
///   defaults write com.local.menutimer pomodoroWorkSeconds -int 10
enum Settings {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let presets = "presets"
        static let work = "pomodoroWorkSeconds"
        static let shortBreak = "pomodoroShortBreakSeconds"
        static let longBreak = "pomodoroLongBreakSeconds"
        static let longBreakEvery = "pomodoroLongBreakEvery"
        static let blinkMax = "blinkMaxSeconds"
        static let history = "dayHistory"
    }

    static let defaultPresets: [Preset] = [
        Preset(title: "", seconds: 5 * 60),
        Preset(title: "", seconds: 10 * 60),
        Preset(title: "", seconds: 25 * 60),
        Preset(title: "", seconds: 60 * 60)
    ]

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.work: 25 * 60,
            Key.shortBreak: 5 * 60,
            Key.longBreak: 15 * 60,
            Key.longBreakEvery: 4,
            Key.blinkMax: 600
        ])
    }

    static var presets: [Preset] {
        get {
            guard let data = defaults.data(forKey: Key.presets),
                  let decoded = try? JSONDecoder().decode([Preset].self, from: data),
                  !decoded.isEmpty
            else { return defaultPresets }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.presets)
        }
    }

    static var workSeconds: Int {
        get { defaults.integer(forKey: Key.work) }
        set { defaults.set(max(1, newValue), forKey: Key.work) }
    }

    static var shortBreakSeconds: Int {
        get { defaults.integer(forKey: Key.shortBreak) }
        set { defaults.set(max(1, newValue), forKey: Key.shortBreak) }
    }

    static var longBreakSeconds: Int {
        get { defaults.integer(forKey: Key.longBreak) }
        set { defaults.set(max(1, newValue), forKey: Key.longBreak) }
    }

    static var longBreakEvery: Int {
        get { max(1, defaults.integer(forKey: Key.longBreakEvery)) }
        set { defaults.set(max(1, newValue), forKey: Key.longBreakEvery) }
    }

    static var blinkMaxSeconds: TimeInterval {
        TimeInterval(max(1, defaults.integer(forKey: Key.blinkMax)))
    }

    // MARK: - История по дням

    static var history: [String: DayStat] {
        get {
            guard let data = defaults.data(forKey: Key.history),
                  let decoded = try? JSONDecoder().decode([String: DayStat].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.history)
        }
    }

    /// Помидоров за сегодня. Смена суток обрабатывается сама — ключ другой.
    static var completedToday: Int {
        history[StatsKey.key(for: Date())]?.pomodoros ?? 0
    }

    /// Единственная точка записи статистики.
    static func record(pomodoro: Bool, focusedSeconds: Int) {
        var updated = pruned(history)
        let key = StatsKey.key(for: Date())
        var day = updated[key] ?? DayStat()
        if pomodoro { day.pomodoros += 1 }
        day.focusedSeconds += max(0, focusedSeconds)
        updated[key] = day
        history = updated
    }

    /// Обнуляет сегодняшний день целиком (пункт «Сбросить счётчик и цикл»).
    static func resetToday() {
        var updated = history
        updated.removeValue(forKey: StatsKey.key(for: Date()))
        history = updated
    }

    static func clearHistory() {
        history = [:]
    }

    /// Дни старше 90 суток выкидываем, чтобы словарь не рос бесконечно.
    private static func pruned(_ history: [String: DayStat]) -> [String: DayStat] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else { return history }
        let cutoffKey = StatsKey.key(for: cutoff)
        return history.filter { $0.key >= cutoffKey }
    }
}
