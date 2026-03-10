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

    func testLastReturnsNewestElementWithoutMaterializingOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(5)
        buffer.append(6)

        XCTAssertEqual(buffer.last, 6)
    }

    func testSuffixInOrderWalksNewestUntilPredicateFails() {
        var buffer = RingBuffer<Int>(capacity: 5)
        [1, 2, 3, 4, 5].forEach { buffer.append($0) }

        XCTAssertEqual(buffer.suffixInOrder { $0 >= 3 }, [3, 4, 5])
        XCTAssertEqual(buffer.suffixInOrder { $0 >= 5 }, [5])
    }
}
