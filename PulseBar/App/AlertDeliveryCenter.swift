import Foundation
import UserNotifications

struct DeliveredAlert: Identifiable, Equatable, Codable {
    let id: UUID
    let title: String
    let body: String
    let deliveredAt: Date

    init(id: UUID = UUID(), title: String, body: String, deliveredAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.deliveredAt = deliveredAt
    }
}

@MainActor
final class AlertDeliveryCenter {
    private let isAppBundleRuntime: Bool
    private let maximumRetainedAlerts: Int

    private(set) var recentAlerts: [DeliveredAlert] = []

    init(isAppBundleRuntime: Bool, maximumRetainedAlerts: Int = 20) {
        self.isAppBundleRuntime = isAppBundleRuntime
        self.maximumRetainedAlerts = max(5, maximumRetainedAlerts)
    }

    func requestAuthorizationIfNeeded() async {
        guard isAppBundleRuntime else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func deliver(title: String, body: String) async -> DeliveredAlert {
        let alert = DeliveredAlert(title: title, body: body)
        recentAlerts.insert(alert, at: 0)
        if recentAlerts.count > maximumRetainedAlerts {
            recentAlerts = Array(recentAlerts.prefix(maximumRetainedAlerts))
        }

        guard isAppBundleRuntime else {
            return alert
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().add(request) { _ in
                continuation.resume()
            }
        }
        return alert
    }

    func clearRecentAlerts() {
        recentAlerts.removeAll()
    }
}
