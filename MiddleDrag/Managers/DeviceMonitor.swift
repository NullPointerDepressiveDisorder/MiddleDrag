import Foundation
import CoreFoundation

// MARK: - Debug Logging

private let debugLogPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("middledrag_touch.log")
private var touchCount = 0

private func logToFile(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: debugLogPath.path) {
            if let handle = try? FileHandle(forWritingTo: debugLogPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: debugLogPath)
        }
    }
}

// MARK: - Global Callback Storage

// Required because C callbacks cannot capture Swift context
private var gDeviceMonitor: DeviceMonitor?

// MARK: - C Callback Function

private let deviceContactCallback: MTContactCallbackFunction = { device, touches, numTouches, timestamp, frame in
    touchCount += 1
    if touchCount <= 5 || touchCount % 100 == 0 {
        logToFile("Touch callback #\(touchCount): \(numTouches) touches")
    }
    
    guard let monitor = gDeviceMonitor,
          let touches = touches else { return 0 }
    
    let shouldConsume = monitor.handleContact(
        device: device,
        touches: touches,
        count: numTouches,
        timestamp: timestamp
    )
    
    // Return 1 to attempt to suppress system gesture handling for 3+ fingers
    return shouldConsume ? 1 : 0
}

// MARK: - DeviceMonitor

/// Monitors multitouch devices and reports touch events
class DeviceMonitor {
    
    // MARK: - Properties
    
    /// Delegate to receive touch events
    weak var delegate: DeviceMonitorDelegate?
    
    private var device: MTDeviceRef?
    private var isRunning = false
    
    // MARK: - Lifecycle
    
    init() {
        gDeviceMonitor = self
    }
    
    deinit {
        stop()
        gDeviceMonitor = nil
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring the default multitouch device
    func start() {
        guard !isRunning else { return }
        
        logToFile("DeviceMonitor.start() called")
        
        // Try to get all devices
        if let deviceList = MTDeviceCreateList() {
            let count = CFArrayGetCount(deviceList)
            logToFile("Found \(count) multitouch device(s)")
            
            for i in 0..<count {
                let devicePtr = CFArrayGetValueAtIndex(deviceList, i)
                if let dev = devicePtr {
                    let deviceRef = UnsafeMutableRawPointer(mutating: dev)
                    logToFile("Registering callback for device \(i): \(deviceRef)")
                    MTRegisterContactFrameCallback(deviceRef, deviceContactCallback)
                    MTDeviceStart(deviceRef, 0)
                    
                    if device == nil {
                        device = deviceRef
                    }
                }
            }
        } else {
            logToFile("MTDeviceCreateList returned nil, trying default")
        }
        
        // Also try the default device
        if let defaultDevice = MultitouchFramework.shared.getDefaultDevice() {
            logToFile("Also registering default device: \(defaultDevice)")
            MTRegisterContactFrameCallback(defaultDevice, deviceContactCallback)
            MTDeviceStart(defaultDevice, 0)
            
            if device == nil {
                device = defaultDevice
            }
        }
        
        logToFile("Device registration complete")
        isRunning = true
        logToFile("DeviceMonitor started successfully")
    }
    
    /// Stop monitoring
    func stop() {
        guard isRunning, let device = device else { return }
        
        MTUnregisterContactFrameCallback(device, deviceContactCallback)
        MTDeviceStop(device)
        
        self.device = nil
        isRunning = false
    }
    
    // MARK: - Internal
    
    /// Handle contact from callback and return whether to consume the event
    fileprivate func handleContact(
        device: MTDeviceRef?,
        touches: UnsafeMutableRawPointer,
        count: Int32,
        timestamp: Double
    ) -> Bool {
        // Count valid touching fingers (state 3 = touching, state 4 = active)
        let touchArray = touches.bindMemory(to: MTTouch.self, capacity: Int(count))
        var validFingerCount = 0
        
        for i in 0..<Int(count) {
            let state = touchArray[i].state
            if state == 3 || state == 4 {
                validFingerCount += 1
            }
        }
        
        // Pass to delegate
        delegate?.deviceMonitor(self, didReceiveTouches: touches, count: count, timestamp: timestamp)
        
        // Consume event if we have 3+ valid fingers
        return validFingerCount >= 3
    }
}

// MARK: - Delegate Protocol

/// Protocol for receiving touch events from the device monitor
protocol DeviceMonitorDelegate: AnyObject {
    /// Called when new touch data is received
    /// - Parameters:
    ///   - monitor: The device monitor
    ///   - touches: Raw pointer to touch data array
    ///   - count: Number of touches
    ///   - timestamp: Timestamp of the touch frame
    func deviceMonitor(
        _ monitor: DeviceMonitor,
        didReceiveTouches touches: UnsafeMutableRawPointer,
        count: Int32,
        timestamp: Double
    )
}
