import Foundation
import CoreFoundation
import CoreGraphics

// MARK: - Private API Bindings

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallbackFunction = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

// Device Management
@_silgen_name("MTDeviceCreateList")
func MTDeviceCreateList() -> CFArray

@_silgen_name("MTDeviceCreateDefault")
func MTDeviceCreateDefault() -> MTDeviceRef?

@_silgen_name("MTDeviceRelease")
func MTDeviceRelease(_ device: MTDeviceRef)

// Device Control
@_silgen_name("MTDeviceStart")
func MTDeviceStart(_ device: MTDeviceRef, _ mode: Int32)

@_silgen_name("MTDeviceStop")
func MTDeviceStop(_ device: MTDeviceRef)

@_silgen_name("MTDeviceIsRunning")
func MTDeviceIsRunning(_ device: MTDeviceRef) -> Bool

// Device Properties
@_silgen_name("MTDeviceIsBuiltIn")
func MTDeviceIsBuiltIn(_ device: MTDeviceRef) -> Bool

@_silgen_name("MTDeviceGetSensorSurfaceDimensions")
func MTDeviceGetSensorSurfaceDimensions(_ device: MTDeviceRef) -> CGSize

@_silgen_name("MTDeviceGetFamilyID")
func MTDeviceGetFamilyID(_ device: MTDeviceRef) -> Int32

@_silgen_name("MTDeviceGetDriverType")
func MTDeviceGetDriverType(_ device: MTDeviceRef) -> Int32

// Callback Registration
@_silgen_name("MTRegisterContactFrameCallback")
func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallbackFunction)

@_silgen_name("MTUnregisterContactFrameCallback")
func MTUnregisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallbackFunction?)

// MARK: - Framework Helper

/// Helper class to manage MultitouchSupport framework
class MultitouchFramework {
    static let shared = MultitouchFramework()
    
    private init() {}
    
    /// Check if the framework is available
    var isAvailable: Bool {
        // Try to create a default device to test availability
        if let device = MTDeviceCreateDefault() {
            MTDeviceRelease(device)
            return true
        }
        return false
    }
    
    /// Get all available multitouch devices
    func getDevices() -> [MTDeviceRef] {
        let deviceList = MTDeviceCreateList() as [AnyObject]
        return deviceList.map { unsafeBitCast($0, to: MTDeviceRef.self) }
    }
    
    /// Get device information
    func getDeviceInfo(_ device: MTDeviceRef) -> DeviceInfo {
        return DeviceInfo(
            isBuiltIn: MTDeviceIsBuiltIn(device),
            dimensions: MTDeviceGetSensorSurfaceDimensions(device),
            familyID: MTDeviceGetFamilyID(device),
            driverType: MTDeviceGetDriverType(device)
        )
    }
}

/// Device information structure
struct DeviceInfo {
    let isBuiltIn: Bool
    let dimensions: CGSize
    let familyID: Int32
    let driverType: Int32
    
    var description: String {
        let type = isBuiltIn ? "Built-in Trackpad" : "External Magic Trackpad"
        return "\(type) (\(Int(dimensions.width))x\(Int(dimensions.height)))"
    }
}
