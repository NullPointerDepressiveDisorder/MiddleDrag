import Cocoa

/// "Debug Touches…" window: live visualization of classified touch frames with
/// recording and JSON/CSV export for classifier tuning and calibration capture.
@MainActor
final class TouchDebugWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    private weak var multitouchManager: MultitouchManager?

    private let surfaceView = TouchDebugSurfaceView()
    private let countsLabel = NSTextField(labelWithString: "Waiting for touch data…")
    private let stateLabel = NSTextField(labelWithString: "")
    private let scenarioPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let recordButton = NSButton(title: "Start Recording", target: nil, action: nil)
    private let exportJSONButton = NSButton(title: "Export JSON…", target: nil, action: nil)
    private let exportCSVButton = NSButton(title: "Export CSV…", target: nil, action: nil)
    private let recordingStatusLabel = NSTextField(labelWithString: "Not recording")

    private var isRecording = false
    private var recordedFrames: [TouchDebugRecordedFrame] = []
    private var recordingStartedAt: Double = 0

    /// ~5 minutes at 120 Hz; prevents unbounded memory growth if a recording is forgotten.
    private let maxRecordedFrames = 36_000

    // MARK: - Initialization

    init(multitouchManager: MultitouchManager) {
        self.multitouchManager = multitouchManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MiddleDrag Touch Debug"
        window.minSize = NSSize(width: 480, height: 420)
        window.center()

        super.init(window: window)

        window.delegate = self
        buildContent()
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
        isRecording = false
    }

    private func attachObserver() {
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

        countsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        stateLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        stateLabel.textColor = .secondaryLabelColor
        recordingStatusLabel.font = .systemFont(ofSize: 11)
        recordingStatusLabel.textColor = .secondaryLabelColor

        surfaceView.wantsLayer = true
        surfaceView.translatesAutoresizingMaskIntoConstraints = false

        scenarioPopUp.addItems(withTitles: TouchDebugScenario.allCases.map(\.rawValue))

        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        exportJSONButton.target = self
        exportJSONButton.action = #selector(exportJSON)
        exportCSVButton.target = self
        exportCSVButton.action = #selector(exportCSV)
        updateExportButtons()

        let headerStack = NSStackView(views: [countsLabel, stateLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2

        let controlsStack = NSStackView(views: [
            scenarioPopUp, recordButton, exportJSONButton, exportCSVButton,
            recordingStatusLabel,
        ])
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 8

        let mainStack = NSStackView(views: [headerStack, surfaceView, controlsStack])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 8
        mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            surfaceView.widthAnchor.constraint(
                equalTo: mainStack.widthAnchor, constant: -24),
        ])
        surfaceView.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    // MARK: - Frame Ingestion

    private func ingest(_ frame: TouchDebugFrame) {
        surfaceView.update(with: frame)

        let classified = frame.classified
        countsLabel.stringValue =
            "raw \(classified.rawCount)   digits \(classified.digitCount)   "
            + "incidental \(classified.incidentalCount)   "
            + "uncertain \(classified.uncertainTouches.count)"
        let eventState =
            frame.isDragging ? "dragging (suppressing)" : frame.isPassThrough ? "pass-through" : "idle"
        stateLabel.stringValue = "recognizer: \(frame.recognizerState)   events: \(eventState)"

        if isRecording {
            if recordedFrames.count < maxRecordedFrames {
                recordedFrames.append(
                    TouchDebugRecordedFrame(
                        wallClock: Date().timeIntervalSince1970, frame: frame))
                recordingStatusLabel.stringValue = "Recording… \(recordedFrames.count) frames"
            } else {
                stopRecording()
            }
        }
    }

    // MARK: - Recording

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            recordedFrames.removeAll()
            recordingStartedAt = Date().timeIntervalSince1970
            isRecording = true
            recordButton.title = "Stop Recording"
            recordingStatusLabel.stringValue = "Recording… 0 frames"
            scenarioPopUp.isEnabled = false
            updateExportButtons()
        }
    }

    private func stopRecording() {
        isRecording = false
        recordButton.title = "Start Recording"
        recordingStatusLabel.stringValue = "Recorded \(recordedFrames.count) frames"
        scenarioPopUp.isEnabled = true
        updateExportButtons()
    }

    private func updateExportButtons() {
        let canExport = !isRecording && !recordedFrames.isEmpty
        exportJSONButton.isEnabled = canExport
        exportCSVButton.isEnabled = canExport
    }

    private func currentSession() -> TouchDebugSession {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        return TouchDebugSession(
            scenario: scenarioPopUp.titleOfSelectedItem ?? TouchDebugScenario.unlabeled.rawValue,
            startedAt: recordingStartedAt,
            endedAt: recordedFrames.last?.wallClock ?? recordingStartedAt,
            appVersion: version,
            frames: recordedFrames
        )
    }

    // MARK: - Export

    @objc private func exportJSON() {
        exportSession(fileExtension: "json") { session in
            try session.jsonData()
        }
    }

    @objc private func exportCSV() {
        exportSession(fileExtension: "csv") { session in
            session.csvData()
        }
    }

    private func exportSession(
        fileExtension: String,
        encode: @escaping (TouchDebugSession) throws -> Data
    ) {
        guard let window, !recordedFrames.isEmpty else { return }

        let session = currentSession()
        let scenarioSlug = session.scenario.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let timestamp = Int(session.startedAt)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "middledrag-touches-\(scenarioSlug)-\(timestamp).\(fileExtension)"
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try encode(session)
                try data.write(to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

// MARK: - Surface View

/// Draws the trackpad surface with one ellipse per contact, colored by
/// classified role, with motion trails and the digit-cluster centroid.
@MainActor
final class TouchDebugSurfaceView: NSView {

    private var currentFrame: TouchDebugFrame?
    private var trails: [Int32: [MTPoint]] = [:]
    private let maxTrailLength = 48

    /// Axis units from the multitouch framework are undocumented and vary by
    /// device, so the drawing scale adapts: the largest contact seen so far maps
    /// to a fixed fraction of the surface width. Slowly decays so an early palm
    /// does not permanently shrink fingertip ellipses. The labels show the raw
    /// numbers, so this only affects the picture, not the data.
    private var observedMaxAxis: CGFloat = 0.5

    override var isFlipped: Bool { false }

    func update(with frame: TouchDebugFrame) {
        currentFrame = frame

        var activeIDs = Set<Int32>()
        for touch in frame.classified.classifiedTouches {
            let id = touch.sample.fingerID
            activeIDs.insert(id)
            trails[id, default: []].append(touch.sample.position)
            if let count = trails[id]?.count, count > maxTrailLength {
                trails[id]?.removeFirst(count - maxTrailLength)
            }
            observedMaxAxis = max(observedMaxAxis * 0.999, CGFloat(touch.sample.majorAxis))
        }
        trails = trails.filter { activeIDs.contains($0.key) }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let surface = bounds.insetBy(dx: 2, dy: 2)

        // Trackpad surface
        let background = NSBezierPath(roundedRect: surface, xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        background.fill()
        NSColor.separatorColor.setStroke()
        background.lineWidth = 1
        background.stroke()

        // Grid
        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
        for fraction in stride(from: 0.25, through: 0.75, by: 0.25) {
            let vertical = NSBezierPath()
            vertical.move(to: point(x: Float(fraction), y: 0, in: surface))
            vertical.line(to: point(x: Float(fraction), y: 1, in: surface))
            vertical.lineWidth = 0.5
            vertical.stroke()

            let horizontal = NSBezierPath()
            horizontal.move(to: point(x: 0, y: Float(fraction), in: surface))
            horizontal.line(to: point(x: 1, y: Float(fraction), in: surface))
            horizontal.lineWidth = 0.5
            horizontal.stroke()
        }

        guard let frame = currentFrame else {
            drawCenteredText(
                "No touch data — enable MiddleDrag and touch the trackpad", in: surface)
            return
        }

        drawTrails(in: surface)

        for touch in frame.classified.classifiedTouches {
            drawTouch(touch, in: surface)
        }

        drawDigitCentroid(frame.classified, in: surface)
    }

    // MARK: - Drawing Helpers

    private func point(x: Float, y: Float, in surface: NSRect) -> NSPoint {
        NSPoint(
            x: surface.minX + surface.width * CGFloat(x),
            y: surface.minY + surface.height * CGFloat(y)
        )
    }

    private func color(for role: TouchRole) -> NSColor {
        switch role {
        case .digit: return .systemGreen
        case .probableThumb: return .systemOrange
        case .probablePalm: return .systemRed
        case .ignored: return .systemGray
        case .uncertain: return .systemYellow
        }
    }

    private func drawTrails(in surface: NSRect) {
        for positions in trails.values {
            guard positions.count > 1 else { continue }
            for (index, position) in positions.enumerated() {
                let alpha = 0.05 + 0.25 * CGFloat(index) / CGFloat(positions.count)
                NSColor.labelColor.withAlphaComponent(alpha).setFill()
                let center = point(x: position.x, y: position.y, in: surface)
                let dot = NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }

    private func drawTouch(_ touch: ClassifiedTouch, in surface: NSRect) {
        let sample = touch.sample
        let center = point(x: sample.position.x, y: sample.position.y, in: surface)
        let roleColor = color(for: touch.role)

        // Largest contact seen so far draws at ~9% of the surface width.
        let pointsPerAxisUnit = surface.width * 0.09 / max(observedMaxAxis, 0.001)
        let width = max(12, CGFloat(sample.majorAxis) * pointsPerAxisUnit)
        let height = max(12, CGFloat(sample.minorAxis) * pointsPerAxisUnit)

        // Ellipse rotated by the reported contact angle
        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: CGFloat(sample.angle))
        transform.concat()

        let ellipseRect = NSRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let ellipse = NSBezierPath(ovalIn: ellipseRect)
        roleColor.withAlphaComponent(0.35).setFill()
        ellipse.fill()
        roleColor.setStroke()
        ellipse.lineWidth = 1.5
        ellipse.stroke()

        NSGraphicsContext.current?.restoreGraphicsState()

        // Velocity vector
        let speed = hypot(CGFloat(sample.velocity.x), CGFloat(sample.velocity.y))
        if speed > 0.001 {
            let vector = NSBezierPath()
            vector.move(to: center)
            vector.line(
                to: NSPoint(
                    x: center.x + CGFloat(sample.velocity.x) * surface.width * 0.2,
                    y: center.y + CGFloat(sample.velocity.y) * surface.height * 0.2
                ))
            roleColor.setStroke()
            vector.lineWidth = 1
            vector.stroke()
        }

        // Label
        let confidencePercent = Int(touch.confidence * 100)
        var label = "id \(sample.fingerID)  \(touch.role.rawValue)  \(confidencePercent)%\n"
        label += unsafe String(
            format: "z %.2f  axes %.2f/%.2f", sample.zTotal, sample.majorAxis, sample.minorAxis)
        if !touch.scoreBreakdown.reasons.isEmpty {
            label += "\n" + touch.scoreBreakdown.reasons.joined(separator: ", ")
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        var textOrigin = NSPoint(
            x: center.x - textSize.width / 2,
            y: center.y - height / 2 - textSize.height - 4
        )
        textOrigin.x = min(max(textOrigin.x, surface.minX + 2), surface.maxX - textSize.width - 2)
        if textOrigin.y < surface.minY + 2 {
            textOrigin.y = center.y + height / 2 + 4
        }
        text.draw(at: textOrigin)
    }

    private func drawDigitCentroid(_ classified: ClassifiedTouchFrame, in surface: NSRect) {
        let digits = classified.digitTouches
        guard digits.count > 1 else { return }

        let sumX = digits.reduce(Float(0)) { $0 + $1.sample.position.x }
        let sumY = digits.reduce(Float(0)) { $0 + $1.sample.position.y }
        let center = point(
            x: sumX / Float(digits.count), y: sumY / Float(digits.count), in: surface)

        NSColor.systemBlue.setStroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: center.x - 6, y: center.y))
        cross.line(to: NSPoint(x: center.x + 6, y: center.y))
        cross.move(to: NSPoint(x: center.x, y: center.y - 6))
        cross.line(to: NSPoint(x: center.x, y: center.y + 6))
        cross.lineWidth = 1.5
        cross.stroke()
    }

    private func drawCenteredText(_ string: String, in surface: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let text = NSAttributedString(string: string, attributes: attributes)
        let size = text.size()
        text.draw(
            at: NSPoint(
                x: surface.midX - size.width / 2,
                y: surface.midY - size.height / 2
            ))
    }
}
