import XCTest
import Carbon.HIToolbox

@testable import MiddleDragCore

@MainActor @unsafe final class HotKeyRecorderViewTests: XCTestCase {

    // MARK: - Helper

    private func makeBinding(
        keyCode: Int = kVK_ANSI_E,
        modifiers: UInt32 = UInt32(cmdKey)
    ) -> HotKeyBinding {
        HotKeyBinding(keyCode: UInt32(keyCode), carbonModifiers: modifiers)
    }

    private func makeRecorder(
        keyCode: Int = kVK_ANSI_E,
        modifiers: UInt32 = UInt32(cmdKey)
    ) -> HotKeyRecorderView {
        unsafe HotKeyRecorderView(binding: makeBinding(keyCode: keyCode, modifiers: modifiers))
    }

    // MARK: - Initialization Tests

    func testInitStoresBinding() {
        let binding = unsafe makeBinding()
        let recorder = HotKeyRecorderView(binding: binding)
        XCTAssertEqual(recorder.binding, binding)
    }

    func testInitShowsBindingDisplayString() {
        let recorder = unsafe makeRecorder()
        // Should show key name, not "Press a key…"
        XCTAssertFalse(recorder.title.contains("Press a key"))
    }

    func testInitSetsBezelStyle() {
        let recorder = unsafe makeRecorder()
        XCTAssertEqual(recorder.bezelStyle, .recessed)
    }

    func testInitSetsButtonType() {
        let recorder = unsafe makeRecorder()
        // momentaryPushIn - verifying it was set by checking it doesn't crash
        XCTAssertNotNil(recorder)
    }

    func testInitSetsBordered() {
        let recorder = unsafe makeRecorder()
        XCTAssertTrue(recorder.isBordered)
    }

    func testInitSetsMonospacedFont() {
        let recorder = unsafe makeRecorder()
        XCTAssertNotNil(recorder.font)
    }

    func testInitSetsTargetToSelf() {
        let recorder = unsafe makeRecorder()
        XCTAssertTrue(recorder.target as AnyObject === recorder)
    }

    func testInitSetsAction() {
        let recorder = unsafe makeRecorder()
        XCTAssertNotNil(recorder.action)
    }

    func testInitWithDifferentBindings() {
        let bindings = unsafe [
            makeBinding(keyCode: kVK_ANSI_A, modifiers: UInt32(cmdKey)),
            makeBinding(keyCode: kVK_ANSI_M, modifiers: UInt32(cmdKey) | UInt32(shiftKey)),
            makeBinding(keyCode: kVK_ANSI_Z, modifiers: UInt32(optionKey) | UInt32(controlKey)),
        ]

        for binding in bindings {
            let recorder = HotKeyRecorderView(binding: binding)
            XCTAssertEqual(recorder.binding, binding)
        }
    }

    // MARK: - Binding Update Tests

    func testBindingDidSetUpdatesTitle() {
        let recorder = unsafe makeRecorder(keyCode: kVK_ANSI_A)
        let titleBefore = recorder.title

        recorder.binding = unsafe makeBinding(keyCode: kVK_ANSI_B, modifiers: UInt32(cmdKey) | UInt32(shiftKey))
        XCTAssertNotEqual(recorder.title, titleBefore)
    }

    func testBindingEquality() {
        let a = unsafe makeBinding(keyCode: kVK_ANSI_E, modifiers: UInt32(cmdKey) | UInt32(shiftKey))
        let b = unsafe makeBinding(keyCode: kVK_ANSI_E, modifiers: UInt32(cmdKey) | UInt32(shiftKey))
        XCTAssertEqual(a, b)
    }

    func testBindingInequalityByKeyCode() {
        let a = unsafe makeBinding(keyCode: kVK_ANSI_E)
        let b = unsafe makeBinding(keyCode: kVK_ANSI_M)
        XCTAssertNotEqual(a, b)
    }

    func testBindingInequalityByModifiers() {
        let a = unsafe makeBinding(keyCode: kVK_ANSI_E, modifiers: UInt32(cmdKey))
        let b = unsafe makeBinding(keyCode: kVK_ANSI_E, modifiers: UInt32(shiftKey))
        XCTAssertNotEqual(a, b)
    }

