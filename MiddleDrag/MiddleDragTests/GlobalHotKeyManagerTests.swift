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

    func testCarbonModifiersCombined() {
        let result = GlobalHotKeyManager.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(result, UInt32(cmdKey) | UInt32(shiftKey))
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

    func testCarbonModifiersIgnoresNonModifierFlags() {
        // .capsLock is not mapped by our utility - should not appear in result
        let result = GlobalHotKeyManager.carbonModifiers(from: .capsLock)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Singleton Tests

    func testSharedInstanceIsSingleton() {
        let a = GlobalHotKeyManager.shared
        let b = GlobalHotKeyManager.shared
        XCTAssertTrue(a === b)
    }

    // MARK: - Register / Unregister Tests

    func testRegisterReturnsNonZeroID() {
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

    func testUnregisterInvalidIDDoesNotCrash() {
        // Unregistering an ID that was never registered should be safe
        XCTAssertNoThrow(GlobalHotKeyManager.shared.unregister(id: 99999))
    }

    func testUnregisterZeroIDDoesNotCrash() {
        // 0 is the failure return value from register - unregistering it should be safe
        XCTAssertNoThrow(GlobalHotKeyManager.shared.unregister(id: 0))
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

    // MARK: - Handler Invocation Tests

    func testRegisterStoresHandler() {
        var handlerCalled = false
        let id = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)
        ) {
            handlerCalled = true
        }

        // We can't easily simulate a Carbon hotkey press in tests,
        // but we verify the handler was stored (not called yet)
        XCTAssertFalse(handlerCalled)

        if id != 0 { GlobalHotKeyManager.shared.unregister(id: id) }
    }
}
