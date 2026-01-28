import XCTest

@testable import MiddleDrag

@MainActor
final class ScreenHelperTests: XCTestCase {

    // MARK: - Primary Screen Tests

    func testPrimaryScreenReturnsFirstScreen() {
        let primaryScreen = ScreenHelper.primaryScreen
        let firstScreen = NSScreen.screens.first
        
        XCTAssertEqual(primaryScreen, firstScreen)
    }

    func testPrimaryScreenHeightIsPositive() {
        let height = ScreenHelper.primaryScreenHeight
        
        XCTAssertGreaterThan(height, 0)
    }

    func testGetPrimaryScreenHeightSyncFromMainThread() {
        let syncHeight = ScreenHelper.getPrimaryScreenHeightSync()
        let directHeight = ScreenHelper.primaryScreenHeight
        
        XCTAssertEqual(syncHeight, directHeight)
    }

    // MARK: - Coordinate Conversion Tests

    func testCocoaToQuartzConversion() {
        let height = ScreenHelper.primaryScreenHeight
        let cocoaPoint = CGPoint(x: 100, y: 200)
        
        let quartzPoint = ScreenHelper.cocoaToQuartz(cocoaPoint)
        
        XCTAssertEqual(quartzPoint.x, 100)
        XCTAssertEqual(quartzPoint.y, height - 200)
    }

    func testQuartzToCocoaConversion() {
        let height = ScreenHelper.primaryScreenHeight
        let quartzPoint = CGPoint(x: 100, y: 200)
        
        let cocoaPoint = ScreenHelper.quartzToCocoa(quartzPoint)
        
        XCTAssertEqual(cocoaPoint.x, 100)
        XCTAssertEqual(cocoaPoint.y, height - 200)
    }

    func testCoordinateConversionRoundTrip() {
        let original = CGPoint(x: 150, y: 300)
        
        let quartz = ScreenHelper.cocoaToQuartz(original)
        let backToCocoa = ScreenHelper.quartzToCocoa(quartz)
        
        XCTAssertEqual(backToCocoa.x, original.x, accuracy: 0.001)
        XCTAssertEqual(backToCocoa.y, original.y, accuracy: 0.001)
    }

    func testCocoaYToQuartzY() {
        let height = ScreenHelper.primaryScreenHeight
        let cocoaY: CGFloat = 250
        
        let quartzY = ScreenHelper.cocoaYToQuartzY(cocoaY)
        
        XCTAssertEqual(quartzY, height - cocoaY)
    }

    func testCocoaYToQuartzYSyncFromMainThread() {
        let cocoaY: CGFloat = 250
        
        let syncResult = ScreenHelper.cocoaYToQuartzYSync(cocoaY)
        let directResult = ScreenHelper.cocoaYToQuartzY(cocoaY)
        
        XCTAssertEqual(syncResult, directResult)
    }

    // MARK: - Screen Origin Tests

    func testCocoaOriginAtBottomLeft() {
        let height = ScreenHelper.primaryScreenHeight
        let cocoaBottomLeft = CGPoint(x: 0, y: 0)
        
        let quartzPoint = ScreenHelper.cocoaToQuartz(cocoaBottomLeft)
        
        XCTAssertEqual(quartzPoint.x, 0)
        XCTAssertEqual(quartzPoint.y, height)
    }

    func testCocoaTopLeftMapsToQuartzOrigin() {
        let height = ScreenHelper.primaryScreenHeight
        let cocoaTopLeft = CGPoint(x: 0, y: height)
        
        let quartzPoint = ScreenHelper.cocoaToQuartz(cocoaTopLeft)
        
        XCTAssertEqual(quartzPoint.x, 0)
        XCTAssertEqual(quartzPoint.y, 0)
    }

    // MARK: - Negative Coordinate Tests (Multi-Monitor)

    func testNegativeXCoordinatePreserved() {
        let negativePoint = CGPoint(x: -500, y: 300)
        
        let quartz = ScreenHelper.cocoaToQuartz(negativePoint)
        let backToCocoa = ScreenHelper.quartzToCocoa(quartz)
        
        XCTAssertEqual(backToCocoa.x, negativePoint.x)
    }

