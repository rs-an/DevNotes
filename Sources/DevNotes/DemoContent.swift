#if DEVNOTES_DEMO
import AppKit
import Foundation

enum DemoContent {
    static func archive() -> NotesArchive {
        let labels = ["Разработка", "Дизайн", "Релиз", "Идеи"]
        return NotesArchive(notes: notes(), createdLabels: labels,
            labelIcons: ["Разработка": "book.fill", "Дизайн": "sparkles", "Релиз": "calendar", "Идеи": "lightbulb.fill"],
            labelColors: Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($0.element, LabelColor.demoPalette($0.offset)) }))
    }

    static func notes() -> [Note] {
        func note(_ title: String, _ labels: [String], _ blocks: [NoteBlock], pinned: Bool = false, age: Double = 0, trash: Bool = false) -> Note {
            var n = Note()
            n.title = title; n.labels = labels; n.blocks = blocks; n.isPinned = pinned
            n.createdAt = Date().addingTimeInterval(-86400 * (age + 7))
            n.updatedAt = Date().addingTimeInterval(-3600 * age)
            n.deletedAt = trash ? Date().addingTimeInterval(-3600) : nil
            return n
        }
        func bullets(_ items: [String]) -> NoteBlock {
            NoteBlock(kind: .bulletedList, bulletItems: items.map { BulletItem(text: $0) })
        }
        func check(_ text: String, done: Bool = false) -> NoteBlock {
            var block = NoteBlock.checklist(text); block.isChecked = done; return block
        }
        return [
            note("иконка: какой цвет?", ["Дизайн"], [
                .image(iconStudy()),
                .text("графит, терракота или сиреневый? пока оставлю графит: он не спорит с цветными лейблами."),
                check("посмотреть иконку в Dock на светлом и тёмном фоне"),
                .text("стопка листов остаётся. хочется, чтобы даже маленькая иконка была похожа на заметки.")
            ], pinned: true),
            note("сохранение без ⌘S", ["Разработка"], [
                .code("pendingSave?.cancel()\nsaveQueue.asyncAfter(\n    deadline: .now() + 0.25,\n    execute: work\n)"),
                .text("не писать на диск после каждой буквы. подождать 250 мс после правки, затем сохранить снимок."),
                check("проверить закрытие окна сразу после ввода"),
                .text("при выходе не ждать таймера — сохранить оставшиеся изменения сразу.")
            ], pinned: true, age: 1),
            note("перед публикацией", ["Релиз"], [
                check("выложить код на GitHub", done: true),
                check("прикрепить DMG к релизу", done: true),
                check("записать короткое видео"),
                check("попросить друга установить"),
                .text("на видео: открыть заметку с кодом, отметить задачу, найти заметку по слову. уложиться в полминуты.")
            ], age: 2),
            note("цвета интерфейса", ["Дизайн"], [
                NoteBlock(kind: .table, table: [["", "день", "ночь"], ["фон", "#F4F1EC", "#202124"], ["акцент", "#E3572E", "#FF6E40"]]),
                .text("светлый фон — чуть теплее белого. ночью не делать фон совсем чёрным: карточки должны отделяться от него."),
                check("посмотреть контраст текста в обеих темах")
            ], age: 3),
            note("после первого релиза", ["Идеи"], [
                bullets(["шаблон для разбора бага", "ссылки между заметками", "быстрый ввод из меню Mac", "сначала — отзывы друзей"])
            ], age: 5),
            note("зачем мне DevNotes", ["Идеи"], [
                .text("пишу DevNotes и веду его разработку здесь же.\n\nкод, мысли и задачи — наконец рядом.")
            ], age: 8),
            note("старое описание", ["Дизайн"], [
                .text("«универсальное пространство продуктивности» — нет, слишком громко.\n\nлучше просто: заметки, код и задачи в одном месте.")
            ], age: 24, trash: true)
        ]
    }

    private static func iconStudy() -> Data {
        guard let url = Bundle.main.url(forResource: "IconStudy", withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("Missing bundled demo image: IconStudy.png")
        }
        return data
    }
}

#endif
