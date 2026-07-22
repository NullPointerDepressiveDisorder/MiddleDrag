import Cocoa

/// Guided calibration wizard (plan section 7): walks the user through natural
/// hand postures, records a few seconds per step, validates each sample, and
/// derives per-user classifier thresholds from the accepted recordings.
@MainActor
final class CalibrationWizardController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    private weak var multitouchManager: MultitouchManager?

    private let steps = CalibrationStep.wizardSequence
    private var stepIndex = 0

    private var acceptedSessions: [Int: TouchDebugSession] = [:]
    private var capturedFrames: [TouchDebugFrame] = []
    private var isCapturing = false
    private var captureStartedAt: Double = 0
    private var captureGeneration = 0

    private let stepTitleLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(wrappingLabelWithString: "")
    private let liveLabel = NSTextField(labelWithString: "Touch the trackpad to see live data")
    private let resultLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "Record", target: nil, action: nil)
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)

    // MARK: - Initialization

    init(multitouchManager: MultitouchManager) {
        self.multitouchManager = multitouchManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Calibrate Touch Classification"
        window.center()

        super.init(window: window)

        window.delegate = self
        buildContent()
        showStep(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    func show() {
        attachObserver()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        multitouchManager?.touchDebugObserver = nil
        isCapturing = false
        captureGeneration += 1
    }

    private func attachObserver() {
        // Shares the single observer slot with the Debug Touches window; the most
        // recently opened tool receives the frames.
        multitouchManager?.touchDebugObserver = { [weak self] frame in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.ingest(frame)
                }
            }
        }
    }

    // MARK: - Layout

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        stepTitleLabel.font = .boldSystemFont(ofSize: 14)
        instructionLabel.font = .systemFont(ofSize: 13)
        instructionLabel.preferredMaxLayoutWidth = 440
        liveLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        liveLabel.textColor = .secondaryLabelColor
        resultLabel.font = .systemFont(ofSize: 12)

        recordButton.target = self
        recordButton.action = #selector(startCapture)
        backButton.target = self
        backButton.action = #selector(goBack)
        nextButton.target = self
        nextButton.action = #selector(goNext)

        let buttonRow = NSStackView(views: [recordButton, backButton, nextButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            stepTitleLabel, instructionLabel, liveLabel, resultLabel, buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Step Navigation

    private func showStep(_ index: Int) {
        stepIndex = index
        let step = steps[index]

        stepTitleLabel.stringValue = "Step \(index + 1) of \(steps.count)"
        instructionLabel.stringValue = step.instruction
        resultLabel.stringValue =
            acceptedSessions[index] != nil ? "Sample accepted." : ""
        resultLabel.textColor = .labelColor

        recordButton.title = "Record \(Int(step.duration))s"
        recordButton.isEnabled = true
        backButton.isEnabled = index > 0
        updateNextButton()
    }

    private func updateNextButton() {
        let isLast = stepIndex == steps.count - 1
        nextButton.title = isLast ? "Finish" : "Next"
        nextButton.isEnabled = acceptedSessions[stepIndex] != nil
    }

    @objc private func goBack() {
        guard stepIndex > 0 else { return }
        cancelCapture()
        showStep(stepIndex - 1)
    }

    @objc private func goNext() {
        cancelCapture()
        if stepIndex == steps.count - 1 {
            finishCalibration()
        } else {
            showStep(stepIndex + 1)
        }
    }

    // MARK: - Capture

    @objc private func startCapture() {
        let step = steps[stepIndex]

        capturedFrames.removeAll()
        captureStartedAt = Date().timeIntervalSince1970
        isCapturing = true
        captureGeneration += 1
        let generation = captureGeneration

        recordButton.isEnabled = false
        recordButton.title = "Recording…"
        resultLabel.stringValue = "Recording — perform the action now."
        resultLabel.textColor = .secondaryLabelColor

        DispatchQueue.main.asyncAfter(deadline: .now() + step.duration) { [weak self] in
            guard let self, self.captureGeneration == generation else { return }
            self.finishCapture()
        }
    }

    private func cancelCapture() {
        isCapturing = false
        captureGeneration += 1
    }

    private func finishCapture() {
        isCapturing = false
        let step = steps[stepIndex]

        let verdict = CalibrationValidator.validate(frames: capturedFrames, step: step)
        resultLabel.stringValue = verdict.message
        resultLabel.textColor = verdict.accepted ? .systemGreen : .systemRed

        if verdict.accepted {
            let version =
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "unknown"
            acceptedSessions[stepIndex] = TouchDebugSession(
                scenario: step.scenario.rawValue,
                startedAt: captureStartedAt,
                endedAt: Date().timeIntervalSince1970,
                appVersion: version,
                frames: capturedFrames.map {
                    TouchDebugRecordedFrame(wallClock: Date().timeIntervalSince1970, frame: $0)
                }
            )
        }

        recordButton.isEnabled = true
        recordButton.title = "Record \(Int(step.duration))s"
        updateNextButton()
    }

    private func ingest(_ frame: TouchDebugFrame) {
        let classified = frame.classified
        liveLabel.stringValue =
            "contacts \(classified.rawCount)   classified digits \(classified.digitCount)   "
            + "incidental \(classified.incidentalCount)"

        if isCapturing {
            capturedFrames.append(frame)
        }
    }

    // MARK: - Finish

    private func finishCalibration() {
        let sessions = acceptedSessions.values.map { $0 }
        let summary = CalibrationDerivation.derive(from: sessions)

        do {
            try TouchCalibrationStore.shared.save(summary.derived)
            multitouchManager?.applyTouchCalibration(summary.derived)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Save Calibration"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let sizeText = unsafe String(format: "%.3f", summary.derived.maxTypicalDigitMajorAxis)
        let confidenceText = unsafe String(
            format: "%.2f", summary.derived.extraContactIgnoreConfidence)
        let alert = NSAlert()
        alert.messageText = "Calibration Complete"
        alert.informativeText = """
            Derived from \(summary.digitSampleCount) digit samples and \
            \(summary.incidentalSampleCount) incidental-contact samples.

            Typical digit size: \(sizeText)
            Ignore confidence: \(confidenceText)

            The new thresholds are active now and will load automatically at launch.
            """
        alert.runModal()

        window?.close()
    }
}