    func testNegativeYCoordinateHandled() {
        let height = ScreenHelper.primaryScreenHeight
        let negativeYPoint = CGPoint(x: 100, y: -50)
        
        let quartz = ScreenHelper.cocoaToQuartz(negativeYPoint)
        
        XCTAssertEqual(quartz.y, height + 50)
    }

    // MARK: - Screen Detection Tests

    func testScreenContainingValidCocoaPoint() {
        guard let primaryScreen = ScreenHelper.primaryScreen else {
            XCTFail("No primary screen available")
            return
        }
        
        let centerX = primaryScreen.frame.midX
        let centerY = primaryScreen.frame.midY
        let centerPoint = CGPoint(x: centerX, y: centerY)
        
        let foundScreen = ScreenHelper.screenContaining(cocoaPoint: centerPoint)
        
        XCTAssertNotNil(foundScreen)
    }

    func testScreenContainingPointOutsideAllScreens() {
        let farAwayPoint = CGPoint(x: -100000, y: -100000)
        
        let foundScreen = ScreenHelper.screenContaining(cocoaPoint: farAwayPoint)
        
        XCTAssertNil(foundScreen)
    }

    // MARK: - Mouse Position Tests

    func testCurrentMousePositionQuartzReturnsValidPoint() {
        let position = ScreenHelper.currentMousePositionQuartz()
        
        XCTAssertFalse(position.x.isNaN)
        XCTAssertFalse(position.y.isNaN)
        XCTAssertFalse(position.x.isInfinite)
        XCTAssertFalse(position.y.isInfinite)
    }

    // MARK: - Multi-Monitor Info Tests

    func testHasMultipleMonitorsReturnsBoolean() {
        let hasMultiple = ScreenHelper.hasMultipleMonitors
        let screenCount = NSScreen.screens.count
        
        XCTAssertEqual(hasMultiple, screenCount > 1)
    }

    func testTotalScreenBoundsContainsPrimaryScreen() {
        guard let primaryScreen = ScreenHelper.primaryScreen else {
            XCTFail("No primary screen available")
            return
        }
        
        let totalBounds = ScreenHelper.totalScreenBounds
        
        XCTAssertGreaterThanOrEqual(totalBounds.width, primaryScreen.frame.width)
        XCTAssertGreaterThanOrEqual(totalBounds.height, primaryScreen.frame.height)
    }

    func testTotalScreenBoundsHasPositiveDimensions() {
        let totalBounds = ScreenHelper.totalScreenBounds
        
        XCTAssertGreaterThan(totalBounds.width, 0)
        XCTAssertGreaterThan(totalBounds.height, 0)
    }

    // MARK: - Thread Safety Tests

    func testGetPrimaryScreenHeightSyncFromBackgroundThread() {
        let expectation = expectation(description: "Background thread completion")
        var backgroundHeight: CGFloat = 0
        let mainThreadHeight = ScreenHelper.primaryScreenHeight
        
        DispatchQueue.global(qos: .userInitiated).async {
            backgroundHeight = ScreenHelper.getPrimaryScreenHeightSync()
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        XCTAssertEqual(backgroundHeight, mainThreadHeight)
    }

    func testCocoaYToQuartzYSyncFromBackgroundThread() {
        let expectation = expectation(description: "Background thread completion")
        let testY: CGFloat = 500
        var backgroundResult: CGFloat = 0
        let mainThreadResult = ScreenHelper.cocoaYToQuartzY(testY)
        
        DispatchQueue.global(qos: .userInitiated).async {
            backgroundResult = ScreenHelper.cocoaYToQuartzYSync(testY)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        XCTAssertEqual(backgroundResult, mainThreadResult)
    }

    func testCurrentMousePositionQuartzFromBackgroundThread() {
        let expectation = expectation(description: "Background thread completion")
        var backgroundPosition: CGPoint = .zero
        
        DispatchQueue.global(qos: .userInitiated).async {
            backgroundPosition = ScreenHelper.currentMousePositionQuartz()
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        XCTAssertFalse(backgroundPosition.x.isNaN)
        XCTAssertFalse(backgroundPosition.y.isNaN)
    }
}
