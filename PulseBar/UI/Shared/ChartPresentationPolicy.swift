import Foundation
import PulseBarCore

enum ChartPresentationPolicy {
    struct Resolved: Equatable {
        let baseline: ChartBaselinePolicy
        let areaOpacityMultiplier: Double?
        let usesThermalYAxis: Bool
    }

    static func resolve(for samples: [MetricSample]) -> Resolved {
        guard let first = samples.first else {
            return Resolved(baseline: .zero(), areaOpacityMultiplier: nil, usesThermalYAxis: false)
        }

        switch first.metricID {
        case .thermalStateLevel:
            return Resolved(
                baseline: .fixed(0 ... 3),
                areaOpacityMultiplier: nil,
                usesThermalYAxis: true
            )
        case .batteryChargePercent:
            return Resolved(
                baseline: .fixed(0 ... 100),
                areaOpacityMultiplier: isNearConstant(samples) ? 0.32 : nil,
                usesThermalYAxis: false
            )
        case .temperaturePrimaryCelsius, .temperatureMaxCelsius:
            return Resolved(
                baseline: .dataMin(minimumSpan: 1, paddingFraction: 0.1),
                areaOpacityMultiplier: nil,
                usesThermalYAxis: false
            )
        default:
            if first.unit == .celsius {
                return Resolved(
                    baseline: .dataMin(minimumSpan: 1, paddingFraction: 0.1),
                    areaOpacityMultiplier: nil,
                    usesThermalYAxis: false
                )
            }
            return Resolved(
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.1),
                areaOpacityMultiplier: nil,
                usesThermalYAxis: false
            )
        }
    }

    static func displayOptions(
        base: ChartDisplayOptions,
        environment: ChartDisplayOptions,
        for samples: [MetricSample]
    ) -> ChartDisplayOptions {
        var options = base
        guard let multiplier = resolve(for: samples).areaOpacityMultiplier else {
            return options
        }
        let resolvedBase = options.areaOpacity ?? environment.resolvedAreaOpacity
        options.areaOpacity = resolvedBase * multiplier
        return options
    }

    private static func isNearConstant(_ samples: [MetricSample]) -> Bool {
        guard samples.count >= 2 else { return samples.count <= 1 }
        let values = samples.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return true }
        return (maxValue - minValue) < 1.0
    }
}
