import CoreFoundation
import Foundation
import os

// MARK: - Debug Touch Counter (Debug builds only)

#if DEBUG
    nonisolated(unsafe) private var touchCount = 0
#endif

// MARK: - Global Callback Storage

// Required because C callbacks cannot capture Swift context
@unsafe nonisolated(unsafe) private var gDeviceMonitor: DeviceMonitor?

/// Flag to control whether callbacks should be processed.
/// Access to this flag must be synchronized using `gCallbackLock`; it is *not* atomic by itself.
/// This is checked FIRST in the callback, while holding the lock, before accessing gDeviceMonitor,
/// to prevent race conditions during teardown where gDeviceMonitor might be nil or pointing to
/// a deallocated object.
@unsafe nonisolated(unsafe) private var gCallbackEnabled: Bool = false

/// Lock to synchronize callback processing with stop/deinit operations.
/// Uses os_unfair_lock for minimal overhead in high-frequency C callbacks.
/// This is Apple's recommended lock for performance-critical short critical sections.
/// Note: os_unfair_lock must not be moved in memory after initialization - safe here as a global.
@unsafe nonisolated(unsafe) private var gCallbackLock = os_unfair_lock()

/// Reference to a DeviceMonitor pending cleanup.
/// When a DeviceMonitor is stopped, it's moved here to keep it alive until
/// the framework's internal thread has completed any in-flight callbacks.
/// This prevents EXC_BAD_ACCESS from accessing a deallocated object.
@unsafe nonisolated(unsafe) private var gPendingCleanup: DeviceMonitor?

// MARK: - C Callback Function

