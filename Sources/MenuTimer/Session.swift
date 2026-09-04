import Foundation

enum SessionKind: String, Codable {
    /// Обычный таймер из пресета или заданный вручную.
    case timer
    /// Рабочая фаза Pomodoro.
    case pomodoro
    /// Перерыв Pomodoro — время учитываем, но в «продуктивные» итоги не суём.
    case rest
}

/// Один отрезок работы над задачей. `seconds` — фактически проведённое время
/// (паузы вычтены, овертайм включён), `planned` — сколько ставили изначально.
/// Разница между ними и есть ответ на «сколько я в реальности просидел».
struct Session: Codable, Equatable {
    var task: String
    var start: Date
    var seconds: Int
    var planned: Int
    var kind: SessionKind

    var overtime: Int { max(0, seconds - planned) }
    var end: Date { start.addingTimeInterval(TimeInterval(seconds)) }
}

/// Журнал сессий на диске. Держим весь список в памяти — при 90 днях истории
/// это тысячи записей, читать их полностью дешевле, чем городить индексы.
final class SessionStore {

    static let shared = SessionStore()

    /// Сессии короче этого порога не записываем: это промахи мимо пункта меню,
    /// а не работа.
    static let minimumSeconds = 5

    /// Насколько назад храним историю.
    private static let retentionDays = 90

    private(set) var sessions: [Session] = []

    let fileURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        let folder = base.appendingPathComponent("MenuTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("sessions.json")
        load()
    }

    // MARK: - Запись

    func add(_ session: Session) {
        guard session.seconds >= Self.minimumSeconds else { return }
        sessions.append(session)
        prune()
        save()
    }

    func removeToday() {
        let start = Calendar.current.startOfDay(for: Date())
        sessions.removeAll { $0.start >= start }
        save()
    }

    func clear() {
        sessions = []
        save()
    }

    // MARK: - Выборки

    func sessions(on day: Date) -> [Session] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return sessions.filter { $0.start >= start && $0.start < end }
    }

    /// Последние `days` суток, включая сегодняшние.
    func sessions(lastDays days: Int) -> [Session] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        return sessions.filter { $0.start >= start }
    }

    var todayPomodoros: Int {
        sessions(on: Date()).filter { $0.kind == .pomodoro }.count
    }

    // MARK: - Диск

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.sessions.decode([Session].self, from: data)
        else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.sessions.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func prune() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) else { return }
        sessions.removeAll { $0.start < cutoff }
    }
}

private extension JSONEncoder {
    /// ISO-даты, чтобы файл можно было читать глазами и чинить руками.
    static let sessions: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let sessions: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
