import SwiftUI

// Monochrome symbols stay in the label's palette, unlike multicolour emoji.
enum LabelIcons {
    struct Icon: Identifiable {
        let id: String
        let title: String
    }

    static let all: [Icon] = [
        Icon(id: "tag.fill", title: "Лейбл"),
        Icon(id: "house.fill", title: "Дом"),
        Icon(id: "briefcase.fill", title: "Работа"),
        Icon(id: "heart.fill", title: "Сердце"),
        Icon(id: "star.fill", title: "Звезда"),
        Icon(id: "lightbulb.fill", title: "Идея"),
        Icon(id: "book.fill", title: "Книга"),
        Icon(id: "leaf.fill", title: "Листик"),
        Icon(id: "cup.and.saucer.fill", title: "Кофе"),
        Icon(id: "airplane", title: "Путешествия"),
        Icon(id: "gamecontroller.fill", title: "Игры"),
        Icon(id: "music.note", title: "Музыка"),
        Icon(id: "camera.fill", title: "Фото"),
        Icon(id: "gift.fill", title: "Подарок"),
        Icon(id: "sparkles", title: "Искорки"),
        Icon(id: "pawprint.fill", title: "Лапка"),
        Icon(id: "moon.fill", title: "Луна"),
        Icon(id: "calendar", title: "Планы")
    ]

    static func defaultIcon(for label: String) -> String {
        switch label.lowercased() {
        case "личное": return "house.fill"
        case "работа": return "briefcase.fill"
        case "идеи": return "lightbulb.fill"
        case "учёба", "учеба": return "book.fill"
        case "планы": return "calendar"
        case "путешествия": return "airplane"
        case "здоровье": return "heart.fill"
        case "покупки": return "tag.fill"
        case "финансы": return "star.fill"
        case "проекты": return "briefcase.fill"
        case "книги": return "book.fill"
        case "рецепты": return "cup.and.saucer.fill"
        case "вдохновение": return "sparkles"
        case "подарки": return "gift.fill"
        case "хобби": return "gamecontroller.fill"
        default: return "tag.fill"
        }
    }
}

struct LabelIconPicker: View {
    @Binding var selection: String
    let tint: Color

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 6), spacing: 7) {
            ForEach(LabelIcons.all) { icon in
                Button {
                    selection = icon.id
                } label: {
                    Image(systemName: icon.id)
                        .font(.system(size: 17, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(tint.opacity(selection == icon.id ? 0.18 : 0.05), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(selection == icon.id ? 0.7 : 0), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .help(icon.title)
                .accessibilityLabel(icon.title)
                .accessibilityAddTraits(selection == icon.id ? .isSelected : [])
            }
        }
    }
}
