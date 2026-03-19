//
//  GlobalHotKeyManager.swift
//  MiddleDrag
//

import Cocoa
import Carbon.HIToolbox

/// Manages system-wide hotkeys using Carbon's RegisterEventHotKey
/// Threading: Delivers handlers on the main thread
@safe @MainActor
public final class GlobalHotKeyManager {
    public static let shared = GlobalHotKeyManager()

    // Map hotkey IDs to handlers
    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef?] = unsafe [:]
    private var nextID: UInt32 = 1

    // Keep a reference to the installed event handler
    private var eventHandler: EventHandlerRef?

    // Unique signature to identify our hotkeys (any 4-byte code)
    private let signature: OSType = 0x4D44484B // 'MDHK'

    private init() {
        // Install a single event handler for all hotkeys we register
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { (_, eventRef, userData) in
            // Extract the EventHotKeyID for the pressed hotkey
            var hotKeyID = EventHotKeyID()
            let status = unsafe GetEventParameter(eventRef,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout.size(ofValue: hotKeyID),
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return noErr }

            // Bridge back to Swift instance
            if let userData = unsafe userData {
                let manager = unsafe Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                let id = hotKeyID.id
                if let handler = manager.handlers[id] {
                    // Deliver on main thread to safely call AppKit/UI code
                    DispatchQueue.main.async {
                        handler()
                    }
                }
            }
            return noErr
        }

        unsafe InstallEventHandler(GetEventDispatcherTarget(),
                            callback,
                            1,
                            &eventType,
                            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                            &eventHandler)
    }

    func invalidate() {
        // Unregister all hotkeys and remove the handler
        for unsafe (_, ref) in unsafe hotKeyRefs {
            if let ref = unsafe ref { unsafe UnregisterEventHotKey(ref) }
        }
        unsafe hotKeyRefs.removeAll()

        if let handler = unsafe eventHandler {
            unsafe RemoveEventHandler(handler)
            unsafe eventHandler = nil
        }
    }

    /// Register a global hotkey
    /// - Parameters:
    ///   - keyCode: A virtual key code (e.g. kVK_ANSI_E)
    ///   - modifiers: Carbon modifier mask (e.g. cmdKey | shiftKey)
    ///   - handler: Closure invoked when the hotkey is pressed
    /// - Returns: An identifier to later unregister if needed
    @discardableResult
    public func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID &+= 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)

        let status = unsafe RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)

        guard status == noErr, let _ = unsafe ref else {
            // Registration can fail if another app already claimed the combo
            NSLog("GlobalHotKeyManager: Failed to register hotkey (code \(keyCode), mods \(modifiers))")
            return 0
        }

        unsafe hotKeyRefs[id] = unsafe ref
        handlers[id] = handler
        return id
    }

    /// Unregister a previously registered hotkey by ID
    func unregister(id: UInt32) {
        if let ref = unsafe hotKeyRefs[id] {
            if let ref = unsafe ref { unsafe UnregisterEventHotKey(ref) }
            unsafe hotKeyRefs[id] = nil
        }
        handlers[id] = nil
    }

    /// Utility: Convert NSEvent.ModifierFlags to Carbon modifiers
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
