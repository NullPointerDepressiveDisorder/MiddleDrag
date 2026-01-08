import Foundation

// MARK: - Touch Device Provider Protocol

/// Protocol for device monitoring to enable dependency injection and testing.
/// Implement this protocol to provide touch input, either from real hardware
/// (DeviceMonitor) or simulated input (for testing).
protocol TouchDeviceProviding: AnyObject {
    /// Delegate that receives touch events
    var delegate: DeviceMonitorDelegate? { get set }

    /// Start monitoring for touch input
    /// - Returns: `true` if at least one multitouch device was successfully registered
    @discardableResult
    func start() -> Bool

    /// Stop monitoring for touch input
    func stop()
}
