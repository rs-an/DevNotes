import CryptoKit
import Foundation

@main
struct NotesVaultChecks {
    static func require(_ result: @autoclosure () throws -> Bool) throws {
        let value = try result()
        precondition(value)
    }

    static func rejected(_ action: () throws -> Void) {
        do { try action(); fatalError("Expected a storage error") }
        catch { }
    }

    static func main() throws {
        let key = SymmetricKey(size: .bits256)
        let otherKey = SymmetricKey(size: .bits256)
        let marker = Data("synthetic-note-for-storage-check".utf8)
        let sealed = try NotesEncryption.seal(marker, key: key)
        try require(try NotesEncryption.open(sealed, key: key) == marker)
        precondition(sealed.range(of: marker) == nil)
        try require(try NotesEncryption.seal(marker, key: key) != sealed)
        rejected { _ = try NotesEncryption.open(sealed, key: otherKey) }
        var damaged = sealed
        damaged[damaged.count - 1] ^= 1
        rejected { _ = try NotesEncryption.open(damaged, key: key) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("devnotes-vault-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = NotesVault(directory: root)
        let (empty, _) = try vault.open(keyProvider: { allowCreation in
            precondition(allowCreation)
            return key
        })
        precondition(empty.notes.isEmpty)

        var note = Note()
        note.title = "Synthetic note"
        note.blocks = [.text("text"), .code("code"), .image(marker), .table(), .checklist("task"), .bulletedList()]
        note.labels = ["label"]
        note.deletedAt = Date()
        let original = NotesArchive(notes: [note], createdLabels: ["label"],
            labelIcons: ["label": "heart.fill"], labelColors: ["label": .preview(for: "label")])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let expected = try encoder.encode(original)

        // Previously saved vaults may contain the obsolete migration digest.
        // Unknown metadata must not prevent opening or change actual note data.
        var existingPayload = try JSONSerialization.jsonObject(with: expected) as! [String: Any]
        existingPayload["legacyDigest"] = "obsolete-migration-metadata"
        let existingData = try JSONSerialization.data(withJSONObject: existingPayload)
        try NotesEncryption.seal(existingData, key: key).write(to: vault.file, options: .atomic)
        let (opened, _) = try vault.open(keyProvider: { allowCreation in
            precondition(!allowCreation)
            return key
        })
        try require(try encoder.encode(opened) == expected)
        try vault.save(opened, key: key)
        let (reopened, _) = try vault.open(keyProvider: { _ in key })
        try require(try encoder.encode(reopened) == expected)
        let encrypted = try Data(contentsOf: vault.file)
        precondition(encrypted.range(of: marker) == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: vault.file.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)

        rejected { _ = try vault.open(keyProvider: { _ in throw NotesVaultError.missingKey }) }
        rejected { _ = try vault.open(keyProvider: { _ in otherKey }) }
        rejected { try vault.save(NotesArchive(), key: otherKey) }
        try require(try Data(contentsOf: vault.file) == encrypted)

        // The removed importer must neither read nor delete unrelated JSON files.
        let jsonFile = root.appendingPathComponent("notes.json")
        try marker.write(to: jsonFile)
        _ = try vault.open(keyProvider: { _ in key })
        try vault.save(reopened, key: key)
        try require(try Data(contentsOf: jsonFile) == marker)

        let broken = NotesVault(directory: root.appendingPathComponent("broken"))
        try FileManager.default.createDirectory(at: broken.directory, withIntermediateDirectories: false)
        try marker.write(to: broken.file)
        rejected { _ = try broken.open(keyProvider: { _ in key }) }
        try require(try Data(contentsOf: broken.file) == marker)
        print("PASS: existing encrypted archive compatibility, all block types and labels, save/reopen, permissions, missing/wrong key and damaged archive preservation. Synthetic data only; no Keychain access.")
    }
}
