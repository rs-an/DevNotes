import Foundation

/// Stable identities: changing these would disconnect existing notes or keys.
enum AppConfiguration {
    #if DEVNOTES_DEMO
    static let isDemo = true
    static let bundleIdentifier = "local.devnotes.portfolio-demo"
    static let storageDirectory = "DevNotesPortfolioDemo"
    static let keychainService = "local.devnotes.portfolio-demo.notes-encryption.v1"
    #else
    static let isDemo = false
    static let bundleIdentifier = "local.devnotes.app"
    static let storageDirectory = "DevNotes"
    static let keychainService = "local.devnotes.notes-encryption.v1"
    #endif
}
