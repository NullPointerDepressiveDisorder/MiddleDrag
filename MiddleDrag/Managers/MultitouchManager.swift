import AppKit
import CoreGraphics
import Foundation

/// Main manager that coordinates multitouch monitoring and gesture recognition
class MultitouchManager {

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
        self.deviceProviderFactory = deviceProviderFactory ?? { DeviceMonitor() }
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
        deviceMonitor?.delegate = self
        deviceMonitor?.start()

        // Observe sleep/wake to reinitialize device connections
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

        isMonitoring = true
        isEnabled = true
    }

    /// Stop monitoring
    func stop() {
        guard isMonitoring else { return }

        // Remove sleep/wake observers
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }

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

        // Restart
        applyConfiguration()
        let eventTapSuccess = eventTapSetupFactory()

        if !eventTapSuccess {
            Log.error("Failed to restart: could not create event tap", category: .device)
            isMonitoring = false
            isEnabled = false
            return
        }

        deviceMonitor = deviceProviderFactory()
        deviceMonitor?.delegate = self
        deviceMonitor?.start()

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

        deviceMonitor?.stop()
        deviceMonitor = nil

        teardownEventTap()

        isMonitoring = false
    }

    /// Toggle enabled state
    func toggleEnabled() {
        isEnabled.toggle()

        if !isEnabled {
            mouseGenerator.cancelDrag()
            gestureRecognizer.reset()
            currentFingerCount = 0  // Reset finger count when disabled
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

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else {
                        return Unmanaged.passUnretained(event)
                    }
                    let manager = Unmanaged<MultitouchManager>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    return manager.handleEventTapCallback(proxy: proxy, type: type, event: event)
                },
                userInfo: refcon
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
        return processEvent(event, type: type)
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
            return Unmanaged.passUnretained(event)
        }

        let sourceStateID = event.getIntegerValueField(.eventSourceStateID)
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

        // Check if we're in a 3-finger gesture using:
        // 1. Thread-safe finger count (most reliable for force clicks)
        // 2. Async-updated flag (for tap/drag state)
        // 3. Direct gesture recognizer state (fallback)
        let fingerCountSafe = currentFingerCount
        let gestureActive =
            isInThreeFingerGesture || gestureRecognizer.state != .idle || fingerCountSafe >= 3

        if isMiddleButton && isOurEvent {
            return Unmanaged.passUnretained(event)
        }

        // During 3-finger gesture: convert left clicks to middle clicks (force click support)
        if gestureActive && isLeftButton && !isOurEvent {
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
        let shouldSuppress = gestureActive || timeSinceGestureEnd < 0.15

        if shouldSuppress && !isMiddleButton {
            return nil  // Suppress the event
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Private Methods

    private func applyConfiguration() {
        gestureRecognizer.configuration = configuration
        mouseGenerator.smoothingFactor = configuration.smoothingFactor
        mouseGenerator.minimumMovementThreshold = CGFloat(configuration.minimumMovementThreshold)
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
            self?.gestureRecognizer.processTouches(
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
            }
            return
        }

        // Check window size filter before performing tap
        // Note: WindowHelper uses AppKit APIs (NSEvent.mouseLocation, NSScreen.main)
        // which must be called from the main thread
        let shouldPerformTap: Bool
        if configuration.minimumWindowSizeFilterEnabled {
            let checkWindowSize = {
                WindowHelper.windowAtCursorMeetsMinimumSize(
                    minWidth: self.configuration.minimumWindowWidth,
                    minHeight: self.configuration.minimumWindowHeight
                )
            }
            // Avoid deadlock: call directly if already on main thread, otherwise sync
            if Thread.isMainThread {
                shouldPerformTap = checkWindowSize()
            } else {
                shouldPerformTap = DispatchQueue.main.sync { checkWindowSize() }
            }
        } else {
            shouldPerformTap = true
        }

        // Always reset state regardless of whether tap is performed
        DispatchQueue.main.async { [weak self] in
            self?.isInThreeFingerGesture = false
            self?.gestureEndTime = CACurrentMediaTime()
        }

        // Only perform the click if window meets size requirements
        if shouldPerformTap {
            mouseGenerator.performClick()
        }
    }

    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer) {
        guard configuration.middleDragEnabled else { return }

        // Check window size filter before starting drag
        // Note: WindowHelper uses AppKit APIs (NSEvent.mouseLocation, NSScreen.main)
        // which must be called from the main thread
        if configuration.minimumWindowSizeFilterEnabled {
            let checkWindowSize = {
                WindowHelper.windowAtCursorMeetsMinimumSize(
                    minWidth: self.configuration.minimumWindowWidth,
                    minHeight: self.configuration.minimumWindowHeight
                )
            }
            // Avoid deadlock: call directly if already on main thread, otherwise sync
            let meetsMinimumSize: Bool
            if Thread.isMainThread {
                meetsMinimumSize = checkWindowSize()
            } else {
                meetsMinimumSize = DispatchQueue.main.sync { checkWindowSize() }
            }
            if !meetsMinimumSize {
                // Window too small - skip drag
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

        let scaleFactor: CGFloat = 1600.0 * CGFloat(configuration.sensitivity)
        let scaledDeltaX = delta.x * scaleFactor
        let scaledDeltaY = -delta.y * scaleFactor  // Invert Y for natural movement

        mouseGenerator.updateDrag(deltaX: scaledDeltaX, deltaY: scaledDeltaY)
    }

    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer) {
        DispatchQueue.main.async { [weak self] in
            self?.isActivelyDragging = false
            self?.isInThreeFingerGesture = false
            self?.gestureEndTime = CACurrentMediaTime()
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
        }
    }

    func gestureRecognizerDidCancelDragging(_ recognizer: GestureRecognizer) {
        // Cancel drag immediately - user added 4th finger for Mission Control
        DispatchQueue.main.async { [weak self] in
            self?.isActivelyDragging = false
            self?.isInThreeFingerGesture = false
            self?.gestureEndTime = CACurrentMediaTime()
        }
        mouseGenerator.cancelDrag()
    }
}
