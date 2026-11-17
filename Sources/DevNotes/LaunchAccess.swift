import AppKit
import LocalAuthentication
import SwiftUI

enum LaunchLockMode: String, CaseIterable, Identifiable {
    case none, touchID, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Без блокировки"
        case .touchID: return "Только Touch ID"
        case .system: return "Touch ID или пароль Mac"
        }
    }
}

struct LaunchAuthentication {
    var isActive: () -> Bool = { NSApplication.shared.isActive }
    var verifyOwner: (LAContext) async throws -> Bool = { context in
        try await evaluate(.deviceOwnerAuthentication, context: context)
    }
    var verifyBiometrics: (LAContext) async throws -> Bool = { context in
        try await evaluate(.deviceOwnerAuthenticationWithBiometrics, context: context)
    }

    private static func evaluate(_ policy: LAPolicy, context: LAContext) async throws -> Bool {
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            throw error ?? NSError(domain: LAError.errorDomain, code: LAError.notInteractive.rawValue)
        }
        return try await context.evaluatePolicy(policy, localizedReason: "открыть заметки")
    }
}

@MainActor
final class LaunchAccess: ObservableObject {
    static let preferenceKey = "DevNotes.launchLockMode.v1"
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var mode: LaunchLockMode
    @Published private(set) var needsSetup: Bool
    private let hasExistingStorage: Bool
    private let defaults: UserDefaults
    private let authentication: LaunchAuthentication
    private let unlockNotes: (() async throws -> Void)?
    private var didAttemptAutomaticUnlock = false

    var canShowSetup: Bool { needsSetup && (!hasExistingStorage || isUnlocked) }

    init(authentication: LaunchAuthentication = LaunchAuthentication(),
         unlockNotes: (() async throws -> Void)? = nil,
         defaults: UserDefaults = .standard,
         hasExistingStorage: Bool = true) {
        self.authentication = authentication
        self.unlockNotes = unlockNotes
        self.defaults = defaults
        self.hasExistingStorage = hasExistingStorage
        let stored = defaults.string(forKey: Self.preferenceKey)
        mode = stored.flatMap(LaunchLockMode.init(rawValue:)) ?? .system
        needsSetup = stored == nil
    }

    func requestAutomaticUnlock() async {
        guard authentication.isActive(), !didAttemptAutomaticUnlock,
              !isUnlocked, !isAuthenticating, !canShowSetup else { return }
        didAttemptAutomaticUnlock = true
        await unlock()
    }

    private func verify(_ selected: LaunchLockMode) async throws -> Bool {
        if selected == .none { return true }
        let context = LAContext()
        context.localizedCancelTitle = "Отмена"
        context.localizedFallbackTitle = selected == .touchID ? "" : "Пароль Mac"
        defer { context.invalidate() }
        if selected == .touchID { return try await authentication.verifyBiometrics(context) }
        return try await authentication.verifyOwner(context)
    }

    func unlock() async {
        guard !isUnlocked, !isAuthenticating, !canShowSetup else { return }
        didAttemptAutomaticUnlock = true
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            guard try await verify(mode) else {
                errorMessage = "Не удалось подтвердить вход. Попробуйте ещё раз."
                return
            }
            try await unlockNotes?()
            isUnlocked = true
        } catch { show(error) }
    }

    func selectMode(_ selected: LaunchLockMode) async {
        guard !isAuthenticating, canShowSetup || (isUnlocked && !needsSetup) else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            // Existing users first unlock with their old policy. Settings changes
            // reauthenticate before allowing protection to be disabled or changed.
            if !needsSetup {
                guard try await verify(mode) else {
                    errorMessage = "Изменение входа не подтверждено."
                    return
                }
            }
            if selected != .none && (needsSetup || selected != mode) {
                // The legacy first-run gate has already confirmed system auth.
                if !(needsSetup && hasExistingStorage && isUnlocked && selected == .system) {
                    guard try await verify(selected) else {
                        errorMessage = "Не удалось включить выбранный способ входа."
                        return
                    }
                }
            }
            if !isUnlocked { try await unlockNotes?() }
            defaults.set(selected.rawValue, forKey: Self.preferenceKey)
            mode = selected
            needsSetup = false
            isUnlocked = true
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        if let auth = error as? LAError {
            if [.userCancel, .appCancel, .systemCancel].contains(auth.code) { return }
            if [.biometryNotAvailable, .biometryNotEnrolled, .biometryLockout].contains(auth.code) {
                errorMessage = "Touch ID недоступен. Проверьте его в настройках macOS. Пароль Mac в режиме «Только Touch ID» не используется."
                return
            }
        }
        if let vault = error as? NotesVaultError { errorMessage = vault.localizedDescription }
        else { errorMessage = "Не удалось открыть заметки. Проверьте доступ к Связке ключей и повторите вход. Данные сохранены." }
    }
}
