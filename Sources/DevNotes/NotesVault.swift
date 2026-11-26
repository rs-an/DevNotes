import CryptoKit
import Foundation
import Security

struct NotesArchive: Codable {
    var notes: [Note] = []
    var createdLabels: [String] = []
    var labelIcons: [String: String] = [:]
    var labelColors: [String: LabelColor] = [:]
}

enum NotesVaultError: LocalizedError {
    case missingKey, invalidKey, invalidFile, keychain(OSStatus), verification

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Ключ шифрования не найден в Связке ключей этого Mac. Файл заметок сохранён без изменений. Не удаляйте его."
        case .invalidKey: return "Ключ шифрования в Связке ключей повреждён. Файл заметок сохранён без изменений. Не удаляйте его или ключ."
        case .invalidFile: return "Не удалось проверить зашифрованные заметки. Файл не будет перезаписан."
        case .keychain(let status): return "Не удалось получить ключ из Связки ключей (код \(status)). Повторите разблокировку."
        case .verification: return "Проверка сохранённых данных не прошла. Исходные данные не удалены."
        }
    }
}

enum NotesEncryption {
    // Version and format are authenticated, not just the ciphertext.
    static let header = Data("DEVNOTES-AES256-GCM-1\n".utf8)

    static func seal(_ data: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(data, using: key, authenticating: header)
        guard let combined = box.combined else { throw NotesVaultError.verification }
        return header + combined
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        guard data.starts(with: header) else { throw NotesVaultError.invalidFile }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(header.count))
            return try AES.GCM.open(box, using: key, authenticating: header)
        } catch { throw NotesVaultError.invalidFile }
    }
}

enum NotesKeychain {
    static func key(allowCreation: Bool) throws -> SymmetricKey {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfiguration.keychainService,
            kSecAttrAccount as String: "notes-aes256-key",
            kSecAttrSynchronizable as String: false
        ]
        func read() throws -> Data? {
            var query = identity
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw NotesVaultError.keychain(status) }
            guard let data = result as? Data, data.count == 32 else { throw NotesVaultError.invalidKey }
            return data
        }
        if let data = try read() { return SymmetricKey(data: data) }
        guard allowCreation else { throw NotesVaultError.missingKey }
        let generated = SymmetricKey(size: .bits256)
        var item = identity
        // Login Keychain's default per-app ACL: do not create an all-apps
        // access list. This also supports local ad-hoc macOS builds, which
        // cannot use provisioned Data Protection Keychain access groups.
        // LaunchAccess applies the selected launch policy before storage opens.
        item[kSecAttrLabel as String] = "Ключ шифрования заметок DevNotes"
        item[kSecValueData as String] = generated.withUnsafeBytes { Data($0) }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw NotesVaultError.keychain(status)
        }
        // Verify that the OS actually persisted the key before writing data.
        guard let authenticated = try read() else { throw NotesVaultError.missingKey }
        return SymmetricKey(data: authenticated)
    }
}

struct NotesVault {
    let directory: URL
    var file: URL { directory.appendingPathComponent("notes.vault") }

    func open(initialArchive: () -> NotesArchive = { NotesArchive() },
              keyProvider: (Bool) throws -> SymmetricKey) throws -> (NotesArchive, SymmetricKey) {
        let encryptedExists = FileManager.default.fileExists(atPath: file.path)
        let key = try keyProvider(!encryptedExists)
        if encryptedExists {
            let archive = try JSONDecoder().decode(NotesArchive.self,
                from: NotesEncryption.open(Data(contentsOf: file), key: key))
            return (archive, key)
        }
        let archive = initialArchive()
        try save(archive, key: key)
        return (archive, key)
    }

    func save(_ archive: NotesArchive, key: SymmetricKey) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Refuse to replace an existing vault if its authentication fails.
        if fm.fileExists(atPath: file.path) {
            _ = try NotesEncryption.open(Data(contentsOf: file), key: key)
        }
        let data = try JSONEncoder().encode(archive)
        let encrypted = try NotesEncryption.seal(data, key: key)
        guard try NotesEncryption.open(encrypted, key: key) == data else { throw NotesVaultError.verification }
        try encrypted.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
        guard try NotesEncryption.open(Data(contentsOf: file), key: key) == data else {
            throw NotesVaultError.verification
        }
    }
}
