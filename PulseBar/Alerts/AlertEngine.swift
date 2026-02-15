import Foundation

public actor AlertEngine {
    private var rule: AlertRule
    private var thresholdStart: Date?
    private var lastNotificationDate: Date?
    private let cooldownSeconds: TimeInterval
    private let notifier: @Sendable (_ title: String, _ body: String) async -> Void

    public init(
        rule: AlertRule = .defaultCPU,
        cooldownSeconds: TimeInterval = 120,
        notifier: @escaping @Sendable (_ title: String, _ body: String) async -> Void
    ) {
        self.rule = rule
        self.cooldownSeconds = cooldownSeconds
        self.notifier = notifier
    }

    public func updateRule(_ newRule: AlertRule) {
        rule = newRule
        thresholdStart = nil
    }

    public func process(samples: [MetricSample]) async {
        guard rule.isEnabled else {
            thresholdStart = nil
            return
        }

        guard let sample = samples.first(where: { $0.metricID == rule.metricID }) else {
            return
        }

        if sample.value >= rule.threshold {
            if thresholdStart == nil {
                thresholdStart = sample.timestamp
                return
            }

            guard let start = thresholdStart else { return }
            let elapsed = sample.timestamp.timeIntervalSince(start)
            guard elapsed >= Double(rule.durationSeconds) else { return }

            if let lastNotificationDate,
               sample.timestamp.timeIntervalSince(lastNotificationDate) < cooldownSeconds {
                return
            }

            lastNotificationDate = sample.timestamp
            thresholdStart = sample.timestamp

            let body = "CPU has been above \(Int(rule.threshold))% for \(rule.durationSeconds)s."
            await notifier("PulseBar CPU Alert", body)
        } else {
            thresholdStart = nil
        }
    }
}
