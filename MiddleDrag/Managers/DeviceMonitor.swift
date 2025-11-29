import Foundation
import CoreFoundation

/// Monitors multitouch devices and reports touch events
class DeviceMonitor {
    
    // MARK: - Properties
    
    weak var delegate: DeviceMonitorDelegate?
    
    private var devices: [MTDeviceRef] = []
    private var deviceInfos: [MTDeviceRef: DeviceInfo] = [:]
    private var contactCallback: MTContactCallbackFunction?
    
    // MARK: - Lifecycle
    
    init() {
        setupCallback()
    }
    
    deinit {
        stop()
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
            
            if let callback = contactCallback {
                MTRegisterContactFrameCallback(device, callback)
            }
            
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
            
            if let callback = contactCallback {
                MTUnregisterContactFrameCallback(device, callback)
            }
        }
        
        devices.removeAll()
        deviceInfos.removeAll()
    }
    
    /// Get information about monitored devices
    var monitoredDevices: [DeviceInfo] {
        return Array(deviceInfos.values)
    }
    
    // MARK: - Private Methods
    
    private func setupCallback() {
        // Create callback that captures self weakly
        contactCallback = { [weak self] (device, touches, numTouches, timestamp, frame) in
            guard let self = self,
                  let device = device,
                  let touches = touches else { return 0 }
            
            self.delegate?.deviceMonitor(self, didReceiveTouches: touches, count: numTouches, timestamp: timestamp)
            
            return 0
        }
    }
}

// MARK: - Delegate Protocol

protocol DeviceMonitorDelegate: AnyObject {
    func deviceMonitor(_ monitor: DeviceMonitor, didReceiveTouches touches: UnsafeMutablePointer<MTTouch>, count: Int32, timestamp: Double)
}
