import Foundation
import PulseBarCore

@MainActor
final class TemperaturePaneModel: ObservableObject {
    private enum DefaultsKey {
        static let selectedTemperatureSensorID = "settings.selectedTemperatureSensorID"
        static let hiddenTemperatureSensorIDs = "settings.hiddenTemperatureSensorIDs"
    }

    private let defaults: UserDefaults

    @Published var selectedTemperatureSensorID: String {
        didSet {
            defaults.set(selectedTemperatureSensorID, forKey: DefaultsKey.selectedTemperatureSensorID)
        }
    }

    @Published var hiddenTemperatureSensorIDs: [String] {
        didSet {
            let normalized = Array(Set(hiddenTemperatureSensorIDs))
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if normalized != hiddenTemperatureSensorIDs {
                hiddenTemperatureSensorIDs = normalized
                return
            }
            defaults.set(hiddenTemperatureSensorIDs, forKey: DefaultsKey.hiddenTemperatureSensorIDs)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedTemperatureSensorID = defaults.string(forKey: DefaultsKey.selectedTemperatureSensorID) ?? ""
        hiddenTemperatureSensorIDs = (
            defaults.array(forKey: DefaultsKey.hiddenTemperatureSensorIDs) as? [String] ?? []
        ).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func visibleSensorChannels(from allSensors: [SensorReading]) -> [SensorReading] {
        allSensors.filter { !hiddenTemperatureSensorIDs.contains($0.id) }
    }

    func selectedSensorReading(in allSensors: [SensorReading], includeHidden: Bool = false) -> SensorReading? {
        let source = includeHidden ? allSensors : visibleSensorChannels(from: allSensors)
        return source.first { $0.id == selectedTemperatureSensorID }
    }

    func hideSensor(_ sensorID: String, allSensors: [SensorReading]) {
        guard !sensorID.isEmpty else { return }
        guard !hiddenTemperatureSensorIDs.contains(sensorID) else { return }
        hiddenTemperatureSensorIDs.append(sensorID)

        if selectedTemperatureSensorID == sensorID {
            selectedTemperatureSensorID = visibleSensorChannels(from: allSensors).first?.id ?? ""
        }
    }

    func resetHiddenSensors(allSensors: [SensorReading]) {
        hiddenTemperatureSensorIDs = []
        if selectedTemperatureSensorID.isEmpty {
            selectedTemperatureSensorID = visibleSensorChannels(from: allSensors).first?.id ?? ""
        }
    }

    func reconcileVisibleSensors(_ allSensors: [SensorReading]) {
        let currentIDs = Set(allSensors.map(\.id))
        let updatedHidden = hiddenTemperatureSensorIDs.filter { currentIDs.contains($0) }
        if updatedHidden != hiddenTemperatureSensorIDs {
            hiddenTemperatureSensorIDs = updatedHidden
        }

        let visibleSensors = visibleSensorChannels(from: allSensors)
        if selectedTemperatureSensorID.isEmpty || !visibleSensors.contains(where: { $0.id == selectedTemperatureSensorID }) {
            selectedTemperatureSensorID = visibleSensors.first?.id ?? ""
        }
    }

    func isHidden(sensorID: String) -> Bool {
        hiddenTemperatureSensorIDs.contains(sensorID)
    }
}
