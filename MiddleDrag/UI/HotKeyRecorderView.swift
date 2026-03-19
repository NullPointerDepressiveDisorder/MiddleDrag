//
//  HotKeyRecorderView.swift
//  MiddleDrag
//

import Cocoa
import Carbon.HIToolbox

/// A button that captures the next key + modifier combo when clicked.
/// Displays the current binding as a human-readable string (e.g. "⌘⇧E").
@MainActor
final class HotKeyRecorderView: NSButton {

    var binding: HotKeyBinding {
        didSet { updateLabel() }
    }

    var onBindingChanged: ((HotKeyBinding) -> Void)?

    private var isRecording = false
    private var localMonitor: Any?

    init(binding: HotKeyBinding) {
        self.binding = binding
        super.init(frame: .zero)
        bezelStyle = .recessed
        setButtonType(.momentaryPushIn)
        isBordered = true
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        updateLabel()
        target = self
        action = #selector(startRecording)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        // Safety net: ensure the local monitor is removed even if stopRecording
        // was never called (e.g. alert dismissed without resignFirstResponder)
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func updateLabel() {
        title = isRecording ? "Press a key…" : binding.displayString
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        updateLabel()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil // swallow the event
        }
    }

    /// Cancel any in-progress recording and remove the keyboard monitor.
    /// Call this when the hosting UI is being dismissed to prevent leaked monitors.
    func cancelRecording() {
        if isRecording { stopRecording() }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        updateLabel()
    }

    private func handleKeyDown(_ event: NSEvent) {
        let modifiers = GlobalHotKeyManager.carbonModifiers(from: event.modifierFlags)

        // Escape cancels without changing the binding
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Require at least one modifier (bare keys are too easy to trigger accidentally)
        guard modifiers != 0 else { return }

        let newBinding = HotKeyBinding(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers
        )

        binding = newBinding
        stopRecording()
        onBindingChanged?(newBinding)
    }

    // If the view loses focus while recording, cancel
    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }
}

