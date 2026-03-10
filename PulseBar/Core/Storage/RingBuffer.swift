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

    public var last: Element? {
        guard count > 0 else { return nil }
        let index = (writeIndex - 1 + capacity) % capacity
        return storage[index]
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

    public func suffixInOrder(while predicate: (Element) -> Bool) -> [Element] {
        guard count > 0 else { return [] }

        var output: [Element] = []
        output.reserveCapacity(count)

        var remaining = count
        var index = (writeIndex - 1 + capacity) % capacity

        while remaining > 0 {
            guard let element = storage[index], predicate(element) else {
                break
            }

            output.append(element)
            remaining -= 1
            index = (index - 1 + capacity) % capacity
        }

        return output.reversed()
    }
}
