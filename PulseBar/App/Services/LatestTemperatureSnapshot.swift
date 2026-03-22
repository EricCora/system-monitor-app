import Foundation
import PulseBarCore

struct LatestTemperatureSnapshot: Codable, Equatable, Sendable {
    var channels: [SensorReading]
    var temperatureSensors: [TemperatureSensorReading]
    var lastSuccessMessage: String?
    var sourceDiagnostics: [SensorSourceDiagnostic]
    var fanHealthy: Bool
    var channelsAvailable: [SensorChannelType]
    var activeSourceChain: [String]
    var fanParityGateBlocked: Bool
    var fanParityGateMessage: String?
    var capturedAt: Date
}
