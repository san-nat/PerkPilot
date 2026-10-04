import Foundation
import UserNotifications

/// Local reminders only. PerkPilot sends no push notifications and runs no
/// server in Phase 1; this schedules one quiet monthly closeout reminder.
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var isAuthorized = false
    @Published var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: Self.enabledKey)
            Task { await applySchedule() }
        }
    }

    private static let enabledKey = "perkPilot.monthlyReminderEnabled"
    private static let requestId = "perkPilot.monthly-closeout"

    init() {
        self.remindersEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    private func applySchedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestId])
        guard remindersEnabled else { return }
        guard await requestAuthorization() else {
            remindersEnabled = false
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Monthly credit closeout"
        content.body = "Check off this month's expiring card credits in PerkPilot before they reset."
        content.sound = .default

        // Repeats on the 28th of each month at 9:00 AM local — late enough to
        // act, early enough to beat month-end resets.
        var date = DateComponents()
        date.day = 28
        date.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.requestId,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
