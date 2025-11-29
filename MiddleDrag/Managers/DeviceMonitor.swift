import Foundation
import CoreFoundation

// MARK: - Global callback storage
// This is necessary because C callbacks cannot capture Swift context
private var gDeviceMonitor: DeviceMonitor?

// MARK: - C Callback Function
private let deviceContactCallback: MTContactCallbackFunction = { device, touches, numTouches, timestamp, frame in
    guard let monitor = gDeviceMonitor,
          let touches = touches else { return 0 }
    
    monitor.handleContact(device: device, touches: touches, count: numTouches, timestamp: timestamp)
    return 0
}

/// Monitors multitouch devices and reports touch events
class DeviceMonitor {
    
    // MARK: - Properties
    
    weak var delegate: DeviceMonitorDelegate?
    
    private var devices: [MTDeviceRef] = []
    private var deviceInfos: [MTDeviceRef: DeviceInfo] = [:]
    
    // MARK: - Lifecycle
    
    init() {
        // Store reference for callback
        gDeviceMonitor = self
    }
    
    deinit {
        stop()
        gDeviceMonitor = nil
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring all available devices
    func start() {
        // Get all devices
        devices = MultitouchFramework.shared.getDevices()
        
        // Store device info and register callbacks
        for device in devices {
            let info = MultitouchFramework.shared.getDeviceInfo(device)
            deviceInfos[device] = info
            
            print("Monitoring device: \(info.description)")
            
            // Register the global callback
            MTRegisterContactFrameCallback(device, deviceContactCallback)
            MTDeviceStart(device, 0)
        }
        
        print("Started monitoring \(devices.count) device(s)")
    }
    
    /// Stop monitoring all devices
    func stop() {
        for device in devices {
            if MTDeviceIsRunning(device) {
                MTDeviceStop(device)
            }
            
            // Unregister callback
            MTUnregisterContactFrameCallback(device, nil)
        }
        
        devices.removeAll()
        deviceInfos.removeAll()
    }
    
    /// Get information about monitored devices
    var monitoredDevices: [DeviceInfo] {
        return Array(deviceInfos.values)
    }
    
    // MARK: - Internal callback handler
    
    fileprivate func handleContact(device: MTDeviceRef?, touches: UnsafeMutableRawPointer, count: Int32, timestamp: Double) {
        delegate?.deviceMonitor(self, didReceiveTouches: touches, count: count, timestamp: timestamp)
    }
}

// MARK: - Delegate Protocol

protocol DeviceMonitorDelegate: AnyObject {
    func deviceMonitor(_ monitor: DeviceMonitor, didReceiveTouches touches: UnsafeMutableRawPointer, count: Int32, timestamp: Double)
}
