import Foundation

public enum CPUPaneChart: String, Codable, CaseIterable, Sendable {
    case usage
    case loadAverage
    case gpu
    case framesPerSecond
}

public enum MemoryPaneChart: String, Codable, CaseIterable, Sendable {
    case pressure
    case composition
    case swap
    case pages
}

public enum CPUMenuSectionID: String, Codable, CaseIterable, Sendable {
    case usage
    case processes
    case appleSilicon
    case framesPerSecond
    case loadAverage
    case uptime

    public var label: String {
        switch self {
        case .usage:
            return "CPU"
        case .processes:
            return "Processes"
        case .appleSilicon:
            return "Apple Silicon"
        case .framesPerSecond:
            return "Frames Per Second"
        case .loadAverage:
            return "Load Average"
        case .uptime:
            return "Uptime"
        }
    }
}

public enum MemoryMenuSectionID: String, Codable, CaseIterable, Sendable {
    case pressure
    case memory
    case processes
    case swapMemory
    case pages

    public var label: String {
        switch self {
        case .pressure:
            return "Pressure"
        case .memory:
            return "Memory"
        case .processes:
            return "Processes"
        case .swapMemory:
            return "Swap Memory"
        case .pages:
            return "Pages"
        }
    }
}

public struct MenuSectionLayout<SectionID>: Codable, Sendable, Equatable
where SectionID: Hashable & Codable & CaseIterable & Sendable,
      SectionID.AllCases: RandomAccessCollection,
      SectionID.AllCases.Element == SectionID {
    public var orderedSections: [SectionID]
    public var hiddenSections: [SectionID]

    public init(
        orderedSections: [SectionID]? = nil,
        hiddenSections: [SectionID] = []
    ) {
        self.orderedSections = Self.normalizeOrderedSections(orderedSections ?? Array(SectionID.allCases))
        self.hiddenSections = Self.normalizeHiddenSections(hiddenSections)
    }

    public var visibleSections: [SectionID] {
        let hidden = Set(hiddenSections)
        return orderedSections.filter { !hidden.contains($0) }
    }

    public mutating func setHidden(_ hidden: Bool, for section: SectionID) {
        var hiddenSet = Set(hiddenSections)
        if hidden {
            hiddenSet.insert(section)
        } else {
            hiddenSet.remove(section)
        }
        hiddenSections = Self.normalizeHiddenSections(Array(hiddenSet))
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { orderedSections[$0] }
        orderedSections.remove(atOffsets: source)

        var insertionIndex = destination
        for offset in source where offset < destination {
            insertionIndex -= 1
        }

        orderedSections.insert(contentsOf: moving, at: max(0, min(insertionIndex, orderedSections.count)))
        orderedSections = Self.normalizeOrderedSections(orderedSections)
    }

    public mutating func reconcile() {
        orderedSections = Self.normalizeOrderedSections(orderedSections)
        hiddenSections = Self.normalizeHiddenSections(hiddenSections)
    }

    public func reconciledEnsuringVisibleSections(fallback: MenuSectionLayout<SectionID>? = nil) -> Self {
        var normalized = self
        normalized.reconcile()

        guard normalized.visibleSections.isEmpty else {
            return normalized
        }

        if let fallback {
            var fallbackLayout = fallback
            fallbackLayout.reconcile()
            return fallbackLayout
        }

        return Self()
    }

    private static func normalizeOrderedSections(_ candidate: [SectionID]) -> [SectionID] {
        var seen = Set<SectionID>()
        var normalized: [SectionID] = []

        for section in candidate where !seen.contains(section) {
            seen.insert(section)
            normalized.append(section)
        }

        for section in SectionID.allCases where !seen.contains(section) {
            seen.insert(section)
            normalized.append(section)
        }

        return normalized
    }

    private static func normalizeHiddenSections(_ candidate: [SectionID]) -> [SectionID] {
        let allCases = Set(SectionID.allCases)
        var seen = Set<SectionID>()
        var normalized: [SectionID] = []

        for section in candidate where allCases.contains(section) && !seen.contains(section) {
            seen.insert(section)
            normalized.append(section)
        }

        return normalized
    }
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            remove(at: offset)
        }
    }
}

public extension MenuSectionLayout where SectionID == CPUMenuSectionID {
    static let cpuDefault = MenuSectionLayout(
        orderedSections: [.usage, .processes, .appleSilicon, .framesPerSecond, .loadAverage, .uptime]
    )
}

public extension MenuSectionLayout where SectionID == MemoryMenuSectionID {
    static let memoryDefault = MenuSectionLayout(
        orderedSections: [.pressure, .memory, .processes, .swapMemory, .pages]
    )
}
