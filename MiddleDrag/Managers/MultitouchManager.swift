import Foundation
import CoreGraphics
import AppKit

/// Main manager that coordinates multitouch monitoring and gesture recognition
class MultitouchManager {
    
    // MARK: - Properties
    
    /// Shared instance for convenience
    static let shared = MultitouchManager()
    
    /// Current configuration
    var configuration = GestureConfiguration()
    
    /// Whether monitoring is enabled
    private(set) var isEnabled = false
    
    /// Whether monitoring is active
    private(set) var isMonitoring = false
    
    // Core components
    private let gestureRecognizer = GestureRecognizer()
    private let mouseGenerator = MouseEventGenerator()
    private var deviceMonitor: DeviceMonitor?
    
    // Processing queue
    private let gestureQueue = DispatchQueue(label: "com.middledrag.gesture", qos: .userInteractive)
    
    // Optional system gesture blocking
    private var eventTap: CFMachPort?
    
    // MARK: - Initialization
    
    init() {
        setupGestureRecognizer()
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring for gestures
    func start() {
        guard !isMonitoring else { return }
        guard AXIsProcessTrusted() else {
            print("⚠️ Accessibility permissions not granted")
            return
        }
        
        // Apply configuration
        applyConfiguration()
        
        // Start device monitoring
        deviceMonitor = DeviceMonitor()
        deviceMonitor?.delegate = self
        deviceMonitor?.start()
        
        // Optionally set up event tap
        if configuration.blockSystemGestures {
            setupEventTap()
        }
        
        isMonitoring = true
        isEnabled = true
        
        print("✅ MiddleDrag monitoring started")
    }
    
    /// Stop monitoring
    func stop() {
        guard isMonitoring else { return }
        
        // Clean up any active gestures
        mouseGenerator.cancelDrag()
        gestureRecognizer.reset()
        
        // Stop device monitoring
        deviceMonitor?.stop()
        deviceMonitor = nil
        
        // Clean up event tap
        teardownEventTap()
        
        isMonitoring = false
        isEnabled = false
        
        print("MiddleDrag monitoring stopped")
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
        
        // Restart if needed for system gesture blocking
        if isMonitoring && config.blockSystemGestures != (eventTap != nil) {
            stop()
            start()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupGestureRecognizer() {
        gestureRecognizer.delegate = self
    }
    
    private func applyConfiguration() {
        gestureRecognizer.configuration = configuration
        mouseGenerator.smoothingFactor = configuration.smoothingFactor
        mouseGenerator.minimumMovementThreshold = CGFloat(configuration.minimumMovementThreshold)
    }
    
    private func setupEventTap() {
        // Optional: Event tap for blocking system gestures
        // Since MultitouchSupport receives data before system processing,
        // this is typically not needed. Keeping as placeholder for future use.
        
        /* Commented out - not essential for operation
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                       (1 << CGEventType.leftMouseUp.rawValue) |
                       (1 << CGEventType.leftMouseDragged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Only block if actively dragging
                guard let manager = Unmanaged<MultitouchManager>.fromOpaque(refcon!).takeUnretainedValue() as MultitouchManager? else {
                    return Unmanaged.passRetained(event)
                }
                
                if manager.isEnabled && manager.gestureRecognizer.state == .dragging {
                    return nil  // Consume the event
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Warning: Could not create event tap")
            return
        }
        
        eventTap = tap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        */
    }
    
    private func teardownEventTap() {
        // Clean up event tap if it exists
        /* Commented out - matches setupEventTap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        */
    }
}

// MARK: - DeviceMonitorDelegate

extension MultitouchManager: DeviceMonitorDelegate {
    func deviceMonitor(_ monitor: DeviceMonitor, didReceiveTouches touches: UnsafeMutableRawPointer, count: Int32, timestamp: Double) {
        guard isEnabled else { return }
        
        gestureQueue.async { [weak self] in
            self?.gestureRecognizer.processTouches(touches, count: Int(count), timestamp: timestamp)
        }
    }
}

// MARK: - GestureRecognizerDelegate

extension MultitouchManager: GestureRecognizerDelegate {
    func gestureRecognizerDidStart(_ recognizer: GestureRecognizer, at position: MTPoint) {
        // Gesture started - prepare for possible tap or drag
        print("Gesture started at normalized position: (\(position.x), \(position.y))")
    }
    
    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer) {
        mouseGenerator.performClick()
    }
    
    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer) {
        // Use the CURRENT mouse location as the reference point, not the touch position
        let mouseLocation = MouseEventGenerator.currentMouseLocation
        print("Begin dragging - Mouse at: (\(mouseLocation.x), \(mouseLocation.y))")
        mouseGenerator.startDrag(at: mouseLocation)
    }
    
    func gestureRecognizerDidUpdateDragging(_ recognizer: GestureRecognizer, with data: GestureData) {
        // Use frame-to-frame delta for smooth movement
        let delta = data.frameDelta(from: configuration)
        
        // Debug: Check if we're getting reasonable deltas
        if abs(delta.x) > 0.1 || abs(delta.y) > 0.1 {
            print("Warning: Large delta detected - x: \(delta.x), y: \(delta.y)")
        }
        
        // Scale to screen coordinates (delta is in normalized 0-1 space)
        // Normalized trackpad coordinates are typically much smaller movements
        let screenBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        
        // Scale factor: typical trackpad is ~130mm wide, movements are small fractions
        // Don't multiply by full screen width, use a reasonable scaling factor
        let scaleFactor: CGFloat = 1000.0  // Adjust this based on feel
        
        let scaledDeltaX = delta.x * scaleFactor
        let scaledDeltaY = -delta.y * scaleFactor  // Invert Y for natural scrolling
        
        mouseGenerator.updateDrag(deltaX: scaledDeltaX, deltaY: scaledDeltaY)
    }
    
    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer) {
        mouseGenerator.endDrag()
    }
}
