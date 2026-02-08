import AppKit
import CoreGraphics
import Foundation

/// Main manager that coordinates multitouch monitoring and gesture recognition
/// Thread-safety: Uses internal gestureQueue for synchronization of touch processing
final class MultitouchManager: @unchecked Sendable {

    // MARK: - Constants

    /// Delay after stopping before restarting devices during wake-from-sleep.
    /// This allows the MultitouchSupport framework's internal thread (mt_ThreadedMTEntry)
    /// to fully complete cleanup before we start new devices.
    /// Value determined empirically: 500ms is sufficient to avoid CFRelease(NULL) crashes
    /// and EXC_BREAKPOINT exceptions during rapid connectivity changes (wifi ↔ none).
    /// Increased from 250ms to handle rapid connectivity toggling that triggers multiple
    /// restart cycles in quick succession.
    static let restartCleanupDelay: TimeInterval = 0.5

    /// Minimum delay between restart operations to prevent race conditions.
    /// When multiple restart triggers occur in rapid succession (e.g., rapid connectivity
    /// changes wifi ↔ none), we debounce them by waiting at least this long after the
    /// last restart completed. This prevents overlapping restart attempts that can expose
    /// race conditions in the MultitouchSupport framework's internal thread.
    static let minimumRestartInterval: TimeInterval = 0.6

    // MARK: - Properties

    /// Current gesture configuration
    var configuration = GestureConfiguration()

    /// Whether gesture recognition is enabled
    private(set) var isEnabled = false

    /// Whether monitoring is active
    private(set) var isMonitoring = false

    /// Whether currently in a three-finger gesture (used for event suppression)
    private(set) var isInThreeFingerGesture = false

    /// Whether actively dragging (more restrictive than isInThreeFingerGesture)
    /// Currently unused for suppression but tracks the drag state precisely
    private(set) var isActivelyDragging = false

    // Timestamp when gesture ended (for delayed event suppression)
    private var gestureEndTime: Double = 0
    // Whether the last gesture that ended was actually active (not cancelled)
    private var lastGestureWasActive: Bool = false
    // Whether current gesture should pass through to system (e.g., title bar drag)
    // Set at gesture start and checked in all delegate methods
    private var shouldPassThroughCurrentGesture: Bool = false
    
    // Whether the force-click conversion (event tap) already performed a middle click
    // recently. When a physical trackpad click occurs with 3 fingers, the force-click
    // path fires performClick() immediately. If the user keeps their fingers on the
    // trackpad, the gesture recognizer may fire a tap as well — potentially across
    // gesture boundaries (the click release can cause brief finger instability that
    // ends and restarts the gesture). A timestamp survives these gesture restarts
    // and naturally expires so subsequent intentional taps still work.
    // Protected by forceClickLock: written from processEvent (event tap thread),
    // read from gestureRecognizerDidTap (gesture queue / main dispatch).
    private let forceClickLock = NSLock()
    private var _lastForceClickTime: TimeInterval = 0
    private var lastForceClickTime: TimeInterval {
        get { forceClickLock.withLock { _lastForceClickTime } }
        set { forceClickLock.withLock { _lastForceClickTime = newValue } }
    }
    private let forceClickDeduplicationWindow: TimeInterval = 0.5  // 500ms

    // Core components
    private let gestureRecognizer = GestureRecognizer()
    private let mouseGenerator = MouseEventGenerator()
    private var deviceMonitor: TouchDeviceProviding?

    // Factory for creating device monitors (injectable for testing)
    private let deviceProviderFactory: () -> TouchDeviceProviding

    // Factory for setting up event tap (injectable for testing)
    // Returns true if setup succeeded, false otherwise
    private var eventTapSetupFactory: (() -> Bool)!

    // Event tap for suppressing system-generated clicks during gestures
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Sleep/wake observers for reinitializing after system wake
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    // HID device watcher for detecting Bluetooth trackpad connections after launch
    private var hidDeviceWatcher: HIDDeviceWatcher?

    // Work item for debouncing restarts
    private var restartWorkItem: DispatchWorkItem?

    // Restart synchronization to prevent race conditions from rapid foreground/background toggling
    private let restartLock = NSLock()
    private var isRestartInProgress = false
    private var lastRestartCompletedTime: TimeInterval = 0

    // Processing queue
    private let gestureQueue = DispatchQueue(label: "com.middledrag.gesture", qos: .userInteractive)

