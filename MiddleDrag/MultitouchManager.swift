import Foundation
import CoreGraphics
import CoreFoundation
import AppKit

// MARK: - MultitouchSupport Framework Structures

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: UInt32  // 3 = touching down, 4 = active, 5 = lifting
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var zTotal: Float  // Pressure/size
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector  // Absolute screen coordinates
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

// MARK: - Touch State Management

private struct TrackedFinger {
    let id: Int32
    var position: MTPoint
    var velocity: MTPoint
    var pressure: Float
    var timestamp: Double
    var state: UInt32
}

private enum GestureState {
    case idle
    case possibleTap
    case dragging
    case waitingForRelease
}

// MARK: - Private API Bindings

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallbackFunction = @convention(c) (MTDeviceRef?, UnsafeMutablePointer<MTTouch>?, Int32, Double, Int32) -> Int32

@_silgen_name("MTDeviceCreateList")
func MTDeviceCreateList() -> CFArray

@_silgen_name("MTRegisterContactFrameCallback")
func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: @escaping MTContactCallbackFunction)

@_silgen_name("MTDeviceStart")
func MTDeviceStart(_ device: MTDeviceRef, _ mode: Int32)

@_silgen_name("MTDeviceStop")
func MTDeviceStop(_ device: MTDeviceRef)

@_silgen_name("MTDeviceIsBuiltIn")
func MTDeviceIsBuiltIn(_ device: MTDeviceRef) -> Bool

@_silgen_name("MTDeviceGetSensorSurfaceDimensions")
func MTDeviceGetSensorSurfaceDimensions(_ device: MTDeviceRef) -> CGSize

@_silgen_name("MTDeviceIsRunning")
func MTDeviceIsRunning(_ device: MTDeviceRef) -> Bool

// MARK: - Multitouch Manager

class MultitouchManager {
    // Configuration
    var isEnabled = true
    var sensitivity: Float = 1.0
    var tapThreshold: Double = 0.15  // 150ms for tap detection
    var moveThreshold: Float = 0.015  // Movement threshold for tap vs drag
    var smoothingFactor: Float = 0.3  // For smooth cursor movement
    var requiresThreeFingerDrag = true  // Option to require exactly 3 fingers
    var blockSystemGestures = false  // Optional: block system gestures while dragging
    
    // Device management
    private var devices: [MTDeviceRef] = []
    private var deviceDimensions: [MTDeviceRef: CGSize] = [:]
    private var eventTap: CFMachPort?
    
    // Gesture state
    private var gestureState: GestureState = .idle
    private var trackedFingers: [Int32: TrackedFinger] = [:]
    private var isMiddleMouseDown = false
    
    // Timing and position tracking
    private var gestureStartTime: Double = 0
    private var gestureStartPosition: MTPoint?
    private var lastCursorPosition: CGPoint = .zero
    private var smoothedCursorPosition: CGPoint = .zero
    private var initialMousePosition: CGPoint = .zero
    
    // Performance optimization
    private let gestureQueue = DispatchQueue(label: "com.middledrag.gesture", qos: .userInteractive)
    private let mouseEventQueue = DispatchQueue(label: "com.middledrag.mouse", qos: .userInitiated)
    
    // Callback storage (avoids retain cycles)
    private var contactCallback: MTContactCallbackFunction?
    
    // MARK: - Lifecycle
    
    init() {
        setupContactCallback()
    }
    
    deinit {
        stop()
    }
    
    private func setupContactCallback() {
        // Create callback that captures self weakly
        contactCallback = { [weak self] (device, touches, numTouches, timestamp, frame) in
            guard let self = self else { return 0 }
            return self.handleContactFrame(device: device, touches: touches, numTouches: numTouches, timestamp: timestamp, frame: frame)
        }
    }
    
    func start() {
        guard AXIsProcessTrusted() else {
            print("⚠️ Accessibility permissions not granted")
            return
        }
        
        // Initialize devices
        initializeDevices()
        
        // Optionally set up event tap for consuming system gestures
        if blockSystemGestures {
            setupEventTap()
        }
        
        print("✅ MiddleDrag monitoring started with \(devices.count) device(s)")
    }
    
    func stop() {
        // Clean up any active gesture
        if isMiddleMouseDown {
            mouseEventQueue.async { [weak self] in
                self?.simulateMiddleMouseUp(at: self?.lastCursorPosition ?? .zero)
            }
        }
        
        // Stop all devices
        for device in devices {
            if MTDeviceIsRunning(device) {
                MTDeviceStop(device)
            }
        }
        
        // Clean up event tap
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        // Clear state
        devices.removeAll()
        deviceDimensions.removeAll()
        trackedFingers.removeAll()
        gestureState = .idle
        isMiddleMouseDown = false
        
        print("MiddleDrag monitoring stopped")
    }
    
