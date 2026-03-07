import Foundation
import XCTest
@testable import PulseBarCore

final class ProcessMemoryProviderTests: XCTestCase {
    private struct FixtureError: Error {}

    func testParsePSOutputSortsAndTrimsTopN() {
        let output = """
          1024 /Applications/A.app/Contents/MacOS/A
          4096 /Applications/B.app/Contents/MacOS/B
          2048 /Applications/C.app/Contents/MacOS/C
        """

        let entries = ProcessMemoryProvider.parsePSOutput(output, maxEntries: 2)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "/Applications/B.app/Contents/MacOS/B")
        XCTAssertEqual(entries[1].name, "/Applications/C.app/Contents/MacOS/C")
        XCTAssertEqual(entries[0].residentBytes, 4_096 * 1_024, accuracy: 0.001)
    }

    func testParsePSOutputSkipsMalformedLines() {
        let output = """
        not-a-number bad line
        2000
        3000    
          512 /usr/bin/valid
        """

        let entries = ProcessMemoryProvider.parsePSOutput(output, maxEntries: 5)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "/usr/bin/valid")
    }

    func testProviderUsesCacheAndHandlesRunnerFailureGracefully() async {
        let runner = RunnerSequence([
            .success("1024 /usr/bin/first\n2048 /usr/bin/second"),
            .failure(FixtureError())
        ])
        let provider = ProcessMemoryProvider(
            maxEntries: 5,
            minCollectionInterval: 1,
            processRunner: { try runner.next() }
        )

        let first = await provider.topProcesses(at: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(runner.callCount(), 1)

        let cached = await provider.topProcesses(at: Date(timeIntervalSince1970: 1_700_000_000.5))
        XCTAssertEqual(cached.count, 2)
        XCTAssertEqual(runner.callCount(), 1)

        let fallback = await provider.topProcesses(at: Date(timeIntervalSince1970: 1_700_000_002))
        XCTAssertEqual(fallback.count, 2)
        XCTAssertEqual(runner.callCount(), 2)
        let status = await provider.statusMessage()
        XCTAssertNotNil(status)
    }
}

private final class RunnerSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<String, Error>]
    private var calls = 0

    init(_ queue: [Result<String, Error>]) {
        self.queue = queue
    }

    func next() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        guard !queue.isEmpty else {
            throw NSError(domain: "RunnerSequence", code: 0)
        }
        return try queue.removeFirst().get()
    }

    func callCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}
