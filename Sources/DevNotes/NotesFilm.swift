#if DEVNOTES_DEMO
import AppKit
import Foundation
import SwiftUI

// No mouse, keyboard, screen API, microphone, or activation calls.
// The existing views render the same store actions used by normal interaction.
@MainActor
final class NotesFilm: NSObject, ObservableObject {
    private weak var store: NoteStore?
    private weak var access: LaunchAccess?
    private var task: Task<Void, Never>?
    private var token: String?
    private var watchdog: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var windowID: Int?

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(command(_:)), name: .init("local.portfolio.demo.command"), object: "local.devnotes.portfolio-demo")
        NotificationCenter.default.addObserver(self, selector: #selector(closing(_:)), name: NSWindow.willCloseNotification, object: nil)
    }
    func attach(store: NoteStore, access: LaunchAccess) { self.store = store; self.access = access }
    private func reply(_ event: String, message: String = "") {
        guard let token else { return }
        DistributedNotificationCenter.default().postNotificationName(.init("local.portfolio.demo.response"), object: "local.devnotes.portfolio-demo", userInfo: ["runID": token, "event": event, "message": message], deliverImmediately: true)
    }
    @objc private func closing(_ notification: Notification) {
        if (notification.object as? NSWindow)?.windowNumber == windowID { reply("error", message: "Выбранное окно DevNotes закрыто."); restore() }
    }
    @objc private func command(_ notification: Notification) {
        guard let id = notification.userInfo?["runID"] as? String,
              let action = notification.userInfo?["action"] as? String else { return }
        if action == "cancel" { if id == token { restore() }; return }
        if action == "run" { if id == token { run() }; return }
        guard action == "prepare", token == nil,
              let number = notification.userInfo?["windowID"] as? String,
              let wid = Int(number),
              NSApp.windows.contains(where: { $0.windowNumber == wid && !$0.isMiniaturized && $0.canBecomeMain }) else { return }
        token = id; windowID = wid
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Автоматический сценарий синтетической демоверсии")
        guard access?.isUnlocked == true, let store else { reply("error", message: "Сначала разблокируйте DevNotes Demo, затем выберите его главное окно."); restore(); return }
        do {
            // Replace only in-memory content with the bundled synthetic seed.
            // NoteStore suppresses saves until the previous store is restored.
            try store.beginFilmSession()
            home()
            reply("ready")
            watchdog = Task { [weak self] in
                for _ in 0..<130 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled, let self, self.token == id else { return }
                        guard let wid = self.windowID, NSApp.windows.contains(where: { $0.windowNumber == wid && !$0.isMiniaturized }) else {
                            self.reply("error", message: "Выбранное окно закрыто или свёрнуто."); self.restore(); return
                        }
                    }
                    guard !Task.isCancelled, let self, self.token == id else { return }
                    self.reply("error", message: "Демосеанс завершён по таймауту."); self.restore()
            }
        } catch { reply("error", message: error.localizedDescription); restore() }
    }
    private func home(label: String? = nil, pinned: Bool = false, search: String = "") {
        store?.activeNoteID = nil
        var values: [String: Any] = ["pinned": pinned, "search": search]
        if let label { values["label"] = label }
        NotificationCenter.default.post(name: .init("PortfolioFilm.notesHome"), object: nil, userInfo: values)
    }
    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); try Task.checkCancellation()
        guard let windowID, NSApp.windows.contains(where: { $0.windowNumber == windowID && !$0.isMiniaturized }) else {
            throw NSError(domain: "PortfolioFilm", code: 3, userInfo: [NSLocalizedDescriptionKey: "Окно DevNotes закрыто или свёрнуто."])
        }
    }
    private func run() {
        guard task == nil, let store else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await pause(3)
                if let note = store.notes.first(where: { $0.title.hasPrefix("иконка:") }) {
                    store.activeNoteID = note.id
                }
                try await pause(5)
                NotificationCenter.default.post(name: .init("PortfolioFilm.notesScroll"), object: nil)
                try await pause(4)
                if let i = store.notes.firstIndex(where: { $0.title.hasPrefix("иконка:") }),
                   let b = store.notes[i].blocks.firstIndex(where: { $0.kind == .checklist && !$0.isChecked }) {
                    store.notes[i].blocks[b].isChecked = true
                }
                try await pause(3)
                home(label: "Разработка")
                try await pause(3)
                if let note = store.notes.first(where: { $0.title.hasPrefix("сохранение без") }) { store.activeNoteID = note.id }
                try await pause(5)
                home(search: "цвета")
                try await pause(3)
                home()
                try await pause(1)
                var note = Note()
                note.title = "идея следующей итерации"
                note.labels = ["Идеи"]
                note.blocks = [.text("собрать обратную связь о DevNotes после первого показа."), .checklist("обсудить следующий шаг"), .code("// меньше переключений — больше контекста")]
                store.notes.insert(note, at: 0); store.activeNoteID = note.id
                try await pause(4)
                home(pinned: true)
                try await pause(3)
                reply("finished")
            } catch is CancellationError {} catch { reply("error", message: error.localizedDescription) }
        }
    }
    private func restore() {
        task?.cancel(); task = nil; watchdog?.cancel(); watchdog = nil
        store?.endFilmSession(); home()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }; activity = nil
        token = nil; windowID = nil
    }
}

#endif
