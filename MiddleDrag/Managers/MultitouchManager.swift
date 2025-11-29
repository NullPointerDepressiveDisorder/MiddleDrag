import Foundation
import CoreGraphics
import AppKit

/// Main manager that coordinates multitouch monitoring and gesture recognition
class MultitouchManager {
    
    // MARK: - Properties
    
    /// Shared instance
    static let shared = MultitouchManager()
    
    /// Current gesture configuration
    var configuration = GestureConfiguration()
    
    /// Whether gesture recognition is enabled
    private(set) var isEnabled = false
    
    /// Whether monitoring is active
    private(set) var isMonitoring = false
    
    /// Whether currently in a three-finger gesture (used for event suppression)
    private(set) var isInThreeFingerGesture = false
    
    // Timestamp when gesture ended (for delayed event suppression)
    private var gestureEndTime: Double = 0
    
    // Core components
    private let gestureRecognizer = GestureRecognizer()
    private let mouseGenerator = MouseEventGenerator()
    private var deviceMonitor: DeviceMonitor?
    
    // Event tap for suppressing system-generated clicks during gestures
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Processing queue
    private let gestureQueue = DispatchQueue(label: "com.middledrag.gesture", qos: .userInteractive)
    
    // MARK: - Initialization
    
    init() {
        gestureRecognizer.delegate = self
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring for gestures
    func start() {
        guard !isMonitoring else { return }
        
        applyConfiguration()
        setupEventTap()
        
        deviceMonitor = DeviceMonitor()
        deviceMonitor?.delegate = self
        deviceMonitor?.start()
        
        isMonitoring = true
        isEnabled = true
    }
    
    /// Stop monitoring
    func stop() {
        guard isMonitoring else { return }
        
        mouseGenerator.cancelDrag()
        gestureRecognizer.reset()
        
        deviceMonitor?.stop()
        deviceMonitor = nil
        
        teardownEventTap()
        
        isMonitoring = false
        isEnabled = false
    }
    
    /// Toggle enabled state
    func toggleEnabled() {
        isEnabled.toggle()
        
        if !isEnabled {
            mouseGenerator.cancelDrag()
            gestureRecognizer.reset()
        }
    }
    
    /// Update configuration
    func updateConfiguration(_ config: GestureConfiguration) {
        configuration = config
        applyConfiguration()
    }
    
    // MARK: - Event Tap
    
    private func setupEventTap() {
        // Build event mask for mouse events to intercept
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
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<MultitouchManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEventTapCallback(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            print("⚠️ Could not create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func teardownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
    }
    
    private func handleEventTapCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
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
        let isOurEvent = sourceStateID == 1  // Our private event source
        
        if isMiddleButton && isOurEvent {
            return Unmanaged.passUnretained(event)
        }
        
        // Suppress left/right events during gesture or shortly after
        let shouldSuppress = isInThreeFingerGesture || timeSinceGestureEnd < 0.15
        
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
        
        // Count valid touching fingers for event suppression state
        let touchArray = touches.bindMemory(to: MTTouch.self, capacity: Int(count))
        var validFingerCount = 0
        
        for i in 0..<Int(count) {
            let state = touchArray[i].state
            if state == 3 || state == 4 {
                validFingerCount += 1
            }
        }
        
        // Update gesture state for event tap
        let wasInGesture = isInThreeFingerGesture
        isInThreeFingerGesture = validFingerCount >= 3
        
        if wasInGesture && !isInThreeFingerGesture {
            gestureEndTime = CACurrentMediaTime()
        }
        
        gestureQueue.async { [weak self] in
            self?.gestureRecognizer.processTouches(touches, count: Int(count), timestamp: timestamp)
        }
    }
}

// MARK: - GestureRecognizerDelegate

extension MultitouchManager: GestureRecognizerDelegate {
    func gestureRecognizerDidStart(_ recognizer: GestureRecognizer, at position: MTPoint) {
        // Gesture started - ready for tap or drag
    }
    
    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer) {
        mouseGenerator.performClick()
    }
    
    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer) {
        let mouseLocation = MouseEventGenerator.currentMouseLocation
        mouseGenerator.startDrag(at: mouseLocation)
    }
    
    func gestureRecognizerDidUpdateDragging(_ recognizer: GestureRecognizer, with data: GestureData) {
        let delta = data.frameDelta(from: configuration)
        
        guard delta.x != 0 || delta.y != 0 else { return }
        
        let scaleFactor: CGFloat = 800.0 * CGFloat(configuration.sensitivity)
        let scaledDeltaX = delta.x * scaleFactor
        let scaledDeltaY = -delta.y * scaleFactor  // Invert Y for natural movement
        
        mouseGenerator.updateDrag(deltaX: scaledDeltaX, deltaY: scaledDeltaY)
    }
    
    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer) {
        mouseGenerator.endDrag()
    }
}
