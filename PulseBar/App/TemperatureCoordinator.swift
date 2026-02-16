import Foundation
import PulseBarCore

actor TemperatureCoordinator {
    private let provider: PowermetricsProvider

    init(provider: PowermetricsProvider) {
        self.provider = provider
    }

    func setPrivilegedEnabled(_ enabled: Bool) async {
        await provider.updateEnabled(enabled)
    }

    func currentStatus() async -> PrivilegedTemperatureStatus {
        await provider.currentStatus()
    }

    func requestImmediateRetry() async {
        await provider.requestImmediateRetry()
    }
}