    private func initializeDevices() {
        let deviceList = MTDeviceCreateList() as [AnyObject]
        
        for (index, deviceObj) in deviceList.enumerated() {
            let device = unsafeBitCast(deviceObj, to: MTDeviceRef.self)
            devices.append(device)
            
            // Get device info
            let isBuiltIn = MTDeviceIsBuiltIn(device)
            let dimensions = MTDeviceGetSensorSurfaceDimensions(device)
            deviceDimensions[device] = dimensions
            
            print("Device \(index): \(isBuiltIn ? "Built-in Trackpad" : "External Magic Trackpad")")
            print("  Dimensions: \(dimensions.width) x \(dimensions.height)")
            
            // Register callback
            if let callback = contactCallback {
                MTRegisterContactFrameCallback(device, callback)
            }
            
            // Start device
            MTDeviceStart(device, 0)
        }
    }
    
    private func setupEventTap() {
        // Optional: Create event tap to consume three-finger system gestures
        // This is ONLY needed if the user wants to block system gestures
        // MiddleDrag works fine WITHOUT this since MultitouchSupport gets data first
        let eventMask = (1 << CGEventType.gesture.rawValue) |
                       (1 << CGEventType.magnify.rawValue) |
                       (1 << CGEventType.swipe.rawValue) |
                       (1 << CGEventType.rotate.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { [weak self] (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let self = self,
                      self.isEnabled,
                      self.gestureState == .dragging else {
                    return Unmanaged.passRetained(event)
                }
                
                // Consume three-finger gestures while we're dragging
                if type == .gesture || type == .swipe {
                    return nil  // Consume the event
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            print("Warning: Could not create event tap for gesture blocking")
            return
        }
        
        self.eventTap = eventTap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    // MARK: - Touch Handling
    
    private func handleContactFrame(device: MTDeviceRef?, touches: UnsafeMutablePointer<MTTouch>?, numTouches: Int32, timestamp: Double, frame: Int32) -> Int32 {
        guard isEnabled, let touches = touches else { return 0 }
        
        gestureQueue.async { [weak self] in
            self?.processTouches(touches: touches, count: Int(numTouches), timestamp: timestamp)
        }
        
        return 0
    }
    
    private func processTouches(touches: UnsafeMutablePointer<MTTouch>, count: Int, timestamp: Double) {
        // Update tracked fingers
        updateTrackedFingers(touches: touches, count: count, timestamp: timestamp)
        
        // Analyze gesture based on finger count
        let activeFingers = trackedFingers.values.filter { $0.state == 4 }
        let fingerCount = activeFingers.count
        
        if requiresThreeFingerDrag {
            if fingerCount == 3 {
                handleThreeFingerGesture(fingers: Array(activeFingers), timestamp: timestamp)
            } else if fingerCount < 3 && gestureState != .idle {
                handleGestureEnd(timestamp: timestamp)
            }
        } else {
            // Allow 3+ fingers for compatibility with some CAD software
            if fingerCount >= 3 {
                handleThreeFingerGesture(fingers: Array(activeFingers), timestamp: timestamp)
            } else if fingerCount < 3 && gestureState != .idle {
                handleGestureEnd(timestamp: timestamp)
            }
        }
    }
    
    private func updateTrackedFingers(touches: UnsafeMutablePointer<MTTouch>, count: Int, timestamp: Double) {
        var currentFingerIDs = Set<Int32>()
        
        for i in 0..<count {
            let touch = touches[i]
            currentFingerIDs.insert(touch.fingerID)
            
            // Update or add tracked finger
            trackedFingers[touch.fingerID] = TrackedFinger(
                id: touch.fingerID,
                position: touch.normalizedVector.position,
                velocity: touch.normalizedVector.velocity,
                pressure: touch.zTotal,
                timestamp: timestamp,
                state: touch.state
            )
        }
        
        // Remove fingers that are no longer present
        trackedFingers = trackedFingers.filter { currentFingerIDs.contains($0.key) }
    }
    
    private func handleThreeFingerGesture(fingers: [TrackedFinger], timestamp: Double) {
        // Calculate centroid and average metrics
        let centroid = calculateCentroid(fingers: fingers)
        let averagePressure = fingers.reduce(0) { $0 + $1.pressure } / Float(fingers.count)
        let averageVelocity = calculateAverageVelocity(fingers: fingers)
        
        switch gestureState {
        case .idle:
            // Start new gesture
            gestureState = .possibleTap
            gestureStartTime = timestamp
            gestureStartPosition = centroid
            initialMousePosition = NSEvent.mouseLocation
            smoothedCursorPosition = initialMousePosition
            
        case .possibleTap:
            // Check if we should transition to drag
            let timeSinceStart = timestamp - gestureStartTime
            let movement = calculateMovement(from: gestureStartPosition!, to: centroid)
            
            if movement > moveThreshold || timeSinceStart > tapThreshold {
                // Transition to drag
                gestureState = .dragging
                startMiddleDrag(at: initialMousePosition)
            }
            
        case .dragging:
            // Continue drag with smooth movement
            if let startPos = gestureStartPosition {
                updateMiddleDrag(
                    from: startPos,
                    to: centroid,
                    velocity: averageVelocity,
                    pressure: averagePressure
                )
            }
            
        case .waitingForRelease:
            // Wait for all fingers to lift
            break
        }
    }
    
    private func handleGestureEnd(timestamp: Double) {
        let timeSinceStart = timestamp - gestureStartTime
        
        switch gestureState {
        case .possibleTap:
            // It was a tap!
            if timeSinceStart < tapThreshold {
                performMiddleClick()
            }
            
        case .dragging:
            // End the drag
            endMiddleDrag()
            
        default:
            break
        }
        
        // Reset state
        gestureState = .idle
        gestureStartPosition = nil
        trackedFingers.removeAll()
    }
    
    // MARK: - Gesture Calculations
    
    private func calculateCentroid(fingers: [TrackedFinger]) -> MTPoint {
        let sumX = fingers.reduce(0) { $0 + $1.position.x }
        let sumY = fingers.reduce(0) { $0 + $1.position.y }
        return MTPoint(x: sumX / Float(fingers.count), y: sumY / Float(fingers.count))
    }
    
    private func calculateAverageVelocity(fingers: [TrackedFinger]) -> MTPoint {
        let sumVX = fingers.reduce(0) { $0 + $1.velocity.x }
        let sumVY = fingers.reduce(0) { $0 + $1.velocity.y }
        return MTPoint(x: sumVX / Float(fingers.count), y: sumVY / Float(fingers.count))
    }
    
    private func calculateMovement(from: MTPoint, to: MTPoint) -> Float {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Mouse Event Generation
    
    private func startMiddleDrag(at location: CGPoint) {
        mouseEventQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isMiddleMouseDown = true
            self.lastCursorPosition = location
            self.simulateMiddleMouseDown(at: location)
        }
    }
    
    private func updateMiddleDrag(from startPos: MTPoint, to currentPos: MTPoint, velocity: MTPoint, pressure: Float) {
        mouseEventQueue.async { [weak self] in
            guard let self = self, self.isMiddleMouseDown else { return }
            
            // Calculate delta with enhanced sensitivity calculation
            let deltaX = CGFloat(currentPos.x - startPos.x)
            let deltaY = CGFloat(currentPos.y - startPos.y)
            
            // Apply sensitivity with velocity boost for faster movements
            let velocityBoost = 1.0 + min(abs(velocity.x) + abs(velocity.y), 2.0) * 0.5
            let effectiveSensitivity = CGFloat(self.sensitivity) * velocityBoost
            
            // Scale to screen coordinates
            let screenBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let scaledDeltaX = deltaX * screenBounds.width * effectiveSensitivity
            let scaledDeltaY = -deltaY * screenBounds.height * effectiveSensitivity  // Invert Y
            
            // Calculate new position with smoothing
            let targetX = self.initialMousePosition.x + scaledDeltaX
            let targetY = self.initialMousePosition.y + scaledDeltaY
            
            // Apply exponential smoothing for fluid movement
            let smoothing = CGFloat(self.smoothingFactor)
            self.smoothedCursorPosition.x += (targetX - self.smoothedCursorPosition.x) * smoothing
            self.smoothedCursorPosition.y += (targetY - self.smoothedCursorPosition.y) * smoothing
            
            // Only update if movement is significant (reduces jitter)
            let minMovement: CGFloat = 0.5
            let distance = hypot(
                self.smoothedCursorPosition.x - self.lastCursorPosition.x,
                self.smoothedCursorPosition.y - self.lastCursorPosition.y
            )
            
            if distance > minMovement {
                self.simulateMiddleMouseDrag(at: self.smoothedCursorPosition)
                self.lastCursorPosition = self.smoothedCursorPosition
            }
        }
    }
    
    private func endMiddleDrag() {
        mouseEventQueue.async { [weak self] in
            guard let self = self, self.isMiddleMouseDown else { return }
            
            self.isMiddleMouseDown = false
            self.simulateMiddleMouseUp(at: self.lastCursorPosition)
        }
    }
    
    private func performMiddleClick() {
        mouseEventQueue.async { [weak self] in
            guard let self = self else { return }
            
            let clickLocation = NSEvent.mouseLocation
            self.simulateMiddleMouseDown(at: clickLocation)
            
            // Shorter delay for snappier clicks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
                self.simulateMiddleMouseUp(at: clickLocation)
            }
        }
    }
    
    // MARK: - CGEvent Generation
    
    private func simulateMiddleMouseDown(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.flags = []  // Clear any modifier flags
        event.post(tap: .cghidEventTap)
    }
    
    private func simulateMiddleMouseDrag(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
    
    private func simulateMiddleMouseUp(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
    
    // MARK: - Public Controls
    
    func toggleEnabled() {
        isEnabled.toggle()
        
        if !isEnabled && isMiddleMouseDown {
            endMiddleDrag()
        }
    }
    
    func setSensitivity(_ value: Float) {
        sensitivity = max(0.1, min(3.0, value))
    }
    
    func setTapThreshold(_ seconds: Double) {
        tapThreshold = max(0.05, min(0.5, seconds))
    }
    
    func setSmoothingFactor(_ value: Float) {
        smoothingFactor = max(0.1, min(1.0, value))
    }
}