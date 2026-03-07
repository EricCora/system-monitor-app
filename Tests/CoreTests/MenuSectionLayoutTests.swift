import XCTest
@testable import PulseBarCore

final class MenuSectionLayoutTests: XCTestCase {
    func testReconciledEnsuringVisibleSectionsFallsBackWhenAllSectionsAreHiddenForCPU() {
        let broken = MenuSectionLayout<CPUMenuSectionID>(
            orderedSections: [],
            hiddenSections: Array(CPUMenuSectionID.allCases)
        )

        let reconciled = broken.reconciledEnsuringVisibleSections(fallback: .cpuDefault)

        XCTAssertEqual(reconciled.visibleSections, MenuSectionLayout<CPUMenuSectionID>.cpuDefault.visibleSections)
        XCTAssertTrue(reconciled.hiddenSections.isEmpty)
    }

    func testReconciledEnsuringVisibleSectionsFallsBackWhenAllSectionsAreHiddenForMemory() {
        let broken = MenuSectionLayout<MemoryMenuSectionID>(
            orderedSections: [],
            hiddenSections: Array(MemoryMenuSectionID.allCases)
        )

        let reconciled = broken.reconciledEnsuringVisibleSections(fallback: .memoryDefault)

        XCTAssertEqual(reconciled.visibleSections, MenuSectionLayout<MemoryMenuSectionID>.memoryDefault.visibleSections)
        XCTAssertTrue(reconciled.hiddenSections.isEmpty)
    }
}
