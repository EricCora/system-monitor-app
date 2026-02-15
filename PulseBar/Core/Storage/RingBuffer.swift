import Foundation

public struct RingBuffer<Element: Sendable>: Sendable {
    private var storage: [Element?]
    private var writeIndex: Int = 0
    public private(set) var count: Int = 0

    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    public mutating func append(_ element: Element) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    public func allElementsInOrder() -> [Element] {
        guard count > 0 else { return [] }

        if count < capacity {
            return storage[0..<count].compactMap { $0 }
        }

        let head = writeIndex
        let tailSlice = storage[head..<capacity]
        let headSlice = storage[0..<head]
        return Array(tailSlice + headSlice).compactMap { $0 }
    }
}
