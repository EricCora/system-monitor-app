import XCTest
@testable import PulseBarCore

final class RingBufferTests: XCTestCase {
    func testAppendMaintainsInsertionOrderBeforeCapacity() {
        var buffer = RingBuffer<Int>(capacity: 4)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.allElementsInOrder(), [1, 2, 3])
    }

    func testAppendOverwritesOldestElementAfterCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        buffer.append(4)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.allElementsInOrder(), [2, 3, 4])
    }
}
