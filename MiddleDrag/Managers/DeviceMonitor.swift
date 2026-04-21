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

    // Additional safety check: Verify the monitor instance is still valid and running.
    unsafe monitor.stateLock.lock()
    let monitorIsRunning = unsafe monitor.isRunning
    unsafe monitor.stateLock.unlock()

    guard monitorIsRunning else { return 0 }

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
    static let frameworkCleanupDelay: TimeInterval = 1.0

    /// Interval for refreshing the connected device list while running.
    /// This picks up late-connected devices (for example, a Magic Trackpad).
    static let deviceRefreshInterval: TimeInterval = 2.0

    // MARK: - Properties

    /// Delegate to receive touch events
    weak var delegate: DeviceMonitorDelegate?

    /// Abstracts all MultitouchSupport framework calls for testability.
    let enumerator: DeviceEnumerating

    /// Instance-level cleanup delay; defaults to the static constant.
    /// Tests can pass 0 to avoid sleeping.
    private let cleanupDelay: TimeInterval

    nonisolated(unsafe) private var device: MTDeviceRef?
    /// Registered devices tracked by pointer identity.
    /// The current device identifier logic is pointer-derived, so a simple set
    /// accurately represents the registration state without redundant ID bucketing.
    private var registeredDevicesByID: [Int64: Set<UnsafeMutableRawPointer>] = unsafe [:]
    fileprivate var isRunning = false
    /// Tracks the device count from the last successful enumeration.
    /// Used to skip redundant re-registration when the count is unchanged.
    private(set) var lastKnownDeviceCount: Int = 0
    private var deviceRefreshTimer: DispatchSourceTimer?
    private let deviceRefreshQueue = DispatchQueue(
        label: "com.middledrag.device-monitor.refresh",
        qos: .utility)

    /// Whether the periodic device-refresh timer is currently active.
    var hasActiveRefreshTimer: Bool { unsafe deviceRefreshTimer != nil }

    /// Lock to protect concurrent access to device state during stop/start operations
    fileprivate let stateLock = NSLock()

    /// Tracks whether this instance owns the global callback reference
    private var ownsGlobalReference = false

    /// Global lifecycle lock to serialize start/stop across instances.
    /// This prevents concurrent MTDeviceStart/MTDeviceStop calls, which can crash
    /// the MultitouchSupport framework under parallel test execution.
    private static let lifecycleLock = NSLock()

    /// Result of attempting to register/start a device.
    private enum DeviceRegistrationResult {
        case registered
        case alreadyRegistered
        case invalid
    }

    // MARK: - Lifecycle

    init(enumerator: DeviceEnumerating? = nil, cleanupDelay: TimeInterval = frameworkCleanupDelay) {
        unsafe self.enumerator = unsafe enumerator ?? SystemDeviceEnumerator()
        unsafe self.cleanupDelay = cleanupDelay

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
        guard unsafe !isRunning else {
            unsafe stateLock.unlock()
            return true
        }

        Log.info("DeviceMonitor starting...", category: .device)

        unsafe registeredDevicesByID.removeAll()
        unsafe lastKnownDeviceCount = 0
        unsafe device = nil

        let registrationResult = unsafe registerAvailableDevices(logDeviceCount: true)
        let deviceCount = registrationResult.addedCount

        guard unsafe device != nil else {
            Log.warning(
                "No multitouch device found. MiddleDrag requires a built-in trackpad or Magic Trackpad.",
                category: .device)
            unsafe stateLock.unlock()
            return false
        }

        Log.info("DeviceMonitor started with \(deviceCount) device(s)", category: .device)

        unsafe isRunning = true

        // Enable callbacks AFTER all devices are registered.
        // This ensures gDeviceMonitor is fully set up before callbacks can access it.
        unsafe os_unfair_lock_lock(&gCallbackLock)
        unsafe gCallbackEnabled = true
        unsafe os_unfair_lock_unlock(&gCallbackLock)

        unsafe stateLock.unlock()

        unsafe startDeviceRefreshTimer()

        return true
    }

    /// Stop monitoring
    /// Safe to call even if start() was never called
    @unsafe func stop() {
        unsafe DeviceMonitor.lifecycleLock.lock()
        unsafe stateLock.lock()

        unsafe stopDeviceRefreshTimerLocked()

        // If not running, clean up global reference if we own it, then return.
        // This handles the case where start() failed (no device found) so isRunning
        // was never set to true, but init() already set gDeviceMonitor = self.
        // Without this cleanup, the stale global reference prevents a subsequent
        // DeviceMonitor from registering itself, causing callbacks to be dispatched
        // to this dead instance (which silently drops them because isRunning = false).
        guard unsafe isRunning else {
            if unsafe ownsGlobalReference {
                unsafe os_unfair_lock_lock(&gCallbackLock)
                if unsafe gDeviceMonitor === self {
                    unsafe gDeviceMonitor = nil
                }
                unsafe ownsGlobalReference = false
                unsafe os_unfair_lock_unlock(&gCallbackLock)
            }
            unsafe stateLock.unlock()
            unsafe DeviceMonitor.lifecycleLock.unlock()
            return
        }

        // Mark as not running FIRST to prevent callbacks from processing new events
        unsafe isRunning = false

        // Copy the registered devices to a local variable so we can unlock before sleeping
        let devicesToStop: Set<UnsafeMutableRawPointer> = unsafe Set(registeredDevicesByID.values.flatMap { unsafe $0 })
        unsafe registeredDevicesByID.removeAll()
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
            unsafe enumerator.unregisterContactCallback(deviceRef, deviceContactCallback)
        }

        // Release lifecycle lock before sleeping so other start/stop callers don't
        // block for the full framework cleanup delay.
        unsafe DeviceMonitor.lifecycleLock.unlock()

        // Brief pause to allow the framework's internal thread to complete
        // any in-flight operations AFTER we've disabled callbacks and unregistered.
        // Even with callbacks disabled, we still need to wait for any callback
        // that was already dispatched but hasn't checked the flag yet.
        // This sleep is intentionally done with lock unlocked to avoid blocking other threads.
        if unsafe cleanupDelay > 0 {
            unsafe Thread.sleep(forTimeInterval: cleanupDelay)
        }

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
            unsafe enumerator.stopDevice(deviceRef)
            unsafe os_unfair_lock_unlock(&gCallbackLock)
        }

        Log.info("DeviceMonitor stopped", category: .device)
    }

    // MARK: - Device Refresh

    /// Starts a periodic refresh that registers newly connected multitouch devices.
    private func startDeviceRefreshTimer() {
        unsafe stateLock.lock()
        defer { unsafe stateLock.unlock() }

        guard unsafe isRunning, unsafe deviceRefreshTimer == nil else { return }

        let timer = unsafe DispatchSource.makeTimerSource(queue: deviceRefreshQueue)
        unsafe timer.schedule(
            deadline: .now() + Self.deviceRefreshInterval,
            repeating: Self.deviceRefreshInterval)
        unsafe timer.setEventHandler { [weak self] in
            unsafe self?.refreshConnectedDevices()
        }
        timer.resume()
        unsafe deviceRefreshTimer = timer
    }

    /// Stops and clears the device refresh timer.
    /// Must be called while holding stateLock.
    private func stopDeviceRefreshTimerLocked() {
        guard let timer = unsafe deviceRefreshTimer else { return }
        unsafe deviceRefreshTimer = nil
        timer.cancel()
    }

    /// Tears down old device handles and re-registers the current device set.
    ///
    /// `MTDeviceCreateList()` may return different pointer addresses for the same
    /// physical device on every call, so we cannot correlate old handles with new
    /// ones. A full unregister-stop-then-register-start cycle on every refresh
    /// prevents orphaned callbacks that would otherwise accumulate and deliver
    /// duplicate touch events.
    func refreshConnectedDevices() {
        unsafe DeviceMonitor.lifecycleLock.lock()
        defer { unsafe DeviceMonitor.lifecycleLock.unlock() }

        unsafe stateLock.lock()
        defer { unsafe stateLock.unlock() }

        guard unsafe isRunning else { return }

        let devices = unsafe enumerator.enumerateDevices()
        let previousCount = unsafe lastKnownDeviceCount

        // Optimization to prevent ThreadSanitizer thread leaks:
        // Only tear down and re-register if the device count has actually changed.
        // Repeatedly stopping and starting MTDevice handles every few seconds
        // causes the MultitouchSupport framework to leak internal threads.
        if unsafe devices.count == previousCount {
            return
        }

        // --- tear down every old handle ---
        let oldDevices: Set<UnsafeMutableRawPointer> =
            unsafe Set(registeredDevicesByID.values.flatMap { unsafe $0 })
        if unsafe !oldDevices.isEmpty {
            // Unregister callbacks first (same ordering as stop()).
            for unsafe deviceRef in unsafe oldDevices {
                unsafe enumerator.unregisterContactCallback(deviceRef, deviceContactCallback)
            }
            // Stop each device under gCallbackLock so the framework's internal
            // thread cannot access the handle mid-teardown.
            for unsafe deviceRef in unsafe oldDevices {
                unsafe os_unfair_lock_lock(&gCallbackLock)
                unsafe enumerator.stopDevice(deviceRef)
                unsafe os_unfair_lock_unlock(&gCallbackLock)
            }
            unsafe registeredDevicesByID.removeAll()
            unsafe device = nil
        }

        // --- register fresh handles ---
        let registrationResult = unsafe registerAvailableDevices(
            logDeviceCount: false, prefetchedDevices: devices)

        // Only log when the set of devices actually changed, not on every
        // routine re-registration cycle.
        if unsafe devices.count != previousCount {
            Log.info(
                unsafe "Multitouch device count changed: \(previousCount) → \(devices.count)",
                category: .device)
        }

        _ = registrationResult  // suppress unused-result warning
    }

    /// Enumerates currently available devices and registers any that are not already active.
    /// Must be called while holding `stateLock` and `lifecycleLock`.
    private func registerAvailableDevices(
        logDeviceCount: Bool,
        prefetchedDevices: [MTDeviceRef]? = nil
    ) -> (addedCount: Int, hadAnyDevice: Bool) {
        var addedCount = 0
        var hadAnyDevice = false
        var currentlyConnectedIDs: Set<Int64> = []

        let devices = unsafe prefetchedDevices ?? enumerator.enumerateDevices()
        hadAnyDevice = unsafe !devices.isEmpty
        unsafe lastKnownDeviceCount = unsafe devices.count

        if logDeviceCount {
            Log.info(unsafe "Found \(devices.count) multitouch device(s)", category: .device)
        }

        for unsafe deviceRef in unsafe devices {
            let deviceID = unsafe deviceIdentifier(for: deviceRef)
            currentlyConnectedIDs.insert(deviceID)

            switch unsafe registerDeviceIfNeeded(deviceRef, deviceID: deviceID) {
            case .registered:
                addedCount += 1
            case .alreadyRegistered, .invalid:
                break
            }
        }

        if let defaultDevice = unsafe enumerator.getDefaultDevice() {
            hadAnyDevice = true
            let defaultDeviceID = unsafe deviceIdentifier(for: defaultDevice)
            currentlyConnectedIDs.insert(defaultDeviceID)

            switch unsafe registerDeviceIfNeeded(defaultDevice, deviceID: defaultDeviceID) {
            case .registered:
                addedCount += 1
            case .alreadyRegistered:
                if logDeviceCount {
                    Log.debug("Default device already registered from device list", category: .device)
                }
            case .invalid:
                break
            }
        }

        unsafe pruneDisconnectedDevices(keepingDeviceIDs: currentlyConnectedIDs)

        return (addedCount, hadAnyDevice)
    }

    /// Registers callbacks and starts a device if we are not already monitoring it.
    ///
    /// Device identity is pointer-based and not stable across `MTDeviceCreateList()` calls.
    /// `refreshConnectedDevices()` handles this by tearing down all old handles before
    /// calling `registerAvailableDevices`, so within a single registration pass the
    /// pointer-based IDs are consistent.
    private func registerDeviceIfNeeded(
        _ deviceRef: MTDeviceRef?,
        deviceID: Int64?
    ) -> DeviceRegistrationResult {
        guard let deviceRef = unsafe deviceRef else { return .invalid }

        let resolvedDeviceID = unsafe deviceID ?? deviceIdentifier(for: deviceRef)

        if var knownPointers = unsafe registeredDevicesByID[resolvedDeviceID], unsafe !knownPointers.isEmpty {
            unsafe knownPointers.insert(deviceRef)
            unsafe registeredDevicesByID[resolvedDeviceID] = unsafe knownPointers
            return .alreadyRegistered
        }

        // Always register our callback, even if the framework reports the device as
        // already running (e.g., started by a previous monitor or another process).
        // Without this, we'd miss touch events on devices that are running but don't
        // have our callback registered.
        unsafe enumerator.registerContactCallback(deviceRef, deviceContactCallback)
        if unsafe !enumerator.isDeviceRunning(deviceRef) {
            unsafe enumerator.startDevice(deviceRef)
        }
        unsafe registeredDevicesByID[resolvedDeviceID, default: []].insert(deviceRef)

        if unsafe device == nil {
            unsafe device = unsafe deviceRef
        }

        return .registered
    }

    /// Returns a pointer-based device identifier for the current `MTDeviceRef`.
    /// This identifier is only valid for the lifetime of the underlying pointer
    /// and is not stable across `MTDeviceCreateList()` refreshes.
    private func deviceIdentifier(for deviceRef: MTDeviceRef) -> Int64 {
        return Int64(UInt(bitPattern: deviceRef))
    }

    /// Removes device IDs (and associated pointers) that are no longer present.
    private func pruneDisconnectedDevices(keepingDeviceIDs connectedIDs: Set<Int64>) {
        unsafe registeredDevicesByID = unsafe registeredDevicesByID.filter { id, _ in
            connectedIDs.contains(id)
        }
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