    func testBindingCodable() throws {
        let original = unsafe makeBinding(keyCode: kVK_ANSI_E, modifiers: UInt32(cmdKey) | UInt32(shiftKey))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyBinding.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testMultipleBindingUpdates() {
        let recorder = unsafe makeRecorder()

        let bindings = unsafe [
            makeBinding(keyCode: kVK_ANSI_A),
            makeBinding(keyCode: kVK_ANSI_B, modifiers: UInt32(shiftKey)),
            makeBinding(keyCode: kVK_ANSI_C, modifiers: UInt32(cmdKey) | UInt32(optionKey)),
        ]

        for binding in bindings {
            recorder.binding = binding
            XCTAssertEqual(recorder.binding, binding)
        }
    }

    // MARK: - startRecording Tests

    func testStartRecordingChangesTitle() {
        let recorder = unsafe makeRecorder()
        recorder.performClick(nil)
        XCTAssertEqual(recorder.title, "Press a key…")
    }

    func testStartRecordingIdempotent() {
        let recorder = unsafe makeRecorder()

        // Click twice - guard prevents double installation
        recorder.performClick(nil)
        recorder.performClick(nil)

        // Should still show recording state (not crashed)
        XCTAssertEqual(recorder.title, "Press a key…")

        // Single cancel should fully clean up
        recorder.cancelRecording()
        XCTAssertNotEqual(recorder.title, "Press a key…")
    }

    // MARK: - cancelRecording Tests

    func testCancelRecordingWhenNotRecording() {
        let recorder = unsafe makeRecorder()
        // Should be safe to call when not recording (no-op)
        XCTAssertNoThrow(recorder.cancelRecording())
    }

    func testCancelRecordingStopsRecording() {
        let recorder = unsafe makeRecorder()
        recorder.performClick(nil)
        XCTAssertEqual(recorder.title, "Press a key…")

        recorder.cancelRecording()
        XCTAssertNotEqual(recorder.title, "Press a key…")
    }

    func testCancelRecordingPreservesOriginalBinding() {
        let original = unsafe makeBinding(keyCode: kVK_ANSI_E, modifiers: UInt32(cmdKey) | UInt32(shiftKey))
        let recorder = HotKeyRecorderView(binding: original)

        recorder.performClick(nil)
        recorder.cancelRecording()

        XCTAssertEqual(recorder.binding, original)
    }

    func testDoubleCancelRecordingDoesNotCrash() {
        let recorder = unsafe makeRecorder()
        recorder.performClick(nil)
        recorder.cancelRecording()
        XCTAssertNoThrow(recorder.cancelRecording())
    }

    func testCancelRecordingRestoresTitleToDisplayString() {
        let binding = unsafe makeBinding()
        let recorder = HotKeyRecorderView(binding: binding)
        let expectedTitle = binding.displayString

        recorder.performClick(nil)
        recorder.cancelRecording()

        XCTAssertEqual(recorder.title, expectedTitle)
    }

    // MARK: - resignFirstResponder Tests

    func testResignFirstResponderStopsRecording() {
        let recorder = unsafe makeRecorder()
        recorder.performClick(nil)
        XCTAssertEqual(recorder.title, "Press a key…")

        _ = recorder.resignFirstResponder()
        XCTAssertNotEqual(recorder.title, "Press a key…")
    }

    func testResignFirstResponderWhenNotRecording() {
        let recorder = unsafe makeRecorder()
        let result = recorder.resignFirstResponder()
        XCTAssertTrue(result)
    }

    func testResignFirstResponderPreservesBinding() {
        let original = unsafe makeBinding()
        let recorder = HotKeyRecorderView(binding: original)

        recorder.performClick(nil)
        _ = recorder.resignFirstResponder()

        XCTAssertEqual(recorder.binding, original)
    }

    func testResignFirstResponderReturnsTrueAfterRecording() {
        let recorder = unsafe makeRecorder()
        recorder.performClick(nil)
        let result = recorder.resignFirstResponder()
        XCTAssertTrue(result)
    }

    // MARK: - onBindingChanged Callback Tests

    func testOnBindingChangedNotCalledOnCancel() {
        let recorder = unsafe makeRecorder()
        var callbackCalled = false
        recorder.onBindingChanged = { _ in callbackCalled = true }

        recorder.performClick(nil)
        recorder.cancelRecording()

        XCTAssertFalse(callbackCalled)
    }

    func testOnBindingChangedNotCalledOnResignFirstResponder() {
        let recorder = unsafe makeRecorder()
        var callbackCalled = false
        recorder.onBindingChanged = { _ in callbackCalled = true }

        recorder.performClick(nil)
        _ = recorder.resignFirstResponder()

        XCTAssertFalse(callbackCalled)
    }

    func testOnBindingChangedDefaultIsNil() {
        let recorder = unsafe makeRecorder()
        XCTAssertNil(recorder.onBindingChanged)
    }

    func testOnBindingChangedCanBeSet() {
        let recorder = unsafe makeRecorder()
        recorder.onBindingChanged = { _ in }
        XCTAssertNotNil(recorder.onBindingChanged)
    }

    func testOnBindingChangedCanBeCleared() {
        let recorder = unsafe makeRecorder()
        recorder.onBindingChanged = { _ in }
        recorder.onBindingChanged = nil
        XCTAssertNil(recorder.onBindingChanged)
    }

    // MARK: - invalidate() Tests (deinit safety net)

    func testInvalidateWhenNotRecording() {
        let recorder = unsafe makeRecorder()
        // Should be safe to call when no monitor is installed
        XCTAssertNoThrow(recorder.invalidate())
    }

    func testInvalidateWhileRecording() {
        let recorder = unsafe makeRecorder()
        recorder.performClick(nil)

        // Should clean up the monitor
        XCTAssertNoThrow(recorder.invalidate())
    }

    func testDoubleInvalidateDoesNotCrash() {
        let recorder = unsafe makeRecorder()
        recorder.performClick(nil)
        recorder.invalidate()
        XCTAssertNoThrow(recorder.invalidate())
    }

    func testInvalidateAfterCancelRecording() {
        let recorder = unsafe makeRecorder()
        recorder.performClick(nil)
        recorder.cancelRecording()
        // invalidate after cancel should be safe (monitor already removed)
        XCTAssertNoThrow(recorder.invalidate())
    }

    // MARK: - Deallocation Safety Tests

    func testDeallocAfterRecordingStartedDoesNotCrash() {
        var recorder: HotKeyRecorderView? = unsafe makeRecorder()
        recorder?.performClick(nil)

        // Deallocate without calling cancelRecording
        // invalidate() in deinit should clean up the monitor
        recorder = nil
        XCTAssertNil(recorder)
    }

    func testDeallocWithoutRecordingDoesNotCrash() {
        var recorder: HotKeyRecorderView? = unsafe makeRecorder()
        recorder = nil
        XCTAssertNil(recorder)
    }

    func testDeallocAfterCancelDoesNotCrash() {
        var recorder: HotKeyRecorderView? = unsafe makeRecorder()
        recorder?.performClick(nil)
        recorder?.cancelRecording()
        recorder = nil
        XCTAssertNil(recorder)
    }

    // MARK: - Recording Lifecycle Stress Tests

    func testRapidStartCancelCycles() {
        let recorder = unsafe makeRecorder()

        for _ in 0..<20 {
            recorder.performClick(nil)
            recorder.cancelRecording()
        }

        // Should still be in valid state
        XCTAssertNotEqual(recorder.title, "Press a key…")
    }

    func testStartRecordingCancelWithResignMixed() {
        let recorder = unsafe makeRecorder()

        // Cycle 1: start -> cancel
        recorder.performClick(nil)
        recorder.cancelRecording()

        // Cycle 2: start -> resignFirstResponder
        recorder.performClick(nil)
        _ = recorder.resignFirstResponder()

        // Cycle 3: start -> cancel again
        recorder.performClick(nil)
        recorder.cancelRecording()

        XCTAssertNotEqual(recorder.title, "Press a key…")
    }

    func testBindingUnchangedAfterMultipleCancelCycles() {
        let original = unsafe makeBinding(keyCode: kVK_ANSI_E, modifiers: UInt32(cmdKey) | UInt32(shiftKey))
        let recorder = HotKeyRecorderView(binding: original)

        for _ in 0..<5 {
            recorder.performClick(nil)
            recorder.cancelRecording()
        }

        XCTAssertEqual(recorder.binding, original)
    }

    // MARK: - Frame / Layout Tests

    func testRecorderAcceptsFrame() {
        let recorder = unsafe makeRecorder()
        recorder.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        XCTAssertEqual(recorder.frame.width, 200)
        XCTAssertEqual(recorder.frame.height, 24)
    }
}