    // Thread-safe finger count tracking
    private let fingerCountLock = NSLock()
    private var _currentFingerCount: Int = 0
    internal var currentFingerCount: Int {
        get {
            fingerCountLock.lock()
            defer { fingerCountLock.unlock() }
            return _currentFingerCount
        }
        set {
            fingerCountLock.lock()
            defer { fingerCountLock.unlock() }
            _currentFingerCount = newValue
        }
    }

    // MARK: - Initialization

    /// Shared production instance
    /// Note: Initialized once at app startup, accessed from main thread and gesture queue
    static let shared = MultitouchManager()

    /// Initialize with optional factories for dependency injection
    /// - Parameters:
    ///   - deviceProviderFactory: Factory that creates TouchDeviceProviding instances.
    ///                            Defaults to creating real DeviceMonitor for production.
    ///   - eventTapSetup: Factory that sets up the event tap. Returns true on success.
    ///                    Defaults to real setupEventTap() for production.
    init(
        deviceProviderFactory: (() -> TouchDeviceProviding)? = nil,
        eventTapSetup: (() -> Bool)? = nil
    ) {
        self.deviceProviderFactory = deviceProviderFactory ?? { unsafe DeviceMonitor() }
        gestureRecognizer.delegate = self

        // Set up event tap factory after self is available
        if let customSetup = eventTapSetup {
            // Use provided mock for testing
            self.eventTapSetupFactory = customSetup
        } else {
            // Use real setupEventTap for production - capture self weakly
            self.eventTapSetupFactory = { [weak self] in
                self?.setupEventTap() ?? false
            }
        }
    }

    // MARK: - Public Interface

    /// Start monitoring for gestures
    @MainActor func start() {
        guard !isMonitoring else { return }

        applyConfiguration()
        let eventTapSuccess = eventTapSetupFactory()

        if !eventTapSuccess {
            Log.error("Failed to start: could not create event tap", category: .device)
            return
        }

        deviceMonitor = deviceProviderFactory()
        unsafe deviceMonitor?.delegate = self

        guard deviceMonitor?.start() == true else {
            Log.warning(
                "No compatible multitouch hardware detected. Gesture monitoring disabled.",
                category: .device)
            deviceMonitor?.stop()
            deviceMonitor = nil
            teardownEventTap()
            isMonitoring = false
            isEnabled = false

            // Start HID device watcher to detect late-connecting devices
            // (e.g., Bluetooth Magic Trackpad connecting after login)
            startHIDDeviceWatcher()
            return
        }

        addSleepWakeObservers()
        startHIDDeviceWatcher()

        isMonitoring = true
        isEnabled = true
    }

    /// Stop monitoring
    @MainActor func stop() {
        // Stop HID device watcher
        stopHIDDeviceWatcher()

        // Clear restart state and cancel any pending restart work item.
        // This must be done under lock to prevent data races with restart().
        restartLock.lock()
        restartWorkItem?.cancel()
        restartWorkItem = nil
        isRestartInProgress = false
        lastRestartCompletedTime = 0
        restartLock.unlock()

        // If not monitoring AND no wake observer (normal stopped state), just return
        // We must proceed if either isMonitoring OR wakeObserver exists (meaning we might be in restart delay)
        guard isMonitoring || wakeObserver != nil else { return }

        removeSleepWakeObservers()

        internalStop()
        isEnabled = false
    }

    /// Restart monitoring (used after sleep/wake)
    func restart() {
        // Allow restart if either:
        // 1. wakeObserver exists (normal production case after successful start)
        // 2. isMonitoring is true (for test scenarios where event tap setup may fail)
        // Using wakeObserver allows retry after failed restart (when isMonitoring=false)
        // because internalStop() sets isMonitoring=false before setupEventTap() runs
        guard wakeObserver != nil || isMonitoring else { return }

        // Prevent concurrent restart operations - this is critical to avoid race conditions
        // when rapid foreground/background toggling triggers multiple restart() calls.
        // The MultitouchSupport framework's internal thread can crash (EXC_BREAKPOINT) if
        // we attempt overlapping stop/start cycles.
        restartLock.lock()

        // If a restart is already in progress, just let it complete
        if isRestartInProgress {
            Log.debug("Restart already in progress, skipping duplicate request", category: .device)
            restartLock.unlock()
            return
        }

        // Check if we're restarting too quickly after a previous restart
        let now = CACurrentMediaTime()
        let timeSinceLastRestart = now - lastRestartCompletedTime
        if lastRestartCompletedTime > 0 && timeSinceLastRestart < Self.minimumRestartInterval {
            Log.debug(unsafe "Restart throttled: \(String(format: "%.3f", timeSinceLastRestart))s since last restart", category: .device)
            // Schedule a delayed restart instead
            restartWorkItem?.cancel()
            let remainingDelay = Self.minimumRestartInterval - timeSinceLastRestart
            let workItem = DispatchWorkItem { [weak self] in
                self?.restart()
            }
            restartWorkItem = workItem
            restartLock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay, execute: workItem)
            return
        }

