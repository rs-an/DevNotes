import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var blocks: [NoteBlock] = [.text()]
    var createdAt = Date()
    var updatedAt = Date()
    var isPinned = false
    var deletedAt: Date?
    var labels: [String] = []

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }

        for block in blocks where block.kind == .text || block.kind == .code {
            if let firstLine = block.text
                .split(whereSeparator: { $0.isNewline })
                .map(String.init)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return String(firstLine.prefix(60))
            }
        }
        if let firstItem = blocks
            .first(where: { $0.kind == .bulletedList })?
            .resolvedBulletItems
            .first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return String(firstItem.text.prefix(60))
        }
        return "Новая заметка"
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        blocks.allSatisfy { block in
            block.isEmpty && block.reminderAt == nil &&
            !(block.bulletItems ?? []).contains { $0.reminderAt != nil }
        }
    }

    var textPreview: String {
        blocks
            .flatMap { block -> [String] in
                if block.kind == .text || block.kind == .code { return [block.text] }
                if block.kind == .bulletedList { return block.resolvedBulletItems.map(\.text) }
                return []
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Note {
    private enum CodingKeys: String, CodingKey {
        case id, title, blocks, createdAt, updatedAt, isPinned, deletedAt, labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        blocks = try container.decodeIfPresent([NoteBlock].self, forKey: .blocks) ?? [.text()]
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
    }

}

struct NoteBlock: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case code
        case image
        case table
        case checklist
        case bulletedList
    }

    var id = UUID()
    var kind: Kind
    var text = ""
    var imageData: Data?
    var imageWidthFraction: Double?
    var table: [[String]] = []
    // Kept for migration from the first list format.
    var listItems: [String]?
    var bulletItems: [BulletItem]?
    var isChecked = false
    var reminderAt: Date?

    var resolvedBulletItems: [BulletItem] {
        bulletItems ?? []
    }

    var isEmpty: Bool {
        switch kind {
        case .text, .code, .checklist:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .bulletedList:
            return resolvedBulletItems.allSatisfy {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .image:
            return imageData == nil
        case .table:
            return table.allSatisfy { row in
                row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        }
    }

    static func text(_ value: String = "") -> NoteBlock {
        NoteBlock(kind: .text, text: value)
    }

    static func code(_ value: String = "") -> NoteBlock {
        NoteBlock(kind: .code, text: value)
    }

    static func image(_ data: Data) -> NoteBlock {
        NoteBlock(kind: .image, imageData: data)
    }

    static func table(rows: Int = 3, columns: Int = 3) -> NoteBlock {
        NoteBlock(kind: .table, table: Array(repeating: Array(repeating: "", count: columns), count: rows))
    }

    static func checklist(_ value: String = "") -> NoteBlock {
        NoteBlock(kind: .checklist, text: value)
    }

    static func bulletedList() -> NoteBlock {
        NoteBlock(kind: .bulletedList, bulletItems: [BulletItem(text: "")])
    }
}

struct BulletItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var reminderAt: Date?
}

struct ReminderTarget: Identifiable, Equatable {
    let id: UUID
    let text: String
    let currentDate: Date?
}
