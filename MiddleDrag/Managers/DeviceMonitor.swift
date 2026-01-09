import CoreFoundation
import Foundation

// MARK: - Debug Touch Counter (Debug builds only)

#if DEBUG
    private var touchCount = 0
#endif

// MARK: - Global Callback Storage

// Required because C callbacks cannot capture Swift context
private var gDeviceMonitor: DeviceMonitor?

// MARK: - C Callback Function

private let deviceContactCallback: MTContactCallbackFunction = {
    device, touches, numTouches, timestamp, frame in
    #if DEBUG
        touchCount += 1
        // Log sparingly to avoid performance impact
        if touchCount <= 5 || touchCount % 500 == 0 {
            Log.debug("Touch callback #\(touchCount): \(numTouches) touches", category: .device)
        }
    #endif

    guard let monitor = gDeviceMonitor,
        let touches = touches
    else { return 0 }

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
class DeviceMonitor: TouchDeviceProviding {

    // MARK: - Constants

    /// Delay between unregistering callbacks and stopping devices.
    /// This allows the MultitouchSupport framework's internal thread (mt_ThreadedMTEntry)
    /// to complete any in-flight callback processing before we stop devices.
    /// Value determined empirically: 50ms is sufficient to avoid CFRelease(NULL) crashes
    /// while keeping the stop operation reasonably fast.
    static let frameworkCleanupDelay: TimeInterval = 0.05

    // MARK: - Properties

    /// Delegate to receive touch events
    weak var delegate: DeviceMonitorDelegate?

    private var device: MTDeviceRef?
    private var registeredDevices: Set<UnsafeMutableRawPointer> = []
    private var isRunning = false

    /// Tracks whether this instance owns the global callback reference
    private var ownsGlobalReference = false

    // MARK: - Lifecycle

    init() {
        // Only take ownership of the global reference if no other instance owns it
        // This prevents test interference when multiple DeviceMonitor instances are created
        if gDeviceMonitor == nil {
            gDeviceMonitor = self
            ownsGlobalReference = true
        }
    }

    deinit {
        stop()
        // Only clear the global reference if this instance owns it
        if ownsGlobalReference && gDeviceMonitor === self {
            gDeviceMonitor = nil
        }
    }

    // MARK: - Public Interface

    /// Start monitoring the default multitouch device
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        Log.info("DeviceMonitor starting...", category: .device)

        var deviceCount = 0
        registeredDevices.removeAll()  // Clear any previous registrations

        // Try to get all devices
        if let deviceList = MTDeviceCreateList() {
            let count = CFArrayGetCount(deviceList)
            Log.info("Found \(count) multitouch device(s)", category: .device)

            for i in 0..<count {
                let devicePtr = CFArrayGetValueAtIndex(deviceList, i)
                if let dev = devicePtr {
                    let deviceRef = UnsafeMutableRawPointer(mutating: dev)
                    MTRegisterContactFrameCallback(deviceRef, deviceContactCallback)
                    MTDeviceStart(deviceRef, 0)
                    registeredDevices.insert(deviceRef)
                    deviceCount += 1

                    if device == nil {
                        device = deviceRef
                    }
                }
            }
        } else {
            Log.warning("MTDeviceCreateList returned nil, trying default device", category: .device)
        }

        // Also try the default device if not already registered
        if let defaultDevice = MultitouchFramework.shared.getDefaultDevice() {
            if !registeredDevices.contains(defaultDevice) {
                MTRegisterContactFrameCallback(defaultDevice, deviceContactCallback)
                MTDeviceStart(defaultDevice, 0)
                registeredDevices.insert(defaultDevice)
                deviceCount += 1

                if device == nil {
                    device = defaultDevice
                }
            } else {
                Log.debug("Default device already registered from device list", category: .device)
            }
        }

        guard device != nil else {
            Log.warning(
                "No multitouch device found. MiddleDrag requires a built-in trackpad or Magic Trackpad.",
                category: .device)
            return false
        }

        Log.info("DeviceMonitor started with \(deviceCount) device(s)", category: .device)

        isRunning = true
        return true
    }

    /// Stop monitoring
    /// Safe to call even if start() was never called
    func stop() {
        // Safe to call when not running - just return early
        guard isRunning else { return }

        // IMPORTANT: Unregister callbacks FIRST, before stopping devices
        // This prevents the framework's internal thread (mt_ThreadedMTEntry)
        // from receiving callbacks while we're stopping devices, which causes
        // a race condition crash (CFRelease called with NULL / invalid address)
        for deviceRef in registeredDevices {
            MTUnregisterContactFrameCallback(deviceRef, deviceContactCallback)
        }

        // Brief pause to allow the framework's internal thread to see the
        // unregistered callbacks and complete any in-flight operations.
        // Without this, the framework thread may still be processing a callback
        // when we call MTDeviceStop, causing a race condition.
        Thread.sleep(forTimeInterval: Self.frameworkCleanupDelay)

        // Now safe to stop devices
        for deviceRef in registeredDevices {
            MTDeviceStop(deviceRef)
        }

        registeredDevices.removeAll()
        self.device = nil
        isRunning = false

        Log.info("DeviceMonitor stopped", category: .device)
    }

    // MARK: - Internal

    /// Handle contact from callback and return whether to consume the event
    fileprivate func handleContact(
        device: MTDeviceRef?,
        touches: UnsafeMutableRawPointer,
        count: Int32,
        timestamp: Double
    ) -> Bool {
        // Pass touch data to delegate for gesture processing
        delegate?.deviceMonitor(
            self, didReceiveTouches: touches, count: count, timestamp: timestamp)

        // Never consume at the device level - let all touches through to the system
        // Event suppression is handled by the CGEventTap in MultitouchManager
        // This ensures 4-finger gestures (Mission Control) and 2-finger scrolling work
        return false
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
