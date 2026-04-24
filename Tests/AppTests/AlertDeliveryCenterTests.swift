import XCTest
@testable import PulseBarApp

@MainActor
final class AlertDeliveryCenterTests: XCTestCase {
    func testClearRecentAlertsRemovesRetainedSessionAlerts() async {
        let deliveryCenter = AlertDeliveryCenter(isAppBundleRuntime: false)

        _ = await deliveryCenter.deliver(title: "PulseBar Alert", body: "CPU has been above 80% for 10s.")
        _ = await deliveryCenter.deliver(title: "PulseBar Alert", body: "Temperature has been above 90 C for 10s.")

        XCTAssertEqual(deliveryCenter.recentAlerts.count, 2)

        deliveryCenter.clearRecentAlerts()

        XCTAssertTrue(deliveryCenter.recentAlerts.isEmpty)
    }
}
