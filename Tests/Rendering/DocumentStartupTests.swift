#if os(macOS)
import XCTest
@testable import MDReaderRendering

final class DocumentStartupTests: XCTestCase {
    func testFreshLaunchWaitsForRestorationAndCreatesOnlyOnce() {
        var startup = DocumentStartupState()
        startup.launchFinished = true
        XCTAssertFalse(startup.shouldCreateBlank(hasDocuments: false))
        startup.restorationFinished = true
        XCTAssertTrue(startup.shouldCreateBlank(hasDocuments: false))
        XCTAssertFalse(startup.shouldCreateBlank(hasDocuments: false))
    }
    func testRestorationCanFinishBeforeLaunch() {
        var startup = DocumentStartupState()
        startup.restorationFinished = true
        XCTAssertFalse(startup.shouldCreateBlank(hasDocuments: false))
        startup.launchFinished = true
        XCTAssertTrue(startup.shouldCreateBlank(hasDocuments: false))
    }
    func testRestoredOrExplicitlyOpenedDocumentPreventsExtraBlank() {
        var startup = DocumentStartupState()
        startup.launchFinished = true
        startup.restorationFinished = true
        XCTAssertFalse(startup.shouldCreateBlank(hasDocuments: true))
        XCTAssertTrue(startup.resolved)
        XCTAssertFalse(startup.shouldCreateBlank(hasDocuments: false))
    }
}
#endif
