import XCTest
@testable import PulseBarCore

final class ProcessCPUProviderTests: XCTestCase {
    func testParsePSOutputWithPIDSortsAndTrims() {
        let output = """
         501  12.4 /Applications/Codex.app/Contents/MacOS/Codex
         88  85.7 /System/Library/CoreServices/WindowServer
         42  15.1 /usr/bin/loginwindow
        """

        let entries = ProcessCPUProvider.parsePSOutput(output, maxEntries: 2)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].pid, 88)
        XCTAssertEqual(entries[0].name, "/System/Library/CoreServices/WindowServer")
        XCTAssertEqual(entries[0].displayName, "WindowServer")
        XCTAssertEqual(entries[0].cpuPercent, 85.7, accuracy: 0.01)
        XCTAssertEqual(entries[0].id, "pid:88")
        XCTAssertEqual(entries[1].pid, 42)
        XCTAssertEqual(entries[1].displayName, "loginwindow")
    }

    func testParsePSOutputLegacyFormatWithoutPID() {
        let output = """
         12.4 /Applications/Codex.app/Contents/MacOS/Codex
         85.7 /System/Library/CoreServices/WindowServer
         15.1 /usr/bin/loginwindow
        """

        let entries = ProcessCPUProvider.parsePSOutput(output, maxEntries: 2)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].pid, 0)
        XCTAssertEqual(entries[0].name, "/System/Library/CoreServices/WindowServer")
        XCTAssertEqual(entries[0].cpuPercent, 85.7, accuracy: 0.01)
        XCTAssertEqual(entries[1].name, "/usr/bin/loginwindow")
    }

    func testParsePSOutputUsesBundleDisplayName() {
        let output = "501  7.5 /Applications/Codex.app/Contents/MacOS/Codex"
        let entries = ProcessCPUProvider.parsePSOutput(output, maxEntries: 1)
        XCTAssertEqual(entries.first?.displayName, "Codex")
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

    func testCPUProcessEntryDecodesLegacyPayload() throws {
        let json = """
        {"name":"/Applications/Codex.app","cpuPercent":7.5}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(CPUProcessEntry.self, from: json)
        XCTAssertEqual(entry.pid, 0)
        XCTAssertEqual(entry.name, "/Applications/Codex.app")
        XCTAssertEqual(entry.cpuPercent, 7.5)
        XCTAssertEqual(entry.displayName, "Codex")
    }
}
