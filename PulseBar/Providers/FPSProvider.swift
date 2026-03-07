import CoreGraphics
import CoreMedia
import CoreVideo
import Dispatch
import Foundation
@preconcurrency import ScreenCaptureKit

public actor FPSProvider: MetricProvider {
    public nonisolated let providerID = "fps"
    public typealias FPSReader = @Sendable () async -> Double?
    public typealias StatusReader = @Sendable () async -> String?

    private let injectedFPSReader: FPSReader?
    private let injectedStatusReader: StatusReader?
    private let fallbackReader: @Sendable () -> Double?
    private var liveCaptureEnabled: Bool
    private var monitor: ScreenCaptureFPSMonitor?

    public init(
        fpsReader: FPSReader? = nil,
        statusReader: StatusReader? = nil,
        liveCaptureEnabled: Bool = false,
        fallbackReader: (@Sendable () -> Double?)? = nil
    ) {
        self.injectedFPSReader = fpsReader
        self.injectedStatusReader = statusReader
        self.fallbackReader = fallbackReader ?? { FPSProvider.readDisplayLinkRefreshRate() }
        self.liveCaptureEnabled = liveCaptureEnabled

        if fpsReader == nil, statusReader == nil, liveCaptureEnabled {
            self.monitor = ScreenCaptureFPSMonitor(fallbackReader: self.fallbackReader)
        } else {
            self.monitor = nil
        }
    }

    public func sample(at date: Date) async throws -> [MetricSample] {
        guard let fps = await currentFPS() else {
            return []
        }

        return [
            MetricSample(
                metricID: .framesPerSecond,
                timestamp: date,
                value: max(fps, 0),
                unit: .scalar
            )
        ]
    }

    public func currentStatusMessage() async -> String? {
        if let injectedStatusReader {
            return await injectedStatusReader()
        }

        guard liveCaptureEnabled else {
            return nil
        }

        return await ensureMonitor().currentStatusMessage()
    }

    public func setLiveCaptureEnabled(_ enabled: Bool) async {
        liveCaptureEnabled = enabled

        if enabled {
            _ = ensureMonitor()
            return
        }

        if let monitor {
            await monitor.stopCapturing()
        }
        monitor = nil
    }

    private func currentFPS() async -> Double? {
        if let injectedFPSReader {
            return await injectedFPSReader()
        }

        guard liveCaptureEnabled else {
            return fallbackReader()
        }

        return await ensureMonitor().currentFPS()
    }

    private func ensureMonitor() -> ScreenCaptureFPSMonitor {
        if let monitor {
            return monitor
        }

        let createdMonitor = ScreenCaptureFPSMonitor(fallbackReader: fallbackReader)
        monitor = createdMonitor
        return createdMonitor
    }

    static func readDisplayLinkRefreshRate() -> Double? {
        var displayLink: CVDisplayLink?
        guard CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID(), &displayLink) == kCVReturnSuccess,
              let displayLink else {
            return readNominalRefreshRate()
        }

        let actualRefreshPeriod = CVDisplayLinkGetActualOutputVideoRefreshPeriod(displayLink)
        if actualRefreshPeriod > 0 {
            return 1.0 / actualRefreshPeriod
        }

        let nominalRefreshPeriod = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink)
        if nominalRefreshPeriod.timeValue > 0 {
            return Double(nominalRefreshPeriod.timeScale) / Double(nominalRefreshPeriod.timeValue)
        }

        return readNominalRefreshRate()
    }

    private static func readNominalRefreshRate() -> Double? {
        let displayID = CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return nil
        }

        let refreshRate = mode.refreshRate
        return refreshRate > 0 ? refreshRate : nil
    }
}