        isRestartInProgress = true

        // Cancel any pending restart work item while still holding the lock.
        // This prevents data races with stop() which also accesses restartWorkItem.
        restartWorkItem?.cancel()
        restartWorkItem = nil
        restartLock.unlock()

        Log.info("Restarting multitouch monitoring", category: .device)

        // Store current state
        let wasEnabled = isEnabled

        // Stop without removing sleep/wake observers
        internalStop()

        // IMPORTANT: Delay before restarting to allow the MultitouchSupport
        // framework's internal thread (mt_ThreadedMTEntry) to fully complete cleanup.
        // Without this delay, there's a race condition where the framework thread
        // may still be releasing resources when we try to start new devices,
        // causing CFRelease(NULL) crashes or EXC_BREAKPOINT exceptions.

        let workItem = DispatchWorkItem { [weak self] in
            self?.performRestart(wasEnabled: wasEnabled)
        }

        // Store work item under lock to prevent data races
        restartLock.lock()
        restartWorkItem = workItem
        restartLock.unlock()

        // Use async dispatch to avoid blocking the main thread during wake.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.restartCleanupDelay, execute: workItem)
    }

    /// Performs the actual restart after the cleanup delay
    private func performRestart(wasEnabled: Bool) {
        // Verify we should still restart (manager may have been stopped during delay)
        guard wakeObserver != nil else {
            markRestartComplete()
            return
        }

        applyConfiguration()
        let eventTapSuccess = eventTapSetupFactory()

        if !eventTapSuccess {
            Log.error("Failed to restart: could not create event tap", category: .device)
            isMonitoring = false
            isEnabled = false
            removeSleepWakeObservers()
            markRestartComplete()
            return
        }

        deviceMonitor = deviceProviderFactory()
        unsafe deviceMonitor?.delegate = self

        guard deviceMonitor?.start() == true else {
            Log.warning(
                "Restart aborted: no compatible multitouch hardware detected.",
                category: .device)
            deviceMonitor?.stop()
            deviceMonitor = nil
            teardownEventTap()
            isMonitoring = false
            isEnabled = false
            removeSleepWakeObservers()
            markRestartComplete()
            return
        }

        isMonitoring = true
        isEnabled = wasEnabled
        markRestartComplete()
        Log.info("Multitouch monitoring restarted successfully", category: .device)
    }

    /// Mark the restart operation as complete and record the completion time
    private func markRestartComplete() {
        restartLock.lock()
        isRestartInProgress = false
        lastRestartCompletedTime = CACurrentMediaTime()
        restartLock.unlock()
    }

    /// Internal stop without removing sleep/wake observers
    private func internalStop() {
        mouseGenerator.cancelDrag()
        gestureRecognizer.reset()

        // Reset gesture state flags
        isActivelyDragging = false
        isInThreeFingerGesture = false
        currentFingerCount = 0  // Reset finger count on stop
        lastGestureWasActive = false
        gestureEndTime = 0
        lastForceClickTime = 0

        deviceMonitor?.stop()
        deviceMonitor = nil

        teardownEventTap()

        isMonitoring = false
    }

    // MARK: - Sleep/Wake Handling

    private func addSleepWakeObservers() {
        guard sleepObserver == nil, wakeObserver == nil else { return }

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Log.info("System going to sleep", category: .device)
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.info("System woke from sleep, restarting monitoring", category: .device)
            self?.restart()
        }
    }

    private func removeSleepWakeObservers() {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    // MARK: - HID Device Watching

    @MainActor private func startHIDDeviceWatcher() {
        guard hidDeviceWatcher == nil else { return }
        let watcher = HIDDeviceWatcher()
        watcher.delegate = self
        watcher.start()
        hidDeviceWatcher = watcher
    }

    @MainActor private func stopHIDDeviceWatcher() {
        hidDeviceWatcher?.stop()
        hidDeviceWatcher = nil
    }

    /// Attempt to start monitoring after a new HID device is detected.
    /// Unlike restart(), this handles the case where monitoring was never
    /// successfully started (e.g., no devices at launch).
    private func attemptStartAfterDeviceConnection() {
        if isMonitoring {
            // Already monitoring — restart to pick up the new device
            Log.info("New device detected while monitoring - restarting to pick up device", category: .device)
            restart()
        } else {
            // Not monitoring — this is likely the initial launch case where
            // no devices were found. Try a fresh start.
            Log.info("New device detected - attempting initial start", category: .device)

            applyConfiguration()
            let eventTapSuccess = eventTapSetupFactory()

            if !eventTapSuccess {
                Log.error("Failed to start after device connection: could not create event tap", category: .device)
                return
            }

            deviceMonitor = deviceProviderFactory()
            unsafe deviceMonitor?.delegate = self

            guard deviceMonitor?.start() == true else {
                Log.warning(
                    "Device connection detected but still no compatible multitouch hardware.",
                    category: .device)
                deviceMonitor?.stop()
                deviceMonitor = nil
                teardownEventTap()
                return
            }

            addSleepWakeObservers()

            isMonitoring = true
            isEnabled = true
            Log.info("Multitouch monitoring started after device connection", category: .device)

            // Update the menu bar UI to reflect the new state
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .deviceConnectionStateChanged,
                    object: nil
                )
            }
        }
    }

    /// Toggle enabled state
    func toggleEnabled() {
        isEnabled.toggle()

        if !isEnabled {
            mouseGenerator.cancelDrag()
            gestureRecognizer.reset()
            currentFingerCount = 0  // Reset finger count when disabled
            lastGestureWasActive = false
            gestureEndTime = 0
            lastForceClickTime = 0
        }
    }

    /// Update configuration
    func updateConfiguration(_ config: GestureConfiguration) {
        configuration = config
        applyConfiguration()
    }
    
    /// Force release any stuck middle-drag state
    /// This can be called manually by the user (e.g., from menu bar) if they notice
    /// the middle button is stuck. It sends a MIDDLE_UP event regardless of current state.
    func forceReleaseStuckDrag() {
        // Dispatch to main thread to avoid data races with gesture state updates
        // which are also dispatched to main thread (see GestureRecognizerDelegate methods)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            Log.info("Force releasing stuck drag (user triggered)", category: .gesture)
            
            // Reset all internal state
            self.isActivelyDragging = false
            self.isInThreeFingerGesture = false
            self.gestureEndTime = CACurrentMediaTime()
            self.lastGestureWasActive = false
            
            // Force send MIDDLE_UP unconditionally
            // Unlike cancelDrag(), this always sends UP even if internal state is already false
            self.mouseGenerator.forceMiddleMouseUp()
            
            // Also reset the gesture recognizer to ensure clean state
            self.gestureRecognizer.reset()
        }
    }

    // MARK: - Event Tap

    @discardableResult
    private func setupEventTap() -> Bool {
        // Build event mask for mouse events to intercept
        // We ONLY intercept mouse events - NOT gesture events
        // Intercepting gesture events (even just registering for them) causes
        // macOS to freeze when doing 4-finger Mission Control swipes
        var eventMask: CGEventMask = 0
        eventMask |= (1 << CGEventType.leftMouseDown.rawValue)
        eventMask |= (1 << CGEventType.leftMouseUp.rawValue)
        eventMask |= (1 << CGEventType.leftMouseDragged.rawValue)
        eventMask |= (1 << CGEventType.rightMouseDown.rawValue)
        eventMask |= (1 << CGEventType.rightMouseUp.rawValue)
        eventMask |= (1 << CGEventType.rightMouseDragged.rawValue)
        eventMask |= (1 << CGEventType.otherMouseDown.rawValue)
        eventMask |= (1 << CGEventType.otherMouseUp.rawValue)
        eventMask |= (1 << CGEventType.otherMouseDragged.rawValue)

        // NOTE: We intentionally do NOT intercept gesture events (29-32)
        // Doing so causes Mission Control and other system gestures to freeze

        let refcon = unsafe Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = unsafe CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = unsafe refcon else {
                        return unsafe Unmanaged.passUnretained(event)
                    }
                    let manager = unsafe Unmanaged<MultitouchManager>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    return unsafe manager.handleEventTapCallback(
                        proxy: proxy, type: type, event: event)
                },
                userInfo: unsafe refcon
            )
        else {
            Log.warning("Could not create event tap", category: .device)
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            // Explicitly use main run loop to match where state updates are dispatched
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func teardownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    private func handleEventTapCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        return unsafe processEvent(event, type: type)
    }

    /// Internal method for processing events to allow unit testing
    internal func processEvent(
        _ event: CGEvent,
        type: CGEventType
    ) -> Unmanaged<CGEvent>? {

        // Re-enable tap if it was disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return unsafe Unmanaged.passUnretained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        let now = CACurrentMediaTime()
        let timeSinceGestureEnd = now - gestureEndTime

        // Allow our own middle mouse events through
        let isMiddleButton = buttonNumber == 2
        let isLeftButton = buttonNumber == 0

        // Identification of our own events using Magic Number (0x4D44 = 'MD')
        // We tagging events in MouseEventGenerator with this value
        let userData = event.getIntegerValueField(.eventSourceUserData)
        let isOurEvent = userData == 0x4D44

        // Check if modifier key is required and currently held
        // This ensures we only suppress events when a valid gesture is actually active
        let modifierFlags = CGEventSource.flagsState(.hidSystemState)
        let modifierKeyHeld: Bool
        if configuration.requireModifierKey {
            switch configuration.modifierKeyType {
            case .shift:
                modifierKeyHeld = modifierFlags.contains(.maskShift)
            case .control:
                modifierKeyHeld = modifierFlags.contains(.maskControl)
            case .option:
                modifierKeyHeld = modifierFlags.contains(.maskAlternate)
            case .command:
                modifierKeyHeld = modifierFlags.contains(.maskCommand)
            }
        } else {
            modifierKeyHeld = true  // No modifier required, so always "held"
        }

        // Only consider gesture active if:
        // 1. We're actually in a three-finger gesture (flag set by delegate callbacks)
        // 2. AND modifier key requirement is met (if required)
        // We use isInThreeFingerGesture and isActivelyDragging instead of checking
        // fingerCountSafe or gestureRecognizer.state directly, because those flags
        // are only set when a valid gesture actually starts (respecting modifier keys)
        let gestureActive = modifierKeyHeld && (isInThreeFingerGesture || isActivelyDragging)

        if isMiddleButton && isOurEvent {
            return unsafe Unmanaged.passUnretained(event)
        }

        // Force click support: convert left clicks to middle clicks when 3+ fingers are on trackpad
        // This works based on raw finger count, not gesture activation state, so force clicks
        // work even when gestures are cancelled (e.g., modifier key not held)
        // However, don't perform force clicks during an active drag to avoid interference
        // Also skip if we're passing through to system (e.g., title bar drag)
        let hasThreeOrMoreFingers = currentFingerCount >= 3
        if hasThreeOrMoreFingers && isLeftButton && !isOurEvent && !isActivelyDragging && !shouldPassThroughCurrentGesture {
            // Check event type - we want to handle both down and up
            if type == .leftMouseDown || type == .leftMouseUp {
                // Perform middle click instead
                if type == .leftMouseDown {
                    lastForceClickTime = CACurrentMediaTime()
                    mouseGenerator.performClick()
                }
                // Suppress the original left click
                return nil
            }
        }

        // Suppress left/right events during gesture or shortly after
        // Only suppress after gesture end if the last gesture was actually active (not cancelled)
        let shouldSuppress = gestureActive || (timeSinceGestureEnd < 0.15 && lastGestureWasActive)

        if shouldSuppress && !isMiddleButton {
            return nil  // Suppress the event
        }

        return unsafe Unmanaged.passUnretained(event)
    }

    // MARK: - Private Methods

    private func applyConfiguration() {
        gestureRecognizer.configuration = configuration
        mouseGenerator.smoothingFactor = configuration.smoothingFactor
        mouseGenerator.minimumMovementThreshold = CGFloat(configuration.minimumMovementThreshold)
    }

    /// Thread-safe check if cursor is over desktop (no window underneath)
    /// - Returns: true if cursor is over desktop, false if over a window
    /// - Note: WindowHelper uses AppKit APIs (NSEvent.mouseLocation, NSScreen.main)
    ///         which must be called from the main thread
    private func shouldSkipGestureForDesktop() -> Bool {
        guard configuration.ignoreDesktop else { return false }

        if Thread.isMainThread {
            return MainActor.assumeIsolated { WindowHelper.isCursorOverDesktop() }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { WindowHelper.isCursorOverDesktop() }
            }
        }
    }

    /// Thread-safe check if cursor is over a window's title bar
    /// - Returns: true if cursor is in title bar, false otherwise
    /// - Note: Uses thread-safe CGEvent APIs, can be called from any thread
    private func shouldSkipGestureForTitleBar() -> Bool {
        guard configuration.passThroughTitleBar else { return false }

        let titleBarHeight = configuration.titleBarHeight
        // Use thread-safe version that doesn't require main thread
        return WindowHelper.isCursorInTitleBarThreadSafe(titleBarHeight: titleBarHeight)
    }
}

