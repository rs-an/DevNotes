import AppKit
import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = [] {
        didSet { scheduleSave() }
    }
    @Published var activeNoteID: UUID?
    @Published var reminderTargetID: UUID?
    var newNoteFocusID: UUID?
    var finishEditingSession: (() -> Void)?
    @Published private(set) var createdLabels: [String] = []
    @Published private(set) var labelIcons: [String: String] = [:]

    private var pendingSave: DispatchWorkItem?
    private let vault: NotesVault
    private let saveQueue = DispatchQueue(label: "DevNotes.encrypted-save", qos: .utility)
    private var encryptionKey: SymmetricKey?
    private var storageReady = false
    private var pendingReminder: (noteID: UUID, targetID: UUID)?
    @Published var storageError: String?
    @Published var reminderMigrationWarning = false
    @Published private(set) var labelColors: [String: LabelColor] = [:]

    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = appSupport.appendingPathComponent(AppConfiguration.storageDirectory, isDirectory: true)
        vault = NotesVault(directory: folder)
    }

    var hasExistingStorage: Bool {
        FileManager.default.fileExists(atPath: vault.file.path)
    }

    func unlockStorage() async throws {
        guard !storageReady else { return }
        let vault = vault
        let (archive, key) = try await Task.detached(priority: .userInitiated) {
            #if DEVNOTES_DEMO
            try vault.open(initialArchive: { DemoContent.archive() }, keyProvider: { try NotesKeychain.key(allowCreation: $0) })
            #else
            try vault.open(keyProvider: { try NotesKeychain.key(allowCreation: $0) })
            #endif
        }.value
        encryptionKey = key
        createdLabels = archive.createdLabels
        labelIcons = archive.labelIcons
        labelColors = archive.labelColors
        load(archive.notes)
        createdLabels.forEach { ensureLabelColor(for: $0) }
        storageReady = true
        scheduleSave()
        if let pending = pendingReminder {
            pendingReminder = nil
            openReminder(noteID: pending.noteID, targetID: pending.targetID)
        }
        reminderMigrationWarning = !(await ReminderManager.shared.redactExistingNotifications())
    }

    #if DEVNOTES_DEMO
    private var filmBackup: NotesArchive?

    func beginFilmSession() throws {
        guard storageReady, filmBackup == nil else {
            throw NSError(domain: "PortfolioFilm", code: 1, userInfo: [NSLocalizedDescriptionKey: "Сначала разблокируйте DevNotes Demo."])
        }
        finishEditingSession?()
        guard flushStorage() else {
            throw NSError(domain: "PortfolioFilm", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить текущие демозаметки."])
        }
        pendingSave?.cancel()
        filmBackup = archiveSnapshot()
        activeNoteID = nil
        installDemoNotes()
    }

    func endFilmSession() {
        guard let backup = filmBackup else { return }
        activeNoteID = nil
        notes = backup.notes
        createdLabels = backup.createdLabels
        labelIcons = backup.labelIcons
        labelColors = backup.labelColors
        filmBackup = nil
    }

    func resetDemo() throws {
        guard storageReady, filmBackup == nil else { return }
        finishEditingSession?()
        guard flushStorage() else { throw NotesVaultError.verification }
        // A manual reset is reversible with the existing Keychain key.
        let backup = vault.file.deletingLastPathComponent()
            .appendingPathComponent("notes-before-reset-\(UUID().uuidString).vault")
        try FileManager.default.copyItem(at: vault.file, to: backup)
        notes.forEach { ReminderManager.shared.cancel(note: $0) }
        activeNoteID = nil
        installDemoNotes()
        scheduleSave()
    }

    private func installDemoNotes() {
        let archive = DemoContent.archive()
        createdLabels = archive.createdLabels
        labelIcons = archive.labelIcons
        labelColors = archive.labelColors
        notes = archive.notes
    }

    #endif

    func createNote(label: String? = nil) {
        finishEditingSession?()
        var note = Note()
        if let label {
            ensureLabelColor(for: label)
            note.labels = [label]
        }
        notes.insert(note, at: 0)
        newNoteFocusID = note.id
        activeNoteID = note.id
    }

    func insertDictation(_ text: String, noteID: UUID, after blockID: UUID?) -> UUID? {
        guard storageReady, let index = notes.firstIndex(where: { $0.id == noteID && $0.deletedAt == nil }) else { return nil }
        let block = NoteBlock.text(text)
        if notes[index].blocks.count == 1,
           notes[index].blocks[0].kind == .text, notes[index].blocks[0].isEmpty {
            notes[index].blocks[0].text = text
            notes[index].updatedAt = Date()
            return notes[index].blocks[0].id
        }
        let insertion = blockID.flatMap { id in notes[index].blocks.firstIndex { $0.id == id } }
            .map { $0 + 1 } ?? notes[index].blocks.count
        notes[index].blocks.insert(block, at: insertion)
        notes[index].updatedAt = Date()
        return block.id
    }

    func closeEditor() {
        finishEditingSession?()
        guard let id = activeNoteID else { return }
        if let note = notes.first(where: { $0.id == id }), note.isEmpty {
            notes.removeAll { $0.id == id }
        }
        activeNoteID = nil
        if newNoteFocusID == id { newNoteFocusID = nil }
    }

    func delete(_ id: UUID) {
        if activeNoteID == id { finishEditingSession?() }
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        ReminderManager.shared.cancel(note: notes[index])
        notes[index].deletedAt = Date()
        notes[index].isPinned = false
        if activeNoteID == id { activeNoteID = nil }
    }

    func restore(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].deletedAt = nil
        notes[index].updatedAt = Date()
    }

    func deletePermanently(_ id: UUID) {
        if let note = notes.first(where: { $0.id == id }) {
            ReminderManager.shared.cancel(note: note)
        }
        notes.removeAll { $0.id == id }
        if activeNoteID == id { activeNoteID = nil }
    }

    func togglePin(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        touch(id)
    }

    func touch(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].updatedAt = Date()
    }

    func color(for label: String) -> Color {
        if let entry = labelColors.first(where: {
            $0.key.localizedCaseInsensitiveCompare(label) == .orderedSame
        }) {
            return entry.value.color
        }
        return LabelColor.preview(for: label).color
    }

    func ensureLabelColor(for label: String) {
        guard !labelColors.keys.contains(where: {
            $0.localizedCaseInsensitiveCompare(label) == .orderedSame
        }) else { return }

        labelColors[label] = .random()
        saveLabelColors()
    }

    func setLabelColor(_ color: LabelColor, for label: String) {
        let key = labelColors.keys.first { $0.localizedCaseInsensitiveCompare(label) == .orderedSame } ?? label
        labelColors[key] = color
        saveLabelColors()
    }

    private func saveLabelColors() {
        scheduleSave()
    }

    func iconName(for label: String) -> String {
        let icon = labelIcons.first { $0.key.localizedCaseInsensitiveCompare(label) == .orderedSame }?.value
        return icon.flatMap { value in LabelIcons.all.contains { $0.id == value } ? value : nil }
            ?? LabelIcons.defaultIcon(for: label)
    }

    func setLabelIcon(_ icon: String, for label: String) {
        guard LabelIcons.all.contains(where: { $0.id == icon }) else { return }
        let key = labelIcons.keys.first { $0.localizedCaseInsensitiveCompare(label) == .orderedSame } ?? label
        labelIcons[key] = icon
        scheduleSave()
    }

    func createLabel(_ rawLabel: String, icon: String? = nil, color: LabelColor? = nil) {
        let label = String(rawLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !label.isEmpty,
              !createdLabels.contains(where: { $0.localizedCaseInsensitiveCompare(label) == .orderedSame }) else { return }
        ensureLabelColor(for: label)
        if let icon { setLabelIcon(icon, for: label) }
        if let color { setLabelColor(color, for: label) }
        createdLabels.append(label)
        scheduleSave()
    }

    func deleteLabel(_ label: String) {
        func matches(_ value: String) -> Bool {
            value.localizedCaseInsensitiveCompare(label) == .orderedSame
        }

        // Include the trash so restoring a note cannot resurrect the label.
        var updatedNotes = notes
        var changed = false
        for index in updatedNotes.indices where updatedNotes[index].labels.contains(where: matches) {
            updatedNotes[index].labels.removeAll(where: matches)
            changed = true
        }
        // Label management must not change note timestamps or their order.
        if changed { notes = updatedNotes }
        createdLabels.removeAll(where: matches)
        labelIcons = labelIcons.filter { !matches($0.key) }
        labelColors = labelColors.filter { !matches($0.key) }
        saveLabelColors()
        scheduleSave()
    }

    func addLabel(_ rawLabel: String, to noteID: UUID) {
        let label = String(rawLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !label.isEmpty,
              let index = notes.firstIndex(where: { $0.id == noteID && $0.deletedAt == nil }),
              !notes[index].labels.contains(where: {
                  $0.localizedCaseInsensitiveCompare(label) == .orderedSame
              }) else { return }

        ensureLabelColor(for: label)
        notes[index].labels.append(label)
    }

    func openReminder(noteID: UUID, targetID: UUID) {
        guard storageReady else {
            pendingReminder = (noteID, targetID)
            return
        }
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID && $0.deletedAt == nil }) else { return }

        for blockIndex in notes[noteIndex].blocks.indices {
            if notes[noteIndex].blocks[blockIndex].id == targetID {
                notes[noteIndex].blocks[blockIndex].reminderAt = nil
                break
            }
            guard var items = notes[noteIndex].blocks[blockIndex].bulletItems,
                  let itemIndex = items.firstIndex(where: { $0.id == targetID }) else { continue }
            items[itemIndex].reminderAt = nil
            notes[noteIndex].blocks[blockIndex].bulletItems = items
            break
        }

        ReminderManager.shared.cancel(targetID: targetID)
        reminderTargetID = targetID
        activeNoteID = noteID
    }

    func binding(for id: UUID) -> Binding<Note>? {
        guard notes.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.notes.first(where: { $0.id == id }) ?? Note(id: id)
            },
            set: { [weak self] value in
                guard let self, let index = self.notes.firstIndex(where: { $0.id == id }) else { return }
                var updated = value
                updated.updatedAt = Date()
                self.notes[index] = updated
            }
        )
    }

    private func load(_ source: [Note]) {
        var decoded = source

        for noteIndex in decoded.indices {
            for blockIndex in decoded[noteIndex].blocks.indices {
                guard decoded[noteIndex].blocks[blockIndex].kind == .bulletedList,
                      decoded[noteIndex].blocks[blockIndex].bulletItems == nil else { continue }
                let legacyItems = decoded[noteIndex].blocks[blockIndex].listItems ?? [""]
                decoded[noteIndex].blocks[blockIndex].bulletItems = legacyItems.map { BulletItem(text: $0) }
                decoded[noteIndex].blocks[blockIndex].listItems = nil
            }
        }
        notes = decoded
        decoded.flatMap(\.labels).forEach { ensureLabelColor(for: $0) }
    }

    private func scheduleSave() {
        #if DEVNOTES_DEMO
        guard filmBackup == nil else { return }
        #endif
        guard storageReady, let key = encryptionKey else { return }
        pendingSave?.cancel()
        let snapshot = archiveSnapshot()
        let vault = vault
        let work = DispatchWorkItem { [weak self] in
            do { try vault.save(snapshot, key: key) }
            catch {
                Task { @MainActor in
                    self?.storageError = "Не удалось сохранить зашифрованные заметки. Данные пока остаются в памяти. Не закрывайте приложение; повторите сохранение."
                }
            }
        }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func archiveSnapshot() -> NotesArchive {
        NotesArchive(notes: notes, createdLabels: createdLabels,
                     labelIcons: labelIcons, labelColors: labelColors)
    }

    @discardableResult
    func flushStorage() -> Bool {
        #if DEVNOTES_DEMO
        guard filmBackup == nil else { return true }
        #endif
        guard storageReady, let key = encryptionKey else { return true }
        pendingSave?.cancel()
        let snapshot = archiveSnapshot()
        do {
            try saveQueue.sync { try vault.save(snapshot, key: key) }
            storageError = nil
            return true
        } catch {
            storageError = "Не удалось сохранить заметки. Не закрывайте приложение, проверьте свободное место и повторите сохранение."
            return false
        }
    }
}
