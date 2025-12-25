import XCTest

@testable import MiddleDrag

final class AnalyticsManagerTests: XCTestCase {

    // MARK: - Log Category Tests

    func testLogCategoryGesture() {
        // Verify Log.Category enum values exist and have expected raw values
        XCTAssertEqual(Log.Category.gesture.rawValue, "gesture")
    }

    func testLogCategoryDevice() {
        XCTAssertEqual(Log.Category.device.rawValue, "device")
    }

    func testLogCategoryApp() {
        XCTAssertEqual(Log.Category.app.rawValue, "app")
    }

    func testLogCategoryCrash() {
        XCTAssertEqual(Log.Category.crash.rawValue, "crash")
    }

    // MARK: - Log Category osLog Property Tests

    func testLogCategoryOsLogGesture() {
        let osLog = Log.Category.gesture.osLog
        XCTAssertNotNil(osLog)
    }

    func testLogCategoryOsLogDevice() {
        let osLog = Log.Category.device.osLog
        XCTAssertNotNil(osLog)
    }

    func testLogCategoryOsLogApp() {
        let osLog = Log.Category.app.osLog
        XCTAssertNotNil(osLog)
    }

    func testLogCategoryOsLogCrash() {
        let osLog = Log.Category.crash.osLog
        XCTAssertNotNil(osLog)
    }

    // MARK: - CrashReporter Singleton Tests

    func testCrashReporterIsSingleton() {
        let instance1 = CrashReporter.shared
        let instance2 = CrashReporter.shared
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - CrashReporter Default State Tests

    func testCrashReportingDefaultDisabled() {
        // By default, crash reporting should be disabled (privacy-first)
        // We can only test the getter, not the actual state since UserDefaults might be polluted
        let _ = CrashReporter.shared.isEnabled
        // Just verify property access doesn't crash
    }

    func testPerformanceMonitoringDefaultDisabled() {
        // By default, performance monitoring should be disabled
        let _ = CrashReporter.shared.performanceMonitoringEnabled
        // Just verify property access doesn't crash
    }

    // MARK: - Log Functions Tests

    func testLogDebugDoesNotCrash() {
        // Verify logging functions don't crash
        Log.debug("Test debug message", category: .app)
    }

    func testLogInfoDoesNotCrash() {
        Log.info("Test info message", category: .app)
    }

    func testLogWarningDoesNotCrash() {
        Log.warning("Test warning message", category: .app)
    }

    func testLogErrorDoesNotCrash() {
        Log.error("Test error message", category: .app)
    }

    func testLogErrorWithErrorDoesNotCrash() {
        let testError = NSError(domain: "TestDomain", code: 42, userInfo: nil)
        Log.error("Test error with error object", category: .app, error: testError)
    }

    func testLogFatalDoesNotCrash() {
        Log.fatal("Test fatal message", category: .app)
    }

    func testLogFatalWithErrorDoesNotCrash() {
        let testError = NSError(domain: "TestDomain", code: 42, userInfo: nil)
        Log.fatal("Test fatal with error object", category: .app, error: testError)
    }

    // MARK: - Log Categories Usage Tests

    func testLogAllCategories() {
        Log.debug("Gesture test", category: .gesture)
        Log.debug("Device test", category: .device)
        Log.debug("App test", category: .app)
        // Just verify no crashes with different categories
    }

    func testLogDefaultCategory() {
        // Log functions should use .app as default category
        Log.debug("Test default category")
        Log.info("Test info default")
        Log.warning("Test warning default")
        Log.error("Test error default")
        Log.fatal("Test fatal default")
    }

    func testCrashReporterEnableToggle() {
        // Test enabling
        CrashReporter.shared.isEnabled = true
        XCTAssertTrue(CrashReporter.shared.isEnabled)

        // Test disabling
        CrashReporter.shared.isEnabled = false
        XCTAssertFalse(CrashReporter.shared.isEnabled)
    }

    func testPerformanceMonitoringToggle() {
        // Test enabling
        CrashReporter.shared.performanceMonitoringEnabled = true
        XCTAssertTrue(CrashReporter.shared.performanceMonitoringEnabled)

        // Test disabling
        CrashReporter.shared.performanceMonitoringEnabled = false
        XCTAssertFalse(CrashReporter.shared.performanceMonitoringEnabled)
    }

    func testAnyTelemetryEnabledWithBothOff() {
        CrashReporter.shared.isEnabled = false
        CrashReporter.shared.performanceMonitoringEnabled = false
        XCTAssertFalse(CrashReporter.shared.anyTelemetryEnabled)
    }

    func testAnyTelemetryEnabledWithCrashReportingOn() {
        CrashReporter.shared.isEnabled = true
        CrashReporter.shared.performanceMonitoringEnabled = false
        XCTAssertTrue(CrashReporter.shared.anyTelemetryEnabled)

        // Cleanup
        CrashReporter.shared.isEnabled = false
    }

    func testAnyTelemetryEnabledWithPerformanceMonitoringOn() {
        CrashReporter.shared.isEnabled = false
        CrashReporter.shared.performanceMonitoringEnabled = true
        XCTAssertTrue(CrashReporter.shared.anyTelemetryEnabled)

        // Cleanup
        CrashReporter.shared.performanceMonitoringEnabled = false
    }

    func testAnyTelemetryEnabledWithBothOn() {
        CrashReporter.shared.isEnabled = true
        CrashReporter.shared.performanceMonitoringEnabled = true
        XCTAssertTrue(CrashReporter.shared.anyTelemetryEnabled)

        // Cleanup
        CrashReporter.shared.isEnabled = false
        CrashReporter.shared.performanceMonitoringEnabled = false
    }

    func testInitializeIfEnabledWhenDisabled() {
        CrashReporter.shared.isEnabled = false
        CrashReporter.shared.performanceMonitoringEnabled = false

        // Should not crash when telemetry is disabled
        XCTAssertNoThrow(CrashReporter.shared.initializeIfEnabled())
    }

    func testAddBreadcrumbWhenDisabled() {
        CrashReporter.shared.isEnabled = false

        // Should not crash when adding breadcrumb while disabled
        XCTAssertNoThrow(
            CrashReporter.shared.addBreadcrumbIfEnabled(
                message: "Test breadcrumb",
                category: "test",
                level: .info
            )
        )
    }
}
