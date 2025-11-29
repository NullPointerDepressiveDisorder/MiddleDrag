import Foundation
import CoreFoundation
import CoreGraphics

// MARK: - MultitouchSupport Private API Bindings

/// Opaque reference to a multitouch device
typealias MTDeviceRef = UnsafeMutableRawPointer

/// Callback function type for receiving touch frame data
/// - Parameters:
///   - device: The device that generated the touches
///   - touches: Pointer to array of touch data
///   - numTouches: Number of touches in the array
///   - timestamp: Timestamp of the touch frame
///   - frame: Frame number
/// - Returns: 0 to pass through to system, non-zero to consume
typealias MTContactCallbackFunction = @convention(c) (
    MTDeviceRef?,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

// MARK: - Device Management

/// Create a reference to the default multitouch device (built-in trackpad)
@_silgen_name("MTDeviceCreateDefault")
func MTDeviceCreateDefault() -> MTDeviceRef?

// MARK: - Device Control

/// Start the multitouch device
/// - Parameters:
///   - device: Device reference
///   - mode: Start mode (use 0 for normal operation)
@_silgen_name("MTDeviceStart")
func MTDeviceStart(_ device: MTDeviceRef, _ mode: Int32)

/// Stop the multitouch device
@_silgen_name("MTDeviceStop")
func MTDeviceStop(_ device: MTDeviceRef)

/// Check if device is currently running
@_silgen_name("MTDeviceIsRunning")
func MTDeviceIsRunning(_ device: MTDeviceRef) -> Bool

// MARK: - Callback Registration

/// Register a callback to receive touch frame data
@_silgen_name("MTRegisterContactFrameCallback")
func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallbackFunction)

/// Unregister a previously registered callback
@_silgen_name("MTUnregisterContactFrameCallback")
func MTUnregisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallbackFunction?)

// MARK: - Framework Helper

/// Helper class to manage MultitouchSupport framework access
class MultitouchFramework {
    
    /// Shared instance
    static let shared = MultitouchFramework()
    
    private init() {}
    
    /// Check if the multitouch framework is available
    var isAvailable: Bool {
        return MTDeviceCreateDefault() != nil
    }
    
    /// Get the default multitouch device (built-in trackpad)
    /// - Returns: Device reference, or nil if no device available
    func getDefaultDevice() -> MTDeviceRef? {
        return MTDeviceCreateDefault()
    }
}
