import Foundation

/// Обёртка над UserDefaults. Здесь живут только настройки — журнал сессий
/// отдельно, в SessionStore. Длительности хранятся в секундах, чтобы их можно
/// было менять руками для проверки:
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
        static let overtimeLimit = "overtimeLimitSeconds"
        static let lastTask = "lastPomodoroTask"
    }

    static let defaultPresets: [Preset] = [
        Preset(title: "Работа", seconds: 25 * 60),
        Preset(title: "Чтение", seconds: 30 * 60),
        Preset(title: "Игры", seconds: 60 * 60),
        Preset(title: "Отдых", seconds: 10 * 60)
    ]

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.work: 25 * 60,
            Key.shortBreak: 5 * 60,
            Key.longBreak: 15 * 60,
            Key.longBreakEvery: 4,
            Key.blinkMax: 600,
            // Овертайм не бесконечен: если про таймер забыли и ушли спать, он
            // сам закроет сессию, а не запишет в статистику всю ночь.
            Key.overtimeLimit: 2 * 3600
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

    static var overtimeLimitSeconds: TimeInterval {
        get { TimeInterval(max(60, defaults.integer(forKey: Key.overtimeLimit))) }
        set { defaults.set(max(60, Int(newValue)), forKey: Key.overtimeLimit) }
    }

    /// Задача последнего помидора — чтобы «Начать помидор» стартовал в один клик,
    /// а не спрашивал название каждый раз.
    static var lastPomodoroTask: String {
        get {
            let stored = (defaults.string(forKey: Key.lastTask) ?? "").trimmingCharacters(in: .whitespaces)
            return stored.isEmpty ? "Работа" : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            defaults.set(trimmed, forKey: Key.lastTask)
        }
    }
}