// MARK: - DeviceMonitorDelegate

extension MultitouchManager: DeviceMonitorDelegate {
    func deviceMonitor(
        _ monitor: DeviceMonitor,
        didReceiveTouches touches: UnsafeMutableRawPointer,
        count: Int32,
        timestamp: Double
    ) {
        guard isEnabled else { return }

        // Update safe finger count immediately
        currentFingerCount = Int(count)

        // Capture modifier flags before dispatching to gesture queue
        // Note: This callback runs on a framework-managed background thread, not main thread
        // CGEventSource.flagsState is thread-safe and can be called from any thread
        let modifierFlags = CGEventSource.flagsState(.hidSystemState)

        // CRITICAL: Copy touch data synchronously during this callback.
        // The touches pointer is only valid for the duration of this callback.
        // The MultitouchSupport framework owns this memory and may free/reuse it
        // immediately after the callback returns. We MUST copy the data before
        // dispatching to the gesture queue.
        let touchCount = Int(count)
        let touchDataCopy: [MTTouch]
        if touchCount > 0 {
            let touchArray = unsafe touches.bindMemory(to: MTTouch.self, capacity: touchCount)
            // Create a Swift array copy of the touch data
            touchDataCopy = (0..<touchCount).map { unsafe touchArray[$0] }
        } else {
            touchDataCopy = []
        }

        // Gesture recognition and finger counting is done inside processTouches
        // State updates happen in delegate callbacks dispatched to main thread
        // IMPORTANT: We must call processTouches even with zero touches so the
        // gesture recognizer can properly end gestures via stableFrameCount logic.
        gestureQueue.async { [weak self] in
            if touchDataCopy.isEmpty {
                // Zero touches - still need to notify gesture recognizer so it can
                // properly end active gestures via stableFrameCount mechanism
                unsafe self?.gestureRecognizer.processTouches(
                    UnsafeMutableRawPointer(bitPattern: 1)!, // Non-null placeholder, won't be dereferenced when count=0
                    count: 0,
                    timestamp: timestamp,
                    modifierFlags: modifierFlags)
            } else {
                // Use withUnsafeBufferPointer to get a pointer to our copied data
                unsafe touchDataCopy.withUnsafeBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else { return }
                    let rawPointer = unsafe UnsafeMutableRawPointer(mutating: baseAddress)
                    unsafe self?.gestureRecognizer.processTouches(
                        rawPointer, count: touchCount, timestamp: timestamp, modifierFlags: modifierFlags)
                }
            }
        }
    }
}

