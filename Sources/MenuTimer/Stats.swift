import Foundation

/// Суммарное время по одной задаче за период.
struct TaskTotal: Equatable {
    var task: String
    var seconds: Int
    var planned: Int
    var count: Int
    var isRest: Bool

    var overtime: Int { max(0, seconds - planned) }
}

enum StatsAggregate {

    /// Группировка по имени задачи. Ключ нормализован — регистр и лишние пробелы
    /// не должны плодить дубли («Игры» и «игры » — одна строка).
    ///
    /// Показываем самое частое написание, а не самое свежее: одна опечатка,
    /// сделанная последней, иначе переименовала бы всю задачу в статистике.
    static func totals(_ sessions: [Session]) -> [TaskTotal] {
        var order: [String] = []
        var byKey: [String: TaskTotal] = [:]
        var spellings: [String: [String: Int]] = [:]

        for session in sessions {
            let name = displayName(session.task)
            let key = name.lowercased()
            spellings[key, default: [:]][name, default: 0] += 1

            if var total = byKey[key] {
                total.seconds += session.seconds
                total.planned += session.planned
                total.count += 1
                // Перерыв остаётся перерывом, только если под этим именем не
                // было обычной работы.
                total.isRest = total.isRest && session.kind == .rest
                byKey[key] = total
            } else {
                order.append(key)
                byKey[key] = TaskTotal(
                    task: name,
                    seconds: session.seconds,
                    planned: session.planned,
                    count: 1,
                    isRest: session.kind == .rest
                )
            }
        }

        return order.compactMap { key -> TaskTotal? in
            guard var total = byKey[key] else { return nil }
            if let best = spellings[key]?.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key {
                total.task = best
            }
            return total
        }
        .sorted { $0.seconds > $1.seconds }
    }

    static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    /// Итог за период: продуктивное время, перерывы и общий счёт помидоров.
    static func summary(_ sessions: [Session]) -> (focused: Int, rest: Int, pomodoros: Int) {
        var focused = 0
        var rest = 0
        var pomodoros = 0
        for session in sessions {
            if session.kind == .rest {
                rest += session.seconds
            } else {
                focused += session.seconds
            }
            if session.kind == .pomodoro { pomodoros += 1 }
        }
        return (focused, rest, pomodoros)
    }
}

enum StatsKey {

    /// Ключ дня. POSIX-локаль и григорианский календарь, чтобы ключи не поехали
    /// от системных настроек.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    /// Ровно `count` дней подряд, заканчивая сегодняшним. Пустые дни тоже
    /// возвращаются — иначе в меню появятся дырки.
    static func lastDays(_ count: Int, from sessions: [Session], today: Date = Date()) -> [(date: Date, sessions: [Session])] {
        let calendar = Calendar.current
        var buckets: [String: [Session]] = [:]
        for session in sessions {
            buckets[key(for: session.start), default: []].append(session)
        }

        let start = calendar.startOfDay(for: today)
        var result: [(date: Date, sessions: [Session])] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { continue }
            result.append((day, buckets[key(for: day)] ?? []))
        }
        return result
    }
}

enum StatsFormat {

    static let barWidth = 12
    private static let nameWidth = 15
    private static let timeWidth = 7

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE dd.MM"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Строка задачи: «Игры            1:12  ██████▓▓».
    /// Полные блоки — время в рамках плана, штриховка — то, что сверх него.
    static func taskLine(_ total: TaskTotal, max maxSeconds: Int) -> String {
        let name = truncate(total.task, nameWidth - 1)
        let time = TimeFormat.hoursMinutes(total.seconds)
        return pad(name, nameWidth) + pad(time, timeWidth) + bar(total, max: maxSeconds)
    }

    /// Строка дня в разбивке за неделю: «Пн 01.09        4:17  ██████ · 5 🍅».
    static func dayLine(date: Date, sessions: [Session], max maxSeconds: Int) -> String {
        var label = dayFormatter.string(from: date)
        label = label.prefix(1).uppercased() + label.dropFirst()

        let summary = StatsAggregate.summary(sessions)
        guard summary.focused > 0 || summary.rest > 0 else {
            return pad(label, nameWidth) + pad("—", timeWidth)
        }

        let filled = maxSeconds > 0 ? scaled(summary.focused, max: maxSeconds) : 0
        var line = pad(label, nameWidth)
            + pad(TimeFormat.hoursMinutes(summary.focused), timeWidth)
            + String(repeating: "█", count: filled)
        if summary.pomodoros > 0 {
            line += "  \(summary.pomodoros) 🍅"
        }
        return line
    }

    /// Строка одной сессии: «14:05  Игры            1:12  +0:12».
    static func sessionLine(_ session: Session) -> String {
        let time = clockFormatter.string(from: session.start)
        let name = truncate(StatsAggregate.displayName(session.task), nameWidth - 1)
        var line = pad(time, 7) + pad(name, nameWidth) + pad(TimeFormat.hoursMinutes(session.seconds), timeWidth)
        if session.overtime > 0 {
            line += "+" + TimeFormat.hoursMinutes(session.overtime)
        }
        return line
    }

    /// Пункт меню пресета в тех же колонках, что и статистика: «Игры      1:00:00».
    static func presetLine(_ preset: Preset) -> String {
        pad(truncate(preset.displayTitle, nameWidth - 1), nameWidth) + TimeFormat.short(preset.duration)
    }

    static func totalLine(_ sessions: [Session]) -> String {
        let summary = StatsAggregate.summary(sessions)
        var line = pad("Итого", nameWidth) + pad(TimeFormat.hoursMinutes(summary.focused), timeWidth)
        var extras: [String] = []
        if summary.pomodoros > 0 { extras.append("\(summary.pomodoros) 🍅") }
        if summary.rest > 0 { extras.append("перерывы \(TimeFormat.hoursMinutes(summary.rest))") }
        if !extras.isEmpty { line += extras.joined(separator: " · ") }
        return line
    }

    // MARK: - Мелочи вёрстки

    private static func bar(_ total: TaskTotal, max maxSeconds: Int) -> String {
        guard maxSeconds > 0, total.seconds > 0 else { return "" }
        let cells = scaled(total.seconds, max: maxSeconds)
        guard cells > 0 else { return "" }
        // Доля овертайма в баре — та же пропорция, что и во времени.
        let over = min(cells, Int((Double(total.overtime) / Double(total.seconds) * Double(cells)).rounded()))
        return String(repeating: "█", count: cells - over) + String(repeating: "▓", count: over)
    }

    private static func scaled(_ value: Int, max maxValue: Int) -> Int {
        guard maxValue > 0, value > 0 else { return 0 }
        return max(1, Int((Double(value) / Double(maxValue) * Double(barWidth)).rounded()))
    }

    private static func truncate(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
