import Foundation

public actor AlertEngine {
    private struct RuleState: Sendable {
        var thresholdStart: Date?
        var lastNotificationDate: Date?
    }

    private var rules: [AlertRule]
    private var statesByMetric: [MetricID: RuleState] = [:]
    private let cooldownSeconds: TimeInterval
    private let notifier: @Sendable (_ title: String, _ body: String) async -> Void

    public init(
        rule: AlertRule = .defaultCPU,
        cooldownSeconds: TimeInterval = 120,
        notifier: @escaping @Sendable (_ title: String, _ body: String) async -> Void
    ) {
        self.rules = [rule]
        self.cooldownSeconds = cooldownSeconds
        self.notifier = notifier
    }

    public init(
        rules: [AlertRule],
        cooldownSeconds: TimeInterval = 120,
        notifier: @escaping @Sendable (_ title: String, _ body: String) async -> Void
    ) {
        self.rules = rules
        self.cooldownSeconds = cooldownSeconds
        self.notifier = notifier
    }

    public func updateRule(_ newRule: AlertRule) {
        updateRules([newRule])
    }

    public func updateRules(_ newRules: [AlertRule]) {
        rules = newRules
        statesByMetric = [:]
    }

    public func process(samples: [MetricSample]) async {
        guard !rules.isEmpty else { return }

        let enabledRules = rules.filter(\.isEnabled)
        let enabledMetricIDs = Set(enabledRules.map(\.metricID))

        for metricID in statesByMetric.keys where !enabledMetricIDs.contains(metricID) {
            statesByMetric[metricID] = nil
        }

        for rule in enabledRules {
            guard let sample = samples.first(where: { $0.metricID == rule.metricID }) else {
                continue
            }
            await evaluate(rule: rule, sample: sample)
        }
    }

    private func evaluate(rule: AlertRule, sample: MetricSample) async {
        var state = statesByMetric[rule.metricID] ?? RuleState(thresholdStart: nil, lastNotificationDate: nil)

        if sample.value >= rule.threshold {
            if state.thresholdStart == nil {
                state.thresholdStart = sample.timestamp
                statesByMetric[rule.metricID] = state
                return
            }

            guard let start = state.thresholdStart else { return }
            let elapsed = sample.timestamp.timeIntervalSince(start)
            guard elapsed >= Double(rule.durationSeconds) else {
                statesByMetric[rule.metricID] = state
                return
            }

            if let lastNotificationDate = state.lastNotificationDate,
               sample.timestamp.timeIntervalSince(lastNotificationDate) < cooldownSeconds {
                statesByMetric[rule.metricID] = state
                return
            }

            state.lastNotificationDate = sample.timestamp
            state.thresholdStart = sample.timestamp
            statesByMetric[rule.metricID] = state

            let thresholdText = UnitsFormatter.format(rule.threshold, unit: sample.unit)
            let body = "\(rule.metricID.displayName) has been above \(thresholdText) for \(rule.durationSeconds)s."
            await notifier("PulseBar Alert", body)
        } else {
            state.thresholdStart = nil
            statesByMetric[rule.metricID] = state
        }
    }
}
