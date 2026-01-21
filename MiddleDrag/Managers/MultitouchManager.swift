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
    /// Value determined empirically: 100ms is sufficient to avoid CFRelease(NULL) crashes
    /// caused by the framework accessing deallocated resources.
    static let restartCleanupDelay: TimeInterval = 0.1

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

    // Work item for debouncing restarts
    private var restartWorkItem: DispatchWorkItem?

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
    nonisolated(unsafe) static let shared = MultitouchManager()

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
    func start() {
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
            return
        }

        addSleepWakeObservers()

        isMonitoring = true
        isEnabled = true
    }

    /// Stop monitoring
    func stop() {
        // Cancel any pending restart
        restartWorkItem?.cancel()
        restartWorkItem = nil

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
        Log.info("Restarting multitouch monitoring", category: .device)

        // Store current state
        let wasEnabled = isEnabled

        // Stop without removing sleep/wake observers
        internalStop()

        // IMPORTANT: Delay before restarting to allow the MultitouchSupport
        // framework's internal thread (mt_ThreadedMTEntry) to fully complete cleanup.
        // Without this delay, there's a race condition where the framework thread
        // may still be releasing resources when we try to start new devices,
        // causing CFRelease(NULL) crashes.

        // Cancel any pending restart to prevent race conditions with multiple rapid restarts
        restartWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performRestart(wasEnabled: wasEnabled)
        }

        restartWorkItem = workItem

        // Use async dispatch to avoid blocking the main thread during wake.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.restartCleanupDelay, execute: workItem)
    }

    /// Performs the actual restart after the cleanup delay
    private func performRestart(wasEnabled: Bool) {
        // Verify we should still restart (manager may have been stopped during delay)
        guard wakeObserver != nil else { return }

        applyConfiguration()
        let eventTapSuccess = eventTapSetupFactory()

        if !eventTapSuccess {
            Log.error("Failed to restart: could not create event tap", category: .device)
            isMonitoring = false
            isEnabled = false
            removeSleepWakeObservers()
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
            return
        }

        isMonitoring = true
        isEnabled = wasEnabled
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

    /// Toggle enabled state
    func toggleEnabled() {
        isEnabled.toggle()

        if !isEnabled {
            mouseGenerator.cancelDrag()
            gestureRecognizer.reset()
            currentFingerCount = 0  // Reset finger count when disabled
            lastGestureWasActive = false
            gestureEndTime = 0
        }
    }

    /// Update configuration
    func updateConfiguration(_ config: GestureConfiguration) {
        configuration = config
        applyConfiguration()
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
        let hasThreeOrMoreFingers = currentFingerCount >= 3
        if hasThreeOrMoreFingers && isLeftButton && !isOurEvent && !isActivelyDragging {
            // Check event type - we want to handle both down and up
            if type == .leftMouseDown || type == .leftMouseUp {
                // Perform middle click instead
                if type == .leftMouseDown {
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

        // Gesture recognition and finger counting is done inside processTouches
        // State updates happen in delegate callbacks dispatched to main thread
        gestureQueue.async { [weak self] in
            unsafe self?.gestureRecognizer.processTouches(
                touches, count: Int(count), timestamp: timestamp, modifierFlags: modifierFlags)
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
        DispatchQueue.main.async { [weak self] in
            self?.isInThreeFingerGesture = true
        }
    }

    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer) {
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
        DispatchQueue.main.async { [weak self] in
            self?.isInThreeFingerGesture = false
            self?.gestureEndTime = CACurrentMediaTime()
            self?.lastGestureWasActive = false  // Gesture was cancelled, not active
        }
    }

    func gestureRecognizerDidCancelDragging(_ recognizer: GestureRecognizer) {
        // Cancel drag immediately - user added 4th finger for Mission Control
        DispatchQueue.main.async { [weak self] in
            self?.isActivelyDragging = false
            self?.isInThreeFingerGesture = false
            self?.gestureEndTime = CACurrentMediaTime()
            self?.lastGestureWasActive = false  // Drag was cancelled, not active
        }
        mouseGenerator.cancelDrag()
    }
}
