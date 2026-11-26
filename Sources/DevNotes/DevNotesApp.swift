import AppKit
import SwiftUI

@main
struct DevNotesApp: App {
    @NSApplicationDelegateAdaptor(DevNotesAppDelegate.self) private var appDelegate
    #if DEVNOTES_DEMO
    @StateObject private var film = NotesFilm()
    @State private var confirmingDemoReset = false
    #endif
    @StateObject private var store: NoteStore
    @StateObject private var access: LaunchAccess
    @StateObject private var dictation: SpeechDictation

    init() {
        let notes = NoteStore()
        let speech = SpeechDictation()
        _dictation = StateObject(wrappedValue: speech)
        notes.finishEditingSession = { speech.finishImmediately() }
        _store = StateObject(wrappedValue: notes)
        _access = StateObject(wrappedValue: LaunchAccess(unlockNotes: {
            try await notes.unlockStorage()
        }, hasExistingStorage: notes.hasExistingStorage))
        DevNotesAppDelegate.prepareToQuit = {
            speech.finishImmediately()
            return notes.flushStorage()
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(access)
                .environmentObject(dictation)
                .frame(minWidth: 880, minHeight: 620)
                .background(WindowConfigurator())
                #if DEVNOTES_DEMO
                .onAppear { film.attach(store: store, access: access) }
                .alert("Восстановить демозаметки?", isPresented: $confirmingDemoReset) {
                    Button("Отмена", role: .cancel) { }
                    Button("Восстановить", role: .destructive) {
                        do { try store.resetDemo() }
                        catch { store.storageError = "Не удалось восстановить демозаметки. " + error.localizedDescription }
                    }
                } message: {
                    Text("Текущие демозаметки будут заменены примерами. Перед заменой сохранится зашифрованная резервная копия.")
                }
                #endif
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            #if DEVNOTES_DEMO
            CommandMenu("Демо") {
                Button("Восстановить демонстрационные данные") { confirmingDemoReset = true }
                    .disabled(!access.isUnlocked || access.needsSetup)
            }
            #endif
            CommandGroup(replacing: .newItem) {
                Button("Новая заметка") {
                    store.createNote()
                }
                .keyboardShortcut("n")
                .disabled(!access.isUnlocked || access.needsSetup)
            }
            CommandGroup(after: .textEditing) {
                Button("Поиск") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("k")
                .disabled(!access.isUnlocked || access.needsSetup)
            }
        }
        Settings {
            LaunchLockSettingsView()
                .environmentObject(access)
        }
    }
}
