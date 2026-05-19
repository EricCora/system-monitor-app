import Foundation
import PulseBarCore

@MainActor
final class TemperaturePaneModel: ObservableObject {
    private enum DefaultsKey {
        static let selectedTemperatureSensorID = "settings.selectedTemperatureSensorID"
        static let hiddenTemperatureSensorIDs = "settings.hiddenTemperatureSensorIDs"
        static let comparedTemperatureSensorIDs = "settings.comparedTemperatureSensorIDs"
    }

    static let maxComparedTemperatureSensors = 6

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

    @Published var comparedTemperatureSensorIDs: [String] {
        didSet {
            let normalized = Self.normalizedSensorIDs(
                comparedTemperatureSensorIDs,
                maxCount: Self.maxComparedTemperatureSensors
            )
            if normalized != comparedTemperatureSensorIDs {
                comparedTemperatureSensorIDs = normalized
                return
            }
            defaults.set(comparedTemperatureSensorIDs, forKey: DefaultsKey.comparedTemperatureSensorIDs)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedTemperatureSensorID = defaults.string(forKey: DefaultsKey.selectedTemperatureSensorID) ?? ""
        hiddenTemperatureSensorIDs = (
            defaults.array(forKey: DefaultsKey.hiddenTemperatureSensorIDs) as? [String] ?? []
        ).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        comparedTemperatureSensorIDs = Self.normalizedSensorIDs(
            defaults.array(forKey: DefaultsKey.comparedTemperatureSensorIDs) as? [String] ?? [],
            maxCount: Self.maxComparedTemperatureSensors
        )
    }

    func visibleSensorChannels(from allSensors: [SensorReading]) -> [SensorReading] {
        allSensors.filter {
            !hiddenTemperatureSensorIDs.contains($0.id)
                && TemperatureSensorPresentationPolicy.isUsefulSensor($0)
        }
    }

    func selectedSensorReading(in allSensors: [SensorReading], includeHidden: Bool = false) -> SensorReading? {
        let source = includeHidden ? allSensors : visibleSensorChannels(from: allSensors)
        return source.first { $0.id == selectedTemperatureSensorID }
    }

    func hideSensor(_ sensorID: String, allSensors: [SensorReading]) {
        guard !sensorID.isEmpty else { return }
        guard !hiddenTemperatureSensorIDs.contains(sensorID) else { return }
        hiddenTemperatureSensorIDs.append(sensorID)
        comparedTemperatureSensorIDs.removeAll { $0 == sensorID }

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

    func comparedTemperatureRows(from aggregateRows: [TemperatureAggregateRow]) -> [TemperatureAggregateRow] {
        let rowsByID = Dictionary(uniqueKeysWithValues: aggregateRows.map { ($0.id, $0) })
        return comparedTemperatureSensorIDs.compactMap { rowsByID[$0] }
    }

    func isCompared(sensorID: String) -> Bool {
        comparedTemperatureSensorIDs.contains(sensorID)
    }

    func toggleComparedSensor(_ sensorID: String, validIDs: Set<String>) {
        guard !sensorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard validIDs.contains(sensorID) else { return }

        if comparedTemperatureSensorIDs.contains(sensorID) {
            comparedTemperatureSensorIDs.removeAll { $0 == sensorID }
        } else if comparedTemperatureSensorIDs.count < Self.maxComparedTemperatureSensors {
            comparedTemperatureSensorIDs.append(sensorID)
        }

        reconcileComparedSensors(validIDs: validIDs)
    }

    func clearComparedSensors() {
        comparedTemperatureSensorIDs = []
    }

    func reconcileComparedSensors(validIDs: Set<String>) {
        let reconciled = comparedTemperatureSensorIDs.filter { validIDs.contains($0) }
        if reconciled != comparedTemperatureSensorIDs {
            comparedTemperatureSensorIDs = reconciled
        }
    }

    private static func normalizedSensorIDs(_ ids: [String], maxCount: Int? = nil) -> [String] {
        var output: [String] = []
        var seen = Set<String>()

        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            output.append(trimmed)
            if let maxCount, output.count >= maxCount {
                break
            }
        }

        return output
    }
}
