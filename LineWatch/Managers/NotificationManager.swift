//
//  NotificationManager.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/11/26.
//

import Foundation
import UserNotifications

/// Schedules and cancels local notifications for the Hall of Fame free trial.
/// All scheduling is on-device — no remote APNs or backend involvement.
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private enum Identifier {
        static let threeDayReminder = "trial_reminder_3_day"
        static let oneDayReminder = "trial_reminder_1_day"
    }

    private init() {}

    /// Request notification permission. iOS only shows the prompt the first
    /// time it's called per install — subsequent calls are no-ops.
    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Silent — user denied or system error
        }
    }

    /// Schedule 3-days-remaining and 1-day-remaining local reminders for an
    /// active trial. Cancels any existing trial reminders first so this is
    /// safe to call repeatedly (e.g. on every app launch).
    func scheduleTrialReminders(endsAt: Date) {
        cancelTrialReminders()

        let threeDaysBefore = endsAt.addingTimeInterval(-3 * 24 * 60 * 60)
        let oneDayBefore = endsAt.addingTimeInterval(-1 * 24 * 60 * 60)
        let now = Date()

        if threeDaysBefore > now {
            schedule(
                id: Identifier.threeDayReminder,
                title: "3 days left in your free trial",
                body: "Your Hall of Fame free trial ends in 3 days. Tap to manage your plan.",
                fireDate: threeDaysBefore
            )
        }

        if oneDayBefore > now {
            schedule(
                id: Identifier.oneDayReminder,
                title: "1 day left in your free trial",
                body: "Your Hall of Fame free trial ends tomorrow. Pick a plan to keep your perks.",
                fireDate: oneDayBefore
            )
        }
    }

    /// Cancel pending trial reminder notifications. Called when the user
    /// upgrades past rookie or signs out.
    func cancelTrialReminders() {
        center.removePendingNotificationRequests(withIdentifiers: [
            Identifier.threeDayReminder,
            Identifier.oneDayReminder
        ])
    }

    private func schedule(id: String, title: String, body: String, fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }
}
