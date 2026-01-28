import CoreFoundation
import Foundation

// MARK: - Debug Touch Counter (Debug builds only)

#if DEBUG
    nonisolated(unsafe) private var touchCount = 0
#endif

// MARK: - Global Callback Storage

// Required because C callbacks cannot capture Swift context
@unsafe nonisolated(unsafe) private var gDeviceMonitor: DeviceMonitor?

// MARK: - C Callback Function

@unsafe private let deviceContactCallback: MTContactCallbackFunction = {
    device, touches, numTouches, timestamp, frame in
    #if DEBUG
        touchCount += 1
        // Log sparingly to avoid performance impact
        if unsafe touchCount <= 5 || touchCount % 500 == 0 {
            Log.debug(unsafe "Touch callback #\(touchCount): \(numTouches) touches", category: .device)
        }
    #endif

    guard let monitor = unsafe gDeviceMonitor,
          let touches = unsafe touches
    else { return 0 }

    let shouldConsume = unsafe monitor.handleContact(
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
///
/// Note: This class uses unsafe pointer types (UnsafeMutableRawPointer) to interface
/// with the private MultitouchSupport C framework. The unsafe usage is intentional
/// and necessary for low-level touch device access. Properties are marked with
/// `nonisolated(unsafe)` to indicate they store unsafe pointers that are managed
/// outside of Swift's memory safety system.
@unsafe @preconcurrency
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

    nonisolated(unsafe) private var device: MTDeviceRef?
    nonisolated(unsafe) private var registeredDevices: Set<UnsafeMutableRawPointer> = unsafe []
    private var isRunning = false

    /// Tracks whether this instance owns the global callback reference
    private var ownsGlobalReference = false

    // MARK: - Lifecycle

    init() {
        // Only take ownership of the global reference if no other instance owns it
        // This prevents test interference when multiple DeviceMonitor instances are created
        if unsafe gDeviceMonitor == nil {
            unsafe gDeviceMonitor = unsafe self
            unsafe ownsGlobalReference = true
        }
    }

    deinit {
        unsafe stop()
        // Only clear the global reference if this instance owns it
        if unsafe ownsGlobalReference && gDeviceMonitor === self {
            unsafe gDeviceMonitor = nil
        }
    }

    // MARK: - Public Interface

    /// Start monitoring the default multitouch device
    @unsafe @discardableResult
    func start() -> Bool {
        guard unsafe !isRunning else { return true }

        Log.info("DeviceMonitor starting...", category: .device)

        var deviceCount = 0
        unsafe registeredDevices.removeAll()  // Clear any previous registrations

        // Try to get all devices
        if let deviceList = MTDeviceCreateList() {
            let count = CFArrayGetCount(deviceList)
            Log.info("Found \(count) multitouch device(s)", category: .device)

            for i in 0..<count {
                let devicePtr = unsafe CFArrayGetValueAtIndex(deviceList, i)
                if let dev = unsafe devicePtr {
                    let deviceRef = unsafe UnsafeMutableRawPointer(mutating: dev)
                    unsafe MTRegisterContactFrameCallback(deviceRef, deviceContactCallback)
                    unsafe MTDeviceStart(deviceRef, 0)
                    unsafe registeredDevices.insert(deviceRef)
                    deviceCount += 1

                    if unsafe device == nil {
                        unsafe device = unsafe deviceRef
                    }
                }
            }
        } else {
            Log.warning("MTDeviceCreateList returned nil, trying default device", category: .device)
        }

        // Also try the default device if not already registered
        if let defaultDevice = unsafe MultitouchFramework.shared.getDefaultDevice() {
            if unsafe !registeredDevices.contains(defaultDevice) {
                unsafe MTRegisterContactFrameCallback(defaultDevice, deviceContactCallback)
                unsafe MTDeviceStart(defaultDevice, 0)
                unsafe registeredDevices.insert(defaultDevice)
                deviceCount += 1

                if unsafe device == nil {
                    unsafe device = unsafe defaultDevice
                }
            } else {
                Log.debug("Default device already registered from device list", category: .device)
            }
        }

        guard unsafe device != nil else {
            Log.warning(
                "No multitouch device found. MiddleDrag requires a built-in trackpad or Magic Trackpad.",
                category: .device)
            return false
        }

        Log.info("DeviceMonitor started with \(deviceCount) device(s)", category: .device)

        unsafe isRunning = true
        return true
    }

    /// Stop monitoring
    /// Safe to call even if start() was never called
    @unsafe func stop() {
        // Safe to call when not running - just return early
        guard unsafe isRunning else { return }

        // IMPORTANT: Unregister callbacks FIRST, before stopping devices
        // This prevents the framework's internal thread (mt_ThreadedMTEntry)
        // from receiving callbacks while we're stopping devices, which causes
        // a race condition crash (CFRelease called with NULL / invalid address)
        for unsafe deviceRef in unsafe registeredDevices {
            unsafe MTUnregisterContactFrameCallback(deviceRef, deviceContactCallback)
        }

        // Brief pause to allow the framework's internal thread to see the
        // unregistered callbacks and complete any in-flight operations.
        // Without this, the framework thread may still be processing a callback
        // when we call MTDeviceStop, causing a race condition.
        unsafe Thread.sleep(forTimeInterval: Self.frameworkCleanupDelay)

        // Now safe to stop devices
        for unsafe deviceRef in unsafe registeredDevices {
            unsafe MTDeviceStop(deviceRef)
        }
        unsafe registeredDevices.removeAll()
        unsafe self.device = nil
        unsafe isRunning = false

        Log.info("DeviceMonitor stopped", category: .device)
    }

    // MARK: - Internal

    /// Handle contact from callback and return whether to consume the event
    @unsafe @preconcurrency
    fileprivate func handleContact(
        device: MTDeviceRef?,
        touches: UnsafeMutableRawPointer,
        count: Int32,
        timestamp: Double
    ) -> Bool {
        // Pass touch data to delegate for gesture processing
        unsafe delegate?.deviceMonitor(
            self, didReceiveTouches: touches, count: count, timestamp: timestamp)

        // Never consume at the device level - let all touches through to the system
        // Event suppression is handled by the CGEventTap in MultitouchManager
        // This ensures 4-finger gestures (Mission Control) and 2-finger scrolling work
        return false
    }
}

// MARK: - Delegate Protocol

/// Protocol for receiving touch events from the device monitor
@unsafe protocol DeviceMonitorDelegate: AnyObject {
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
