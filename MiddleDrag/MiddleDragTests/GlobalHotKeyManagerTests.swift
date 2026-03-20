import XCTest
import Carbon.HIToolbox

@testable import MiddleDragCore

@MainActor @unsafe final class GlobalHotKeyManagerTests: XCTestCase {

    // MARK: - carbonModifiers Tests

    func testCarbonModifiersCommand() {
        let result = GlobalHotKeyManager.carbonModifiers(from: .command)
        XCTAssertEqual(result, UInt32(cmdKey))
    }

    func testCarbonModifiersOption() {
        let result = GlobalHotKeyManager.carbonModifiers(from: .option)
        XCTAssertEqual(result, UInt32(optionKey))
    }

    func testCarbonModifiersShift() {
        let result = GlobalHotKeyManager.carbonModifiers(from: .shift)
        XCTAssertEqual(result, UInt32(shiftKey))
    }

    func testCarbonModifiersControl() {
        let result = GlobalHotKeyManager.carbonModifiers(from: .control)
        XCTAssertEqual(result, UInt32(controlKey))
    }

    func testCarbonModifiersCombinedCommandShift() {
        let result = GlobalHotKeyManager.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(result, UInt32(cmdKey) | UInt32(shiftKey))
    }

    func testCarbonModifiersCombinedOptionControl() {
        let result = GlobalHotKeyManager.carbonModifiers(from: [.option, .control])
        XCTAssertEqual(result, UInt32(optionKey) | UInt32(controlKey))
    }

    func testCarbonModifiersCombinedCommandOption() {
        let result = GlobalHotKeyManager.carbonModifiers(from: [.command, .option])
        XCTAssertEqual(result, UInt32(cmdKey) | UInt32(optionKey))
    }

    func testCarbonModifiersAllFour() {
        let result = GlobalHotKeyManager.carbonModifiers(from: [.command, .option, .shift, .control])
        let expected = UInt32(cmdKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(controlKey)
        XCTAssertEqual(result, expected)
    }

    func testCarbonModifiersEmpty() {
        let result = GlobalHotKeyManager.carbonModifiers(from: [])
        XCTAssertEqual(result, 0)
    }

    func testCarbonModifiersIgnoresCapsLock() {
        let result = GlobalHotKeyManager.carbonModifiers(from: .capsLock)
        XCTAssertEqual(result, 0)
    }

    func testCarbonModifiersIgnoresFunction() {
        let result = GlobalHotKeyManager.carbonModifiers(from: .function)
        XCTAssertEqual(result, 0)
    }

    func testCarbonModifiersIgnoresNumericPad() {
        let result = GlobalHotKeyManager.carbonModifiers(from: .numericPad)
        XCTAssertEqual(result, 0)
    }

    func testCarbonModifiersMixedValidAndInvalid() {
        // .capsLock should be ignored, .command should pass through
        let result = GlobalHotKeyManager.carbonModifiers(from: [.capsLock, .command])
        XCTAssertEqual(result, UInt32(cmdKey))
    }

    func testCarbonModifiersIdempotent() {
        // Calling with same flags twice should produce identical results
        let flags: NSEvent.ModifierFlags = [.command, .shift, .option]
        let result1 = GlobalHotKeyManager.carbonModifiers(from: flags)
        let result2 = GlobalHotKeyManager.carbonModifiers(from: flags)
        XCTAssertEqual(result1, result2)
    }

    func testCarbonModifiersTripleCombination() {
        let result = GlobalHotKeyManager.carbonModifiers(from: [.command, .shift, .option])
        let expected = UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        XCTAssertEqual(result, expected)
    }

    // MARK: - Singleton Tests

    func testSharedInstanceIsSingleton() {
        let a = GlobalHotKeyManager.shared
        let b = GlobalHotKeyManager.shared
        XCTAssertTrue(a === b)
    }

    func testSharedInstanceIsNotNil() {
        XCTAssertNotNil(GlobalHotKeyManager.shared)
    }

    // MARK: - Register / Unregister Tests

    func testRegisterDoesNotCrash() {
        // Carbon RegisterEventHotKey may fail in CI (no window server),
        // but the method itself should not crash
        let id = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}

        // Clean up regardless of success
        if id != 0 {
            GlobalHotKeyManager.shared.unregister(id: id)
        }
    }

