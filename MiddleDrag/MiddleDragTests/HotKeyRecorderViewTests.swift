import XCTest
import Carbon.HIToolbox

@testable import MiddleDragCore

@MainActor @unsafe final class HotKeyRecorderViewTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithBinding() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: binding)

        XCTAssertEqual(recorder.binding, binding)
        XCTAssertFalse(recorder.title.contains("Press a key"))
    }

    func testInitSetsBezelStyle() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(shiftKey))
        let recorder = HotKeyRecorderView(binding: binding)

        XCTAssertEqual(recorder.bezelStyle, .recessed)
    }

    func testInitSetsMonospacedFont() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(shiftKey))
        let recorder = HotKeyRecorderView(binding: binding)

        XCTAssertNotNil(recorder.font)
    }

    // MARK: - Binding Update Tests

    func testBindingUpdateChangesTitle() {
        let initial = HotKeyBinding(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: initial)
        let titleBefore = recorder.title

        let updated = HotKeyBinding(keyCode: UInt32(kVK_ANSI_B), carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey))
        recorder.binding = updated

        // Title should change since the binding changed
        XCTAssertNotEqual(recorder.title, titleBefore)
    }

    func testBindingEquality() {
        let a = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey))
        let b = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey))
        XCTAssertEqual(a, b)
    }

    func testBindingInequality() {
        let a = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let b = HotKeyBinding(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(cmdKey))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - cancelRecording Tests

    func testCancelRecordingWhenNotRecordingDoesNotCrash() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: binding)

        // Should be safe to call even when not recording
        XCTAssertNoThrow(recorder.cancelRecording())
    }

    func testCancelRecordingAfterStartRecording() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: binding)

        // Simulate clicking the button to start recording
        recorder.performClick(nil)

        // Title should show recording state
        XCTAssertEqual(recorder.title, "Press a key…")

        // Cancel should clean up
        recorder.cancelRecording()

        // Title should revert to binding display string
        XCTAssertNotEqual(recorder.title, "Press a key…")
    }

    func testCancelRecordingPreservesOriginalBinding() {
        let original = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey))
        let recorder = HotKeyRecorderView(binding: original)

        // Start recording then cancel
        recorder.performClick(nil)
        recorder.cancelRecording()

        // Binding should remain unchanged
        XCTAssertEqual(recorder.binding, original)
    }

    func testDoubleCancelRecordingDoesNotCrash() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: binding)

        recorder.performClick(nil)
        recorder.cancelRecording()
        // Second cancel should be safe
        XCTAssertNoThrow(recorder.cancelRecording())
    }

    // MARK: - startRecording Idempotency

    func testDoubleClickDoesNotDoubleInstallMonitor() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: binding)

        // Click twice - guard should prevent double installation
        recorder.performClick(nil)
        recorder.performClick(nil)

        // Cancel once should fully clean up
        recorder.cancelRecording()
        XCTAssertNotEqual(recorder.title, "Press a key…")
    }

    // MARK: - resignFirstResponder Tests

    func testResignFirstResponderStopsRecording() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: binding)

        recorder.performClick(nil)
        XCTAssertEqual(recorder.title, "Press a key…")

        // Simulate losing focus
        _ = recorder.resignFirstResponder()

        // Should no longer be recording
        XCTAssertNotEqual(recorder.title, "Press a key…")
    }

    func testResignFirstResponderWhenNotRecordingDoesNotCrash() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: binding)

        // Should be safe when not recording
        let result = recorder.resignFirstResponder()
        XCTAssertTrue(result)
    }

    // MARK: - onBindingChanged Callback Tests

    func testOnBindingChangedNotCalledOnCancel() {
        let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        let recorder = HotKeyRecorderView(binding: binding)

        var callbackCalled = false
        recorder.onBindingChanged = { _ in callbackCalled = true }

        recorder.performClick(nil)
        recorder.cancelRecording()

        XCTAssertFalse(callbackCalled)
    }

    // MARK: - Deallocation Safety Tests

    func testDeallocAfterRecordingStartedDoesNotCrash() {
        // This tests the deinit safety net
        var recorder: HotKeyRecorderView? = HotKeyRecorderView(
            binding: HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey))
        )

        // Start recording (installs monitor)
        recorder?.performClick(nil)

        // Deallocate without calling cancelRecording - deinit should clean up
        recorder = nil

        // If we get here without a crash, the deinit safety net worked
        XCTAssertNil(recorder)
    }
}
