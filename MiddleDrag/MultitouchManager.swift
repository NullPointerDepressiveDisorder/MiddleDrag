import Foundation
import CoreGraphics
import CoreFoundation

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
    var state: UInt32
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

// MARK: - Private API Bindings

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallbackFunction = @convention(c) (
    MTDeviceRef, UnsafeMutablePointer<MTTouch>, Int32, Double, Int32
) -> Int32

@_silgen_name("MTDeviceCreateList")
func MTDeviceCreateList() -> CFArray

@_silgen_name("MTRegisterContactFrameCallback")
func MTRegisterContactFrameCallback(_ device: MTDeviceRef, 
                                   _ callback: @escaping MTContactCallbackFunction)

@_silgen_name("MTDeviceStart")
func MTDeviceStart(_ device: MTDeviceRef, _ mode: Int32)

@_silgen_name("MTDeviceStop")
func MTDeviceStop(_ device: MTDeviceRef)

@_silgen_name("MTDeviceIsBuiltIn")
func MTDeviceIsBuiltIn(_ device: MTDeviceRef) -> Bool

// MARK: - Multitouch Manager

class MultitouchManager {
    private var devices: [MTDeviceRef] = []
    var isEnabled = true
    var sensitivity: Float = 1.0
    
    // Middle mouse button state
    private var isMiddleMouseDown = false
    private var threeFingerActive = false
    private var lastMouseLocation: CGPoint = .zero
    private var dragStartLocation: CGPoint = .zero
    
    // Timing for tap detection
    private var touchStartTime: Double = 0
    private var touchStartLocation: MTPoint?
    
    // Callback for multitouch events
    private lazy var callback: MTContactCallbackFunction = { [weak self] device, touches, numTouches, timestamp, frame in
        guard let self = self, self.isEnabled else { return 0 }
        
        let count = Int(numTouches)
        
        if count == 3 {
            self.handleThreeFingerTouch(touches: touches, count: count, timestamp: timestamp)
        } else if self.threeFingerActive {
            // Fingers lifted
            self.handleFingerLift(timestamp: timestamp)
        }
        
        return 0
    }
    
    // MARK: - Lifecycle
    
    func start() {
        guard AXIsProcessTrusted() else {
            print("⚠️ Accessibility permissions not granted")
            return
        }
        
        let deviceList = MTDeviceCreateList() as [AnyObject]
        print("Found \(deviceList.count) multitouch device(s)")
        
        for (index, deviceObj) in deviceList.enumerated() {
            let device = unsafeBitCast(deviceObj, to: MTDeviceRef.self)
            devices.append(device)
            
            let isBuiltIn = MTDeviceIsBuiltIn(device)
            print("Device \(index): \(isBuiltIn ? "Built-in Trackpad" : "External Magic Trackpad")")
            
            MTRegisterContactFrameCallback(device, callback)
            MTDeviceStart(device, 0)
        }
        
        print("✅ MiddleDrag monitoring started")
    }
    
    func stop() {
        // Release any held mouse button
        if isMiddleMouseDown {
            simulateMiddleMouseUp(at: NSEvent.mouseLocation)
        }
        
        for device in devices {
            MTDeviceStop(device)
        }
        devices.removeAll()
        print("MiddleDrag monitoring stopped")
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
        
        // Release mouse if disabling while dragging
        if !isEnabled && isMiddleMouseDown {
            simulateMiddleMouseUp(at: NSEvent.mouseLocation)
            isMiddleMouseDown = false
            threeFingerActive = false
        }
    }
    
    // MARK: - Touch Handling
    
    private func handleThreeFingerTouch(touches: UnsafeMutablePointer<MTTouch>, count: Int, timestamp: Double) {
        // Calculate average position of three fingers
        var avgX: Float = 0
        var avgY: Float = 0
        var totalPressure: Float = 0
        
        for i in 0..<count {
            let touch = touches[i]
            avgX += touch.normalizedVector.position.x
            avgY += touch.normalizedVector.position.y
            totalPressure += touch.zTotal
        }
        
        avgX /= Float(count)
        avgY /= Float(count)
        
        let currentLocation = CGPoint(x: CGFloat(avgX), y: CGFloat(avgY))
        
        if !threeFingerActive {
            // Just touched with three fingers
            threeFingerActive = true
            touchStartTime = timestamp
            touchStartLocation = MTPoint(x: avgX, y: avgY)
            dragStartLocation = NSEvent.mouseLocation
            
            // Start middle mouse drag
            simulateMiddleMouseDown(at: dragStartLocation)
            isMiddleMouseDown = true
            lastMouseLocation = dragStartLocation
            
        } else if isMiddleMouseDown {
            // Continue dragging - calculate delta movement
            if let startLoc = touchStartLocation {
                let deltaX = CGFloat(avgX - startLoc.x) * 1000 * CGFloat(sensitivity)
                let deltaY = CGFloat(avgY - startLoc.y) * 1000 * CGFloat(sensitivity)
                
                // Apply movement to mouse position
                let newLocation = CGPoint(
                    x: dragStartLocation.x + deltaX,
                    y: dragStartLocation.y - deltaY  // Invert Y for natural scrolling
                )
                
                // Only send drag event if position changed significantly
                let moveThreshold: CGFloat = 0.5
                if abs(newLocation.x - lastMouseLocation.x) > moveThreshold ||
                   abs(newLocation.y - lastMouseLocation.y) > moveThreshold {
                    simulateMiddleMouseDrag(at: newLocation)
                    lastMouseLocation = newLocation
                }
            }
        }
    }
    
    private func handleFingerLift(timestamp: Double) {
        guard threeFingerActive else { return }
        
        // Check if it was a tap (short duration and minimal movement)
        let tapDuration = timestamp - touchStartTime
        let wasTap = tapDuration < 0.2  // 200ms threshold for tap
        
        if isMiddleMouseDown {
            simulateMiddleMouseUp(at: lastMouseLocation)
            isMiddleMouseDown = false
            
            // If it was a quick tap, also send a click
            if wasTap, let startLoc = touchStartLocation {
                // Check movement distance
                let moveThreshold: Float = 0.02
                let currentLoc = MTPoint(x: startLoc.x, y: startLoc.y)
                let distance = sqrt(pow(currentLoc.x - startLoc.x, 2) + pow(currentLoc.y - startLoc.y, 2))
                
                if distance < moveThreshold {
                    // It's a tap, not a drag
                    performMiddleClick(at: NSEvent.mouseLocation)
                }
            }
        }
        
        threeFingerActive = false
        touchStartLocation = nil
    }
    
    // MARK: - Mouse Event Simulation
    
    private func simulateMiddleMouseDown(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.post(tap: .cghidEventTap)
    }
    
    private func simulateMiddleMouseDrag(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.post(tap: .cghidEventTap)
    }
    
    private func simulateMiddleMouseUp(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.post(tap: .cghidEventTap)
    }
    
    private func performMiddleClick(at location: CGPoint) {
        // Send a clean click (down + up)
        simulateMiddleMouseDown(at: location)
        
        // Small delay between press and release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.simulateMiddleMouseUp(at: location)
        }
    }
}