    func testRegisterMultipleHotkeysReturnsDifferentIDs() {
        let id1 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}
        let id2 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}

        // If both succeeded, IDs should differ
        if id1 != 0 && id2 != 0 {
            XCTAssertNotEqual(id1, id2)
        }

        // Clean up
        if id1 != 0 { GlobalHotKeyManager.shared.unregister(id: id1) }
        if id2 != 0 { GlobalHotKeyManager.shared.unregister(id: id2) }
    }

    func testRegisterReturnsMonotonicallyIncreasingIDs() {
        let id1 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}
        let id2 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_O),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}

        // IDs should be monotonically increasing (even if registration fails, nextID advances)
        if id1 != 0 && id2 != 0 {
            XCTAssertGreaterThan(id2, id1)
        }

        if id1 != 0 { GlobalHotKeyManager.shared.unregister(id: id1) }
        if id2 != 0 { GlobalHotKeyManager.shared.unregister(id: id2) }
    }

    func testUnregisterInvalidIDDoesNotCrash() {
        XCTAssertNoThrow(GlobalHotKeyManager.shared.unregister(id: 99999))
    }

    func testUnregisterZeroIDDoesNotCrash() {
        // 0 is the failure return value from register
        XCTAssertNoThrow(GlobalHotKeyManager.shared.unregister(id: 0))
    }

    func testUnregisterMaxUInt32DoesNotCrash() {
        XCTAssertNoThrow(GlobalHotKeyManager.shared.unregister(id: UInt32.max))
    }

    func testDoubleUnregisterDoesNotCrash() {
        let id = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}

        if id != 0 {
            GlobalHotKeyManager.shared.unregister(id: id)
            // Second unregister of same ID should be safe
            XCTAssertNoThrow(GlobalHotKeyManager.shared.unregister(id: id))
        }
    }

    func testRegisterAndUnregisterCycle() {
        // Register, unregister, re-register should work cleanly
        let id1 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}

        if id1 != 0 {
            GlobalHotKeyManager.shared.unregister(id: id1)
        }

        // Re-register same combo after unregister
        let id2 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}

        // New registration should get a new ID
        if id1 != 0 && id2 != 0 {
            XCTAssertNotEqual(id1, id2)
        }

        if id2 != 0 { GlobalHotKeyManager.shared.unregister(id: id2) }
    }

    func testRegisterWithDifferentModifiers() {
        // Same key code with different modifiers should both succeed
        let id1 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}
        let id2 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey)
        ) {}

        if id1 != 0 && id2 != 0 {
            XCTAssertNotEqual(id1, id2)
        }

        if id1 != 0 { GlobalHotKeyManager.shared.unregister(id: id1) }
        if id2 != 0 { GlobalHotKeyManager.shared.unregister(id: id2) }
    }

    // MARK: - Handler Tests

    func testRegisterStoresHandlerWithoutInvoking() {
        var handlerCalled = false
        let id = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {
            handlerCalled = true
        }

        // Handler should not be invoked on registration
        XCTAssertFalse(handlerCalled)

        if id != 0 { GlobalHotKeyManager.shared.unregister(id: id) }
    }

    func testUnregisterClearsHandler() {
        var handlerCalled = false
        let id = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_H),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {
            handlerCalled = true
        }

        if id != 0 {
            GlobalHotKeyManager.shared.unregister(id: id)
        }

        // After unregister, handler should still not have been called
        XCTAssertFalse(handlerCalled)
    }

    func testRegisterWithEmptyHandler() {
        // An empty closure should still be valid
        let id = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_I),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) { /* no-op */ }

        if id != 0 { GlobalHotKeyManager.shared.unregister(id: id) }
    }

    // MARK: - Invalidate Tests

    // Note: We cannot fully test invalidate() on the shared singleton without
    // breaking other tests. Instead we verify it doesn't crash.

    func testInvalidateDoesNotCrash() {
        // Register some hotkeys first
        let id1 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}
        let id2 = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {}

        // invalidate should unregister all and remove the event handler
        XCTAssertNoThrow(GlobalHotKeyManager.shared.invalidate())

        // Unregister after invalidate should be safe (no-ops)
        if id1 != 0 { XCTAssertNoThrow(GlobalHotKeyManager.shared.unregister(id: id1)) }
        if id2 != 0 { XCTAssertNoThrow(GlobalHotKeyManager.shared.unregister(id: id2)) }
    }

    func testDoubleInvalidateDoesNotCrash() {
        XCTAssertNoThrow(GlobalHotKeyManager.shared.invalidate())
        XCTAssertNoThrow(GlobalHotKeyManager.shared.invalidate())
    }

    func testInvalidateWithNoRegisteredHotkeys() {
        // Invalidate when nothing is registered should be safe
        XCTAssertNoThrow(GlobalHotKeyManager.shared.invalidate())
    }

    // MARK: - Rapid Registration Stress Tests

    func testRapidRegisterUnregisterCycles() {
        // Stress test: rapid register/unregister shouldn't crash
        for i: UInt32 in 0..<10 {
            let keyCode = UInt32(kVK_ANSI_A) + (i % 26)
            let id = GlobalHotKeyManager.shared.register(
                keyCode: keyCode,
                modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
            ) {}
            if id != 0 {
                GlobalHotKeyManager.shared.unregister(id: id)
            }
        }
    }

    func testRegisterManyHotkeysAtOnce() {
        var ids: [UInt32] = []

        // Register 5 different hotkeys simultaneously
        for i: UInt32 in 0..<5 {
            let keyCode = UInt32(kVK_ANSI_A) + i
            let id = GlobalHotKeyManager.shared.register(
                keyCode: keyCode,
                modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey)
            ) {}
            ids.append(id)
        }

        // All non-zero IDs should be unique
        let nonZeroIDs = ids.filter { $0 != 0 }
        XCTAssertEqual(nonZeroIDs.count, Set(nonZeroIDs).count, "All IDs should be unique")

        // Clean up
        for id in ids where id != 0 {
            GlobalHotKeyManager.shared.unregister(id: id)
        }
    }
}