// MARK: - GestureRecognizerDelegate

extension MultitouchManager: GestureRecognizerDelegate {
    // NOTE: State updates are dispatched async to main thread for thread safety.
    // There's a brief window (~1 frame) where events could pass through before
    // suppression activates. Using DispatchQueue.main.sync would eliminate this
    // but could cause UI blocking on the gesture processing queue. The current
    // approach trades minimal event leakage for responsiveness.

    func gestureRecognizerDidStart(_ recognizer: GestureRecognizer, at position: MTPoint) {
        // Check title bar passthrough at gesture START to decide if we should handle this gesture
        // This must happen before setting isInThreeFingerGesture to allow system to handle it
        if shouldSkipGestureForTitleBar() {
            Log.debug("gestureRecognizerDidStart: Title bar detected - passing through to system", category: .gesture)
            shouldPassThroughCurrentGesture = true
            // Don't set isInThreeFingerGesture - let system handle the gesture
            return
        }
        
        shouldPassThroughCurrentGesture = false
        Log.debug("gestureRecognizerDidStart: Normal gesture - handling ourselves", category: .gesture)
        DispatchQueue.main.async { [weak self] in
            self?.isInThreeFingerGesture = true
        }
    }

    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer) {
        // Skip if this gesture is being passed through to system (e.g., title bar drag)
        if shouldPassThroughCurrentGesture {
            shouldPassThroughCurrentGesture = false
            return
        }
        
        // Skip if a force-click (physical trackpad click with 3 fingers) recently
        // performed a middle click. Without this, the user gets a double click:
        // one from the force-click conversion in processEvent, and another from
        // this tap detection when they lift their fingers. Uses a timestamp rather
        // than a boolean flag because the click release can cause brief finger
        // instability that ends and restarts the gesture (resetting per-gesture state).
        let timeSinceForceClick = CACurrentMediaTime() - lastForceClickTime
        if timeSinceForceClick < forceClickDeduplicationWindow {
            // Still reset gesture state
            DispatchQueue.main.async { [weak self] in
                self?.isInThreeFingerGesture = false
                self?.isActivelyDragging = false
                self?.gestureEndTime = CACurrentMediaTime()
                self?.lastGestureWasActive = true  // Force click was active
            }
            return
        }
        
        // Check if tap to click is enabled
        guard configuration.tapToClickEnabled else {
            // Reset state even if tap is disabled
            DispatchQueue.main.async { [weak self] in
                self?.isInThreeFingerGesture = false
                self?.gestureEndTime = CACurrentMediaTime()
                self?.lastGestureWasActive = false  // Tap was disabled, so not active
            }
            return
        }

        // Check if cursor is over desktop when ignoreDesktop is enabled
        // Note: This check happens BEFORE the window size filter. If both features are enabled,
        //       ignoreDesktop takes precedence - gestures over desktop are blocked regardless
        //       of window size filter settings. This prevents the behavioral inconsistency where
        //       windowAtCursorMeetsMinimumSize would return true for desktop (no window found).
        if shouldSkipGestureForDesktop() {
            // Cursor is over desktop - skip tap
            DispatchQueue.main.async { [weak self] in
                self?.isInThreeFingerGesture = false
                self?.gestureEndTime = CACurrentMediaTime()
                self?.lastGestureWasActive = false
            }
            return
        }

        // Check window size filter before performing tap
        // Note: WindowHelper uses AppKit APIs (NSEvent.mouseLocation, NSScreen.main)
        // which must be called from the main thread
        let shouldPerformTap: Bool
        if configuration.minimumWindowSizeFilterEnabled {
            let minWidth = configuration.minimumWindowWidth
            let minHeight = configuration.minimumWindowHeight
            // Avoid deadlock: call directly if already on main thread, otherwise sync
            if Thread.isMainThread {
                shouldPerformTap = MainActor.assumeIsolated {
                    WindowHelper.windowAtCursorMeetsMinimumSize(minWidth: minWidth, minHeight: minHeight)
                }
            } else {
                shouldPerformTap = DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        WindowHelper.windowAtCursorMeetsMinimumSize(minWidth: minWidth, minHeight: minHeight)
                    }
                }
            }
        } else {
            shouldPerformTap = true
        }

        // Always reset state regardless of whether tap is performed
        DispatchQueue.main.async { [weak self] in
            self?.isInThreeFingerGesture = false
            self?.isActivelyDragging = false  // Ensure drag state is cleared
            self?.gestureEndTime = CACurrentMediaTime()
            self?.lastGestureWasActive = shouldPerformTap  // Active only if tap was performed
        }

        // Cancel any active drag before performing click to prevent sticky window bug
        // This handles edge cases where a drag might have been started but not properly ended
        mouseGenerator.cancelDrag()

        // Only perform the click if window meets size requirements
        if shouldPerformTap {
            mouseGenerator.performClick()
        }
    }

    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer) {
        // Skip if this gesture is being passed through to system (e.g., title bar drag)
        if shouldPassThroughCurrentGesture {
            return  // Don't reset flag here - will be reset when gesture ends
        }
        
        guard configuration.middleDragEnabled else {
            // Reset state even if drag is disabled
            DispatchQueue.main.async { [weak self] in
                self?.isInThreeFingerGesture = false
                self?.gestureEndTime = CACurrentMediaTime()
                self?.lastGestureWasActive = false  // Drag was disabled, so not active
            }
            return
        }

        // Check if cursor is over desktop when ignoreDesktop is enabled
        // Note: This check happens BEFORE the window size filter. If both features are enabled,
        //       ignoreDesktop takes precedence - gestures over desktop are blocked regardless
        //       of window size filter settings. This prevents the behavioral inconsistency where
        //       windowAtCursorMeetsMinimumSize would return true for desktop (no window found).
        if shouldSkipGestureForDesktop() {
            // Cursor is over desktop - skip drag
            DispatchQueue.main.async { [weak self] in
                self?.isInThreeFingerGesture = false
                self?.gestureEndTime = CACurrentMediaTime()
                self?.lastGestureWasActive = false
            }
            return
        }

        // Check window size filter before starting drag
        // Note: WindowHelper uses AppKit APIs (NSEvent.mouseLocation, NSScreen.main)
        // which must be called from the main thread
        if configuration.minimumWindowSizeFilterEnabled {
            let minWidth = configuration.minimumWindowWidth
            let minHeight = configuration.minimumWindowHeight
            // Avoid deadlock: call directly if already on main thread, otherwise sync
            let meetsMinimumSize: Bool
            if Thread.isMainThread {
                meetsMinimumSize = MainActor.assumeIsolated {
                    WindowHelper.windowAtCursorMeetsMinimumSize(minWidth: minWidth, minHeight: minHeight)
                }
            } else {
                meetsMinimumSize = DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        WindowHelper.windowAtCursorMeetsMinimumSize(minWidth: minWidth, minHeight: minHeight)
                    }
                }
            }
            if !meetsMinimumSize {
                // Window too small - skip drag
                DispatchQueue.main.async { [weak self] in
                    self?.isInThreeFingerGesture = false
                    self?.gestureEndTime = CACurrentMediaTime()
                    self?.lastGestureWasActive = false
                }
                return
            }
        }

        // Set state ONLY after all checks pass and drag will actually start
        DispatchQueue.main.async { [weak self] in
            self?.isActivelyDragging = true
        }

        let mouseLocation = MouseEventGenerator.currentMouseLocation
        mouseGenerator.startDrag(at: mouseLocation)
    }

    func gestureRecognizerDidUpdateDragging(_ recognizer: GestureRecognizer, with data: GestureData)
    {
        // Skip if this gesture is being passed through to system
        guard !shouldPassThroughCurrentGesture else { return }
        guard configuration.middleDragEnabled else { return }
        let delta = data.frameDelta(from: configuration)

        guard delta.x != 0 || delta.y != 0 else { return }

        let baseScaleFactor: CGFloat = 1600.0 * CGFloat(configuration.sensitivity)
        // Use symmetric scaling for both axes - previous horizontal restrictions caused
        // glitchy and restricted movement by reducing horizontal by 65% and capping at 18px
        let scaledDeltaX = delta.x * baseScaleFactor
        let scaledDeltaY = -delta.y * baseScaleFactor  // Invert Y for natural movement

        mouseGenerator.updateDrag(deltaX: scaledDeltaX, deltaY: scaledDeltaY)
    }

    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer) {
        // Reset pass-through flag
        let wasPassingThrough = shouldPassThroughCurrentGesture
        shouldPassThroughCurrentGesture = false
        
        // If we were passing through, don't update our state or send events
        if wasPassingThrough {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isActivelyDragging = false
            self?.isInThreeFingerGesture = false
            self?.gestureEndTime = CACurrentMediaTime()
            self?.lastGestureWasActive = true  // Drag ended normally, was active
        }
        // Always call endDrag to ensure mouse generator state is cleaned up
        // even if middleDragEnabled was toggled off during an active drag
        mouseGenerator.endDrag()
    }

    func gestureRecognizerDidCancel(_ recognizer: GestureRecognizer) {
        // Cancel from early state (e.g., possibleTap) - reset state
        shouldPassThroughCurrentGesture = false
        DispatchQueue.main.async { [weak self] in
            self?.isInThreeFingerGesture = false
            self?.gestureEndTime = CACurrentMediaTime()
            self?.lastGestureWasActive = false  // Gesture was cancelled, not active
        }
    }

    func gestureRecognizerDidCancelDragging(_ recognizer: GestureRecognizer) {
        // Cancel drag immediately - user added 4th finger for Mission Control
        shouldPassThroughCurrentGesture = false
        DispatchQueue.main.async { [weak self] in
            self?.isActivelyDragging = false
            self?.isInThreeFingerGesture = false
            self?.gestureEndTime = CACurrentMediaTime()
            self?.lastGestureWasActive = false  // Drag was cancelled, not active
        }
        mouseGenerator.cancelDrag()
    }
}


// MARK: - HIDDeviceWatcherDelegate

extension MultitouchManager: HIDDeviceWatcher.Delegate {
    func hidDeviceWatcherDidDetectDeviceConnection(_ watcher: HIDDeviceWatcher) {
        Log.info("HID device watcher detected new multitouch device", category: .device)
        attemptStartAfterDeviceConnection()
    }

    func hidDeviceWatcherDidDetectDeviceDisconnection(_ watcher: HIDDeviceWatcher) {
        Log.info("HID device watcher detected multitouch device removal", category: .device)
        // If we're currently monitoring, restart to update the device list.
        // If the removed device was the only one, DeviceMonitor.start() will
        // fail and we'll gracefully go back to waiting for a new device.
        if isMonitoring {
            restart()
        }
    }
}
