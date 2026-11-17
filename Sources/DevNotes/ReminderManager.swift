import AppKit
import Foundation
import UserNotifications

final class ReminderManager {
    static let shared = ReminderManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func schedule(
        targetID: UUID,
        noteID: UUID,
        at date: Date
    ) async -> Bool {
        guard date > Date() else { return false }

        do {
            let settings = await center.notificationSettings()
            let allowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                allowed = true
            case .notDetermined:
                allowed = try await center.requestAuthorization(options: [.alert, .sound])
            default:
                allowed = false
            }
            guard allowed else { return false }

            let content = UNMutableNotificationContent()
            content.title = "DevNotes"
            content.body = "Пора заглянуть в заметку"
            content.sound = .default
            content.userInfo = [
                "noteID": noteID.uuidString,
                "targetID": targetID.uuidString
            ]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier(for: targetID),
                content: content,
                trigger: trigger
            )
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func cancel(targetID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: targetID)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(for: targetID)])
    }

    func redactExistingNotifications() async -> Bool {
        // The OS persists notification contents independently of notes.vault.
        // Keep timing and IDs, but do not leave old note text in that store.
        let requests = await center.pendingNotificationRequests()
        var success = true
        for request in requests where request.identifier.hasPrefix("devnotes.reminder.") {
            if request.content.title == "DevNotes", request.content.body == "Пора заглянуть в заметку",
               request.content.subtitle.isEmpty { continue }
            guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                success = false
                continue
            }
            content.title = "DevNotes"
            content.body = "Пора заглянуть в заметку"
            content.subtitle = ""
            do {
                try await center.add(UNNotificationRequest(identifier: request.identifier,
                                                           content: content, trigger: request.trigger))
            } catch {
                // Never keep plaintext notification text if replacement fails.
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                success = false
            }
        }
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered
            .filter {
                $0.request.identifier.hasPrefix("devnotes.reminder.") &&
                ($0.request.content.title != "DevNotes" ||
                 $0.request.content.body != "Пора заглянуть в заметку" ||
                 !$0.request.content.subtitle.isEmpty)
            }
            .map { $0.request.identifier })
        return success
    }

    func cancel(note: Note) {
        let targetIDs = note.blocks.flatMap { block -> [UUID] in
            var ids: [UUID] = []
            if block.reminderAt != nil { ids.append(block.id) }
            ids.append(contentsOf: block.resolvedBulletItems.filter { $0.reminderAt != nil }.map(\.id))
            return ids
        }
        let identifiers = targetIDs.map(identifier(for:))
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func identifier(for targetID: UUID) -> String {
        "devnotes.reminder.\(targetID.uuidString)"
    }
}

final class DevNotesAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var prepareToQuit: (() -> Bool)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.prepareToQuit?() == false else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Не удалось сохранить заметки"
        alert.informativeText = "Выход отменён, чтобы не потерять изменения. Проверьте свободное место и повторите сохранение."
        alert.addButton(withTitle: "Понятно")
        alert.runModal()
        return .terminateCancel
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .openReminder,
            object: nil,
            userInfo: response.notification.request.content.userInfo
        )
        completionHandler()
    }
}

extension Notification.Name {
    static let openReminder = Notification.Name("DevNotes.openReminder")
}