@unsafe private let deviceContactCallback: MTContactCallbackFunction = {
    device, touches, numTouches, timestamp, frame in
    
    // CRITICAL: Check the enabled flag FIRST, before accessing gDeviceMonitor.
    // This prevents accessing a nil or dangling pointer during teardown.
    // We use the lock to synchronize with stop() which sets the flag to false.
    unsafe os_unfair_lock_lock(&gCallbackLock)
    guard unsafe gCallbackEnabled else {
        unsafe os_unfair_lock_unlock(&gCallbackLock)
        return 0
    }
    // Copy the monitor reference while holding the lock
    guard let monitor = unsafe gDeviceMonitor,
          let touches = unsafe touches
    else {
        unsafe os_unfair_lock_unlock(&gCallbackLock)
        return 0
    }
    unsafe os_unfair_lock_unlock(&gCallbackLock)
    
    #if DEBUG
        unsafe touchCount += 1
        // Log sparingly to avoid performance impact
        if unsafe touchCount <= 5 || touchCount % 500 == 0 {
            Log.debug(unsafe "Touch callback #\(touchCount): \(numTouches) touches", category: .device)
        }
    #endif

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
    /// Value determined empirically: 500ms is sufficient to avoid CFRelease(NULL) crashes
    /// and EXC_BREAKPOINT exceptions during rapid connectivity changes (wifi ↔ none).
    /// Increased from 100ms to handle rapid connectivity toggling that triggers multiple
    /// restart cycles in quick succession.
    static let frameworkCleanupDelay: TimeInterval = 0.5

    // MARK: - Properties

    /// Delegate to receive touch events
    weak var delegate: DeviceMonitorDelegate?

    nonisolated(unsafe) private var device: MTDeviceRef?
    nonisolated(unsafe) private var registeredDevices: Set<UnsafeMutableRawPointer> = unsafe []
    private var isRunning = false

    /// Lock to protect concurrent access to device state during stop/start operations
    private let stateLock = NSLock()

    /// Tracks whether this instance owns the global callback reference
    private var ownsGlobalReference = false

    /// Global lifecycle lock to serialize start/stop across instances.
    /// This prevents concurrent MTDeviceStart/MTDeviceStop calls, which can crash
    /// the MultitouchSupport framework under parallel test execution.
    private static let lifecycleLock = NSLock()

    // MARK: - Lifecycle

    init() {
        // Acquire lock to safely update global state
        unsafe os_unfair_lock_lock(&gCallbackLock)
        
        // Release any previous pending cleanup reference
        // The old instance has had time to complete cleanup by now
        unsafe gPendingCleanup = nil
        
        // Only take ownership of the global reference if no other instance owns it
        // This prevents test interference when multiple DeviceMonitor instances are created
        if unsafe gDeviceMonitor == nil {
            unsafe gDeviceMonitor = unsafe self
            unsafe ownsGlobalReference = true
        }
        
        unsafe os_unfair_lock_unlock(&gCallbackLock)
    }

    deinit {
        // Ensure we've fully stopped monitoring and unregistered callbacks.
        // All global cleanup (gDeviceMonitor, gPendingCleanup, etc.) is handled
        // inside stop() under gCallbackLock to avoid taking locks in deinit.
        unsafe stop()
    }

    // MARK: - Public Interface

    /// Start monitoring the default multitouch device
    @unsafe @discardableResult
    func start() -> Bool {
        unsafe DeviceMonitor.lifecycleLock.lock()
        defer { unsafe DeviceMonitor.lifecycleLock.unlock() }

        unsafe stateLock.lock()
        defer { unsafe stateLock.unlock() }

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
        
        // Enable callbacks AFTER all devices are registered.
        // This ensures gDeviceMonitor is fully set up before callbacks can access it.
        unsafe os_unfair_lock_lock(&gCallbackLock)
        unsafe gCallbackEnabled = true
        unsafe os_unfair_lock_unlock(&gCallbackLock)
        
        return true
    }

    /// Stop monitoring
    /// Safe to call even if start() was never called
    @unsafe func stop() {
        unsafe DeviceMonitor.lifecycleLock.lock()
        unsafe stateLock.lock()

        // Safe to call when not running - just return early
        guard unsafe isRunning else {
            unsafe stateLock.unlock()
            unsafe DeviceMonitor.lifecycleLock.unlock()
            return
        }

        // Mark as not running FIRST to prevent callbacks from processing new events
        unsafe isRunning = false

        // Copy the registered devices to a local variable so we can unlock before sleeping
        let devicesToStop = unsafe registeredDevices
        unsafe registeredDevices.removeAll()
        unsafe self.device = nil

        unsafe stateLock.unlock()

        // CRITICAL: Disable callbacks and handle global cleanup under lock.
        // This must happen BEFORE unregistering callbacks with the framework,
        // because the framework's internal thread (mt_ThreadedMTEntry) may still
        // have in-flight callbacks that could access gDeviceMonitor.
        // The lock synchronizes with the callback to ensure no callback is
        // accessing gDeviceMonitor while we're tearing down.
        unsafe os_unfair_lock_lock(&gCallbackLock)
        unsafe gCallbackEnabled = false
        
        // Handle global cleanup: if this instance owns the global reference,
        // move it to gPendingCleanup to keep it alive until the next DeviceMonitor
        // is created. This prevents EXC_BAD_ACCESS if the framework's internal
        // thread still has a reference to this callback and tries to invoke it.
        if unsafe ownsGlobalReference && gDeviceMonitor === self {
            unsafe gPendingCleanup = gDeviceMonitor
            unsafe gDeviceMonitor = nil
            unsafe ownsGlobalReference = false
        }
        unsafe os_unfair_lock_unlock(&gCallbackLock)

        // IMPORTANT: Unregister callbacks FIRST, before stopping devices
        // This prevents the framework's internal thread (mt_ThreadedMTEntry)
        // from receiving NEW callbacks while we're stopping devices.
        for unsafe deviceRef in unsafe devicesToStop {
            unsafe MTUnregisterContactFrameCallback(deviceRef, deviceContactCallback)
        }

        // Release lifecycle lock before sleeping so other start/stop callers don't
        // block for the full framework cleanup delay.
        unsafe DeviceMonitor.lifecycleLock.unlock()

        // Brief pause to allow the framework's internal thread to complete
        // any in-flight operations AFTER we've disabled callbacks and unregistered.
        // Even with callbacks disabled, we still need to wait for any callback
        // that was already dispatched but hasn't checked the flag yet.
        // This sleep is intentionally done with lock unlocked to avoid blocking other threads.
        unsafe Thread.sleep(forTimeInterval: Self.frameworkCleanupDelay)

        // Reacquire lifecycle lock to serialize MTDeviceStop with MTDeviceStart/MTDeviceStop
        // from any other DeviceMonitor instance.
        unsafe DeviceMonitor.lifecycleLock.lock()
        defer { unsafe DeviceMonitor.lifecycleLock.unlock() }

        // Now safe to stop devices. Acquire lock before each MTDeviceStop to ensure
        // the framework's internal thread (mt_ThreadedMTEntry) cannot access the device
        // during the critical stop operation. This prevents CFRelease(NULL) crashes
        // from the framework trying to release device resources concurrently.
        for unsafe deviceRef in unsafe devicesToStop {
            unsafe os_unfair_lock_lock(&gCallbackLock)
            unsafe MTDeviceStop(deviceRef)
            unsafe os_unfair_lock_unlock(&gCallbackLock)
        }

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
        // Check if we're still running before processing - this prevents processing
        // events during shutdown, which could cause race conditions with the
        // MultitouchSupport framework's internal thread
        unsafe stateLock.lock()
        let stillRunning = unsafe isRunning
        unsafe stateLock.unlock()

        guard stillRunning else { return false }

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
