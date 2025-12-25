import Foundation

@testable import MiddleDrag

/// Mock implementation of TouchDeviceProviding for unit testing.
/// Allows simulating touch input without requiring hardware access.
class MockDeviceMonitor: TouchDeviceProviding {

    // MARK: - Protocol Properties

    weak var delegate: DeviceMonitorDelegate?

    // MARK: - Test Tracking Properties

    /// Track if start was called
    var startCalled = false

    /// Track if stop was called
    var stopCalled = false

    /// Track number of times start was called
    var startCallCount = 0

    /// Track number of times stop was called
    var stopCallCount = 0

    // MARK: - Protocol Methods

    func start() {
        startCalled = true
        startCallCount += 1
    }

    func stop() {
        stopCalled = true
        stopCallCount += 1
    }

    // MARK: - Test Helpers

    /// Reset all tracking state
    func reset() {
        startCalled = false
        stopCalled = false
        startCallCount = 0
        stopCallCount = 0
    }

    /// Simulate receiving touch data
    /// - Parameters:
    ///   - touches: Raw pointer to touch data
    ///   - count: Number of touches
    ///   - timestamp: Event timestamp
    func simulateTouches(
        _ touches: UnsafeMutableRawPointer,
        count: Int32,
        timestamp: Double
    ) {
        // Create a temporary DeviceMonitor just for the delegate call signature
        // This is a workaround since the delegate expects DeviceMonitor type
        let tempMonitor = DeviceMonitor()
        delegate?.deviceMonitor(
            tempMonitor,
            didReceiveTouches: touches,
            count: count,
            timestamp: timestamp
        )
    }
}
