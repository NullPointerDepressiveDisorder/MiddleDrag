import Foundation
import IOKit
import IOKit.hid
import os

/// Watches for HID multitouch device connections/disconnections using IOKit.
///
/// This solves the problem where MiddleDrag launches at login before a Bluetooth
/// Magic Trackpad has connected. When the trackpad connects seconds later, this
/// watcher detects it and notifies the delegate to restart multitouch monitoring.
///
/// Uses IOHIDManager to monitor for devices matching the "digitizer" usage page,
/// which covers trackpads and other multitouch input devices.
///
/// Thread safety: All IOHIDManager operations are scheduled on the main run loop,
/// so callbacks arrive on the main thread. The class is not marked @MainActor to
/// avoid forcing isolation onto callers like MultitouchManager, which would cascade
/// @MainActor requirements through start()/stop() to all call sites including tests.
final class HIDDeviceWatcher {

    // MARK: - Types

    /// Delegate protocol for device connection events
    protocol Delegate: AnyObject {
        /// Called when a new multitouch-capable HID device is connected
        func hidDeviceWatcherDidDetectDeviceConnection(_ watcher: HIDDeviceWatcher)
        /// Called when a multitouch-capable HID device is disconnected
        func hidDeviceWatcherDidDetectDeviceDisconnection(_ watcher: HIDDeviceWatcher)
    }

    // MARK: - Properties

    weak var delegate: Delegate?

    private var hidManager: IOHIDManager?
    private var isRunning = false

    /// Timestamp when the watcher was started.
    /// IOHIDManager fires matching callbacks for all already-connected devices
    /// when it opens. We ignore connection callbacks arriving within
    /// `initialEnumerationWindow` of start to avoid triggering unnecessary
    /// restarts of MultitouchManager on every launch.
    private var startTime: TimeInterval = 0

    /// How long after start() to ignore connection callbacks (initial enumeration)
    private static let initialEnumerationWindow: TimeInterval = 2.0

    /// Debounce timer to coalesce rapid connect/disconnect events
    /// (e.g., Bluetooth negotiation can fire multiple events)
    private var debounceWorkItem: DispatchWorkItem?

    /// Debounce interval for connection events
    static let debounceInterval: TimeInterval = 1.5

    // MARK: - Lifecycle

    deinit {
        stop()
    }

    // MARK: - Public Interface

    /// Start watching for HID multitouch device connections
    func start() {
        guard !isRunning else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        // Match digitizer devices (trackpads, touch screens)
        // Usage Page 0x0D = Digitizer, Usage 0x05 = Touch Pad
        // Also match Usage 0x04 = Touch Screen for broader coverage
        let trackpadMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 0x0D,  // Digitizer
            kIOHIDDeviceUsageKey as String: 0x05        // Touch Pad
        ]

        let touchScreenMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 0x0D,  // Digitizer
            kIOHIDDeviceUsageKey as String: 0x04        // Touch Screen
        ]

        // Set multiple matching dictionaries to cover different device types
        let matchingArray = [trackpadMatch, touchScreenMatch] as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingArray)

        // Register connection callback
        let connectionContext = unsafe Unmanaged.passUnretained(self).toOpaque()
        unsafe IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, result, sender, device in
                guard let context = unsafe context else { return }
                let watcher = unsafe Unmanaged<HIDDeviceWatcher>.fromOpaque(context).takeUnretainedValue()
                watcher.handleDeviceConnected(device)
            },
            unsafe connectionContext
        )

        // Register disconnection callback
        unsafe IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, result, sender, device in
                guard let context = unsafe context else { return }
                let watcher = unsafe Unmanaged<HIDDeviceWatcher>.fromOpaque(context).takeUnretainedValue()
                watcher.handleDeviceDisconnected(device)
            },
            unsafe connectionContext
        )

        // Schedule on main run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // Open the manager
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            Log.warning("Failed to open IOHIDManager: \(result)", category: .device)
            return
        }

        isRunning = true
        startTime = ProcessInfo.processInfo.systemUptime
        Log.info("HID device watcher started", category: .device)
    }

    /// Stop watching for device connections
    func stop() {
        guard isRunning else { return }

        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidManager = nil
        isRunning = false

        Log.info("HID device watcher stopped", category: .device)
    }

    // MARK: - Private

    private func handleDeviceConnected(_ device: IOHIDDevice) {
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"

        // Ignore devices reported during initial enumeration.
        // IOHIDManager fires matching callbacks for already-connected devices
        // when it first opens — these are not new connections.
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        guard elapsed > Self.initialEnumerationWindow else {
            Log.debug("HID device watcher ignoring initial enumeration: \(productName)", category: .device)
            return
        }

        Log.info("HID multitouch device connected: \(productName)", category: .device)

        // Debounce: Bluetooth negotiation can fire multiple events rapidly
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.delegate?.hidDeviceWatcherDidDetectDeviceConnection(self)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }

    private func handleDeviceDisconnected(_ device: IOHIDDevice) {
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        Log.info("HID multitouch device disconnected: \(productName)", category: .device)

        // Debounce disconnection events similarly
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.delegate?.hidDeviceWatcherDidDetectDeviceDisconnection(self)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }
}
