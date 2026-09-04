import Foundation

struct DayStat: Codable, Equatable {
    var pomodoros: Int = 0
    var focusedSeconds: Int = 0

    var isEmpty: Bool { pomodoros == 0 && focusedSeconds == 0 }
}

enum StatsKey {

    /// Ключ дня в истории. POSIX-локаль и григорианский календарь, чтобы ключи
    /// не поехали от системных настроек; лексикографический порядок строк
    /// "yyyy-MM-dd" совпадает с хронологическим — этим пользуется обрезка истории.
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

    /// Ровно `count` дней подряд, заканчивая `today`. Пустые дни возвращаются
    /// с нулями, иначе в меню появятся дырки.
    static func lastDays(_ count: Int, from history: [String: DayStat], today: Date = Date()) -> [(date: Date, stat: DayStat)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        var result: [(date: Date, stat: DayStat)] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { continue }
            result.append((day, history[key(for: day)] ?? DayStat()))
        }
        return result
    }
}

enum StatsFormat {

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE dd.MM"
        return formatter
    }()

    static let maxDots = 10

    /// Строка одного дня: "Пн 01.09   ●●●●          4 · 1:40".
    static func dayLine(date: Date, stat: DayStat) -> String {
        var label = dayFormatter.string(from: date)
        label = label.prefix(1).uppercased() + label.dropFirst()

        let dots: String
        if stat.pomodoros == 0 {
            dots = "—"
        } else if stat.pomodoros <= maxDots {
            dots = String(repeating: "●", count: stat.pomodoros)
        } else {
            dots = String(repeating: "●", count: maxDots) + "+\(stat.pomodoros - maxDots)"
        }

        let tail = String(format: "%2d · %@", stat.pomodoros, TimeFormat.hoursMinutes(stat.focusedSeconds))
        return pad(label, 10) + pad(dots, 14) + tail
    }

    static func totalLine(_ days: [(date: Date, stat: DayStat)]) -> String {
        let pomodoros = days.reduce(0) { $0 + $1.stat.pomodoros }
        let seconds = days.reduce(0) { $0 + $1.stat.focusedSeconds }
        return "Итого: \(pomodoros) 🍅 · \(TimeFormat.hoursMinutes(seconds))"
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
