import Foundation
import PulseBarCore

struct CPUHistorySnapshot: Sendable {
    let user: [MetricHistoryPoint]
    let system: [MetricHistoryPoint]
    let idle: [MetricHistoryPoint]
    let load1: [MetricHistoryPoint]
    let load5: [MetricHistoryPoint]
    let load15: [MetricHistoryPoint]
    let gpuProcessor: [MetricHistoryPoint]
    let gpuMemory: [MetricHistoryPoint]
    let framesPerSecond: [MetricHistoryPoint]
}

struct MemoryHistorySnapshot: Sendable {
    let composition: [MemoryHistoryPoint]
    let pressure: [MetricHistoryPoint]
    let swap: [MetricHistoryPoint]
    let pageIns: [MetricHistoryPoint]
    let pageOuts: [MetricHistoryPoint]
}
