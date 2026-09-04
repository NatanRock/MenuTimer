import Foundation

struct Preset: Codable, Equatable {
    var title: String
    var seconds: Int

    var duration: TimeInterval { TimeInterval(seconds) }

    /// Заголовок для меню: пользовательский, либо выведенный из длительности.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Preset.autoTitle(seconds: seconds) : trimmed
    }

    static func autoTitle(seconds: Int) -> String {
        if seconds % 3600 == 0 && seconds >= 3600 { return "\(seconds / 3600) ч" }
        if seconds % 60 == 0 { return "\(seconds / 60) мин" }
        if seconds < 60 { return "\(seconds) с" }
        return TimeFormat.short(TimeInterval(seconds))
    }
}

enum TimeFormat {

    /// MM:SS до часа, дальше H:MM:SS.
    static func short(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// H:MM для статистики: 6000 -> "1:40". Отрезки короче минуты показываем в
    /// секундах — иначе они выглядят как «0:00», то есть как отсутствие времени.
    static func hoursMinutes(_ seconds: Int) -> String {
        if seconds < 60 { return "\(max(0, seconds))с" }
        return String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    /// Разбирает "25", "25:00", "1:30:00", "10с", "10s".
    static func parse(_ raw: String) -> Int? {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }

        var unitIsSeconds = false
        for suffix in ["с", "s", "sec", "сек"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            unitIsSeconds = true
            break
        }
        for suffix in ["м", "m", "min", "мин"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 3 else { return nil }

        var values: [Int] = []
        for part in parts {
            guard let value = Int(part.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
            values.append(value)
        }

        let seconds: Int
        switch values.count {
        case 1: seconds = unitIsSeconds ? values[0] : values[0] * 60
        case 2: seconds = values[0] * 60 + values[1]
        case 3: seconds = values[0] * 3600 + values[1] * 60 + values[2]
        default: return nil
        }
        return seconds > 0 ? seconds : nil
    }
}