actor ScreenCaptureFPSMonitor {
    typealias TimeProvider = @Sendable () -> TimeInterval

    private enum StartState {
        case idle
        case starting
        case running
        case fallback(String)
        case unavailable(String)
    }

    private let timeProvider: TimeProvider
    private let fallbackReader: @Sendable () -> Double?
    private let outputQueue = DispatchQueue(label: "com.pulsebar.fps-output", qos: .userInitiated)
    private var stream: SCStream?
    private var output: ScreenCaptureFPSOutput?
    private var estimator = FPSWindowEstimator()
    private var state: StartState = .idle
    private var lastStartAttempt = Date.distantPast

    init(
        timeProvider: @escaping TimeProvider = { ProcessInfo.processInfo.systemUptime },
        fallbackReader: @escaping @Sendable () -> Double? = { FPSProvider.readDisplayLinkRefreshRate() }
    ) {
        self.timeProvider = timeProvider
        self.fallbackReader = fallbackReader
    }

    func currentFPS() async -> Double? {
        await ensureStartedIfNeeded()

        switch state {
        case .running:
            return estimator.fps(at: timeProvider())
        case .fallback, .unavailable, .idle, .starting:
            return fallbackReader()
        }
    }

    func currentStatusMessage() async -> String? {
        await ensureStartedIfNeeded()

        switch state {
        case .running, .idle, .starting:
            return nil
        case .fallback(let message), .unavailable(let message):
            return message
        }
    }

    func stopCapturing() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        output = nil
        estimator.reset()
        state = .idle
    }

    func recordFrame(status: SCFrameStatus, at timestamp: TimeInterval) {
        switch status {
        case .complete, .started:
            estimator.recordFrame(at: timestamp)
        case .idle, .blank, .suspended:
            estimator.prune(now: timestamp)
        case .stopped:
            estimator.reset()
            state = .idle
        @unknown default:
            estimator.prune(now: timestamp)
        }
    }

    private func ensureStartedIfNeeded() async {
        switch state {
        case .running, .starting:
            return
        case .idle, .fallback, .unavailable:
            break
        }

        let now = Date()
        guard now.timeIntervalSince(lastStartAttempt) >= 10 else {
            return
        }

        lastStartAttempt = now
        state = .starting

        do {
            let shareableContent = try await SCShareableContent.current
            guard let display = shareableContent.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? shareableContent.displays.first else {
                throw ProviderError.unavailable("No display is available for compositor FPS capture.")
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 16
            configuration.height = 16
            configuration.minimumFrameInterval = .zero
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.queueDepth = 1
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let output = ScreenCaptureFPSOutput(
                monitor: self,
                timeProvider: timeProvider
            )
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()

            estimator.reset()
            self.output = output
            self.stream = stream
            state = .running
        } catch {
            let fallback = fallbackReader()
            if fallback != nil {
                state = .fallback(
                    "Using output refresh fallback. Grant Screen Recording to PulseBar or Terminal for live compositor FPS."
                )
            } else {
                state = .unavailable("Live compositor FPS capture unavailable: \(error.localizedDescription)")
            }
        }
    }
}

final class ScreenCaptureFPSOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let monitor: ScreenCaptureFPSMonitor
    private let timeProvider: @Sendable () -> TimeInterval

    init(
        monitor: ScreenCaptureFPSMonitor,
        timeProvider: @escaping @Sendable () -> TimeInterval
    ) {
        self.monitor = monitor
        self.timeProvider = timeProvider
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer) else {
            return
        }

        let status = Self.frameStatus(from: sampleBuffer) ?? .complete
        let timestamp = timeProvider()

        Task {
            await monitor.recordFrame(status: status, at: timestamp)
        }
    }

    private static func frameStatus(from sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[AnyHashable: Any]],
              let attachments = attachmentsArray.first,
              let rawStatus = attachments[SCStreamFrameInfo.status] as? NSNumber else {
            return nil
        }

        return SCFrameStatus(rawValue: rawStatus.intValue)
    }
}

struct FPSWindowEstimator {
    private(set) var frameTimestamps: [TimeInterval] = []
    private let windowLength: TimeInterval

    init(windowLength: TimeInterval = 1.0) {
        self.windowLength = max(windowLength, 0.25)
    }

    mutating func recordFrame(at timestamp: TimeInterval) {
        frameTimestamps.append(timestamp)
        prune(now: timestamp)
    }

    mutating func prune(now: TimeInterval) {
        let cutoff = now - windowLength
        frameTimestamps.removeAll { $0 < cutoff }
    }

    mutating func fps(at timestamp: TimeInterval) -> Double {
        prune(now: timestamp)
        return Double(frameTimestamps.count) / windowLength
    }

    mutating func reset() {
        frameTimestamps.removeAll(keepingCapacity: false)
    }
}
