import Foundation
import LocalAuthentication

@main
struct LaunchAccessChecks {
    @MainActor
    static func main() async {
        let suite = "DevNotes.LaunchChecks.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(LaunchLockMode.system.rawValue, forKey: LaunchAccess.preferenceKey)
        func makeAccess(authentication: LaunchAuthentication,
                        unlockNotes: (() async throws -> Void)? = nil) -> LaunchAccess {
            LaunchAccess(authentication: authentication, unlockNotes: unlockNotes, defaults: defaults)
        }
        // Simulated authentication only: no real fingerprint prompt or user data.
        var active = false
        var attempts = 0
        let authentication = LaunchAuthentication(isActive: { active }, verifyOwner: { _ in
            attempts += 1
            active = false // System authentication can take focus from the app.
            return true
        })
        let access = makeAccess(authentication: authentication)
        await access.requestAutomaticUnlock()
        precondition(!access.isUnlocked && attempts == 0)
        active = true
        await access.requestAutomaticUnlock()
        precondition(access.isUnlocked && !access.isAuthenticating && attempts == 1)
        active = true
        await access.requestAutomaticUnlock()
        active = false
        await access.requestAutomaticUnlock()
        active = true
        await access.requestAutomaticUnlock()
        precondition(access.isUnlocked && attempts == 1, "Returning must not request entry again")

        let nextLaunch = makeAccess(authentication: authentication)
        precondition(!nextLaunch.isUnlocked, "A new process/session must start locked")
        await nextLaunch.requestAutomaticUnlock()
        precondition(nextLaunch.isUnlocked && attempts == 2)

        active = true
        var retries = 0
        var allow = false
        var vaultAttempts = 0
        let cancelled = makeAccess(authentication: LaunchAuthentication(isActive: { active }, verifyOwner: { _ in
            retries += 1
            if !allow { throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue) }
            return true
        }), unlockNotes: { vaultAttempts += 1 })
        await cancelled.requestAutomaticUnlock()
        await cancelled.requestAutomaticUnlock()
        precondition(!cancelled.isUnlocked && !cancelled.isAuthenticating && retries == 1)
        precondition(vaultAttempts == 0, "No Keychain or file access before authentication")
        allow = true
        await cancelled.unlock()
        precondition(cancelled.isUnlocked && retries == 2)
        precondition(vaultAttempts == 1)

        var storageFails = true
        var storageAttempts = 0
        let storageFailure = makeAccess(authentication: LaunchAuthentication(isActive: { true }, verifyOwner: { _ in true }), unlockNotes: {
            storageAttempts += 1
            if storageFails { throw NotesVaultError.invalidFile }
        })
        await storageFailure.requestAutomaticUnlock()
        precondition(!storageFailure.isUnlocked && storageFailure.errorMessage != nil)
        await storageFailure.requestAutomaticUnlock()
        precondition(storageAttempts == 1, "No automatic retry loop on storage failure")
        storageFails = false
        await storageFailure.unlock()
        precondition(storageFailure.isUnlocked && storageAttempts == 2)
        defaults.removeObject(forKey: LaunchAccess.preferenceKey)
        var ownerCalls = 0
        var biometricCalls = 0
        var opens = 0
        var biometricAllowed = true
        let simulated = LaunchAuthentication(isActive: { true }, verifyOwner: { _ in
            ownerCalls += 1
            return true
        }, verifyBiometrics: { context in
            biometricCalls += 1
            precondition(context.localizedFallbackTitle == "")
            return biometricAllowed
        })
        let firstLaunch = LaunchAccess(authentication: simulated, unlockNotes: { opens += 1 },
                                      defaults: defaults, hasExistingStorage: false)
        await firstLaunch.requestAutomaticUnlock()
        precondition(firstLaunch.canShowSetup && opens == 0 && ownerCalls == 0)
        await firstLaunch.selectMode(.touchID)
        precondition(firstLaunch.isUnlocked && !firstLaunch.needsSetup)
        precondition(biometricCalls == 1 && ownerCalls == 0 && opens == 1)

        let restart = LaunchAccess(authentication: simulated, unlockNotes: { opens += 1 }, defaults: defaults)
        biometricAllowed = false
        await restart.unlock()
        precondition(!restart.isUnlocked && ownerCalls == 0 && opens == 1)
        biometricAllowed = true
        await restart.unlock()
        precondition(restart.isUnlocked && opens == 2)
        biometricAllowed = false
        await restart.selectMode(.none)
        precondition(restart.mode == .touchID)
        biometricAllowed = true
        await restart.selectMode(.none)
        precondition(restart.mode == .none)
        let callsBefore = biometricCalls
        let unprotected = LaunchAccess(authentication: simulated, unlockNotes: { opens += 1 }, defaults: defaults)
        await unprotected.requestAutomaticUnlock()
        precondition(unprotected.isUnlocked && biometricCalls == callsBefore && ownerCalls == 0)

        defaults.removeObject(forKey: LaunchAccess.preferenceKey)
        let legacy = LaunchAccess(authentication: simulated, defaults: defaults, hasExistingStorage: true)
        await legacy.selectMode(.none)
        precondition(!legacy.isUnlocked && !legacy.canShowSetup)
        await legacy.requestAutomaticUnlock()
        precondition(legacy.canShowSetup && ownerCalls == 1)
        await legacy.selectMode(.none)
        precondition(!legacy.needsSetup && legacy.mode == .none)

        defaults.removeObject(forKey: LaunchAccess.preferenceKey)
        let brokenSetup = LaunchAccess(authentication: simulated,
            unlockNotes: { throw NotesVaultError.invalidFile }, defaults: defaults, hasExistingStorage: false)
        await brokenSetup.selectMode(.none)
        precondition(!brokenSetup.isUnlocked && brokenSetup.needsSetup)
        precondition(defaults.string(forKey: LaunchAccess.preferenceKey) == nil)
        print("PASS: launch authentication, first-run choice, biometric-only policy, protected settings changes, legacy upgrade, storage errors. Simulated authentication only.")
    }
}
