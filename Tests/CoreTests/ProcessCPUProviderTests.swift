import XCTest
@testable import PulseBarCore

final class ProcessCPUProviderTests: XCTestCase {
    func testParsePSOutputSortsAndTrims() {
        let output = """
         12.4 /Applications/Codex.app/Contents/MacOS/Codex
         85.7 /System/Library/CoreServices/WindowServer
         15.1 /usr/bin/loginwindow
        """

        let entries = ProcessCPUProvider.parsePSOutput(output, maxEntries: 2)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "/System/Library/CoreServices/WindowServer")
        XCTAssertEqual(entries[0].cpuPercent, 85.7, accuracy: 0.01)
        XCTAssertEqual(entries[1].name, "/usr/bin/loginwindow")
    }

    func testParsePSOutputSkipsMalformedLines() {
        let output = """
        not-a-number broken
         12.3
         7.5 /Applications/Codex.app
        """

        let entries = ProcessCPUProvider.parsePSOutput(output, maxEntries: 5)
        XCTAssertEqual(entries, [CPUProcessEntry(name: "/Applications/Codex.app", cpuPercent: 7.5)])
    }
}
