import Foundation

struct ReminderPreset: Identifiable, Codable, Equatable {
    enum Rule: String, Codable, CaseIterable, Identifiable {
        case after
        case todayAt
        case tomorrowAt
        case specificDate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .after: return "Через"
            case .todayAt: return "Сегодня"
            case .tomorrowAt: return "Завтра"
            case .specificDate: return "Дата"
            }
        }
    }

    enum Unit: String, Codable, CaseIterable, Identifiable {
        case minutes
        case hours
        case days

        var id: String { rawValue }

        var title: String {
            switch self {
            case .minutes: return "минут"
            case .hours: return "часов"
            case .days: return "дней"
            }
        }

        var seconds: TimeInterval {
            switch self {
            case .minutes: return 60
            case .hours: return 3_600
            case .days: return 86_400
            }
        }
    }

    var id = UUID()
    var label: String
    var rule: Rule
    var amount: Int = 30
    var unit: Unit = .minutes
    var hour: Int = 9
    var minute: Int = 0
    var specificDate: Date?

    func fireDate(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch rule {
        case .after:
            return now.addingTimeInterval(TimeInterval(max(amount, 1)) * unit.seconds)
        case .todayAt:
            let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .tomorrowAt:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow) ?? tomorrow
        case .specificDate:
            return specificDate ?? now.addingTimeInterval(3_600)
        }
    }

    var summary: String {
        switch rule {
        case .after:
            return "через \(amount) \(unit.title)"
        case .todayAt:
            return "сегодня, \(formattedTime)"
        case .tomorrowAt:
            return "завтра, \(formattedTime)"
        case .specificDate:
            return (specificDate ?? Date().addingTimeInterval(3_600))
                .formatted(date: .abbreviated, time: .shortened)
        }
    }

    private var formattedTime: String {
        let date = Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static let defaults: [ReminderPreset] = [
        ReminderPreset(label: "15 мин", rule: .after, amount: 15, unit: .minutes),
        ReminderPreset(label: "1 час", rule: .after, amount: 1, unit: .hours),
        ReminderPreset(label: "Вечером", rule: .todayAt, hour: 19, minute: 0),
        ReminderPreset(label: "Завтра", rule: .tomorrowAt, hour: 9, minute: 0)
    ]
}

enum ReminderPresetStorage {
    private static let key = "DevNotes.reminderPresets.v1"

    static func load() -> [ReminderPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([ReminderPreset].self, from: data) else {
            return ReminderPreset.defaults
        }
        return presets
    }

    static func save(_ presets: [ReminderPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
