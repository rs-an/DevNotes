import Foundation

/// Stable identities: changing these would disconnect existing notes or keys.
enum AppConfiguration {
    #if DEVNOTES_DEMO
    static let storageDirectory = "DevNotesPortfolioDemo"
    static let keychainService = "local.devnotes.portfolio-demo.notes-encryption.v1"
    #else
    static let storageDirectory = "DevNotes"
    static let keychainService = "local.devnotes.notes-encryption.v1"
    #endif
}
