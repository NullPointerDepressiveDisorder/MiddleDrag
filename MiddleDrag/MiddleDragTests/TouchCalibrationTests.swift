import XCTest

@testable import MiddleDragCore

final class TouchCalibrationTests: XCTestCase {

    // MARK: - Helpers

    // Defaults model a real fingertip (z≈1, axes≈10/10 in device units).
    private func createTouch(
        x: Float,
        y: Float,
        zTotal: Float = 1.0,
        fingerID: Int32,
        pathIndex: Int32,
        velocity: MTPoint = MTPoint(x: 0, y: 0),
        majorAxis: Float = 10,
        minorAxis: Float = 10
    ) -> MTTouch {
        let position = MTPoint(x: x, y: y)
        let vector = MTVector(position: position, velocity: velocity)

        return MTTouch(
            frame: 0,
            timestamp: 0,
            pathIndex: pathIndex,
            state: 4,
            fingerID: fingerID,
            handID: 0,
            normalizedVector: vector,
            zTotal: zTotal,
            field9: 0,
            angle: 0,
            majorAxis: majorAxis,
            minorAxis: minorAxis,
            absoluteVector: vector,
            field14: 0,
            field15: 0,
            zDensity: 0
        )
    }

    private func sample(_ touch: MTTouch) -> TouchSample {
        TouchSample(touch: touch)
    }

    /// Runs synthetic multi-frame input through a fresh classifier and wraps the
    /// output as a recorded session, the same shape the debug recorder produces.
    private func recordSession(
        scenario: TouchDebugScenario,
        frameCount: Int,
        frameDuration: Double = 0.05,
        touchesAt: (Int, Double) -> [MTTouch]
    ) -> TouchDebugSession {
        let classifier = TouchClassifier()
        var frames: [TouchDebugRecordedFrame] = []

        for index in 0..<frameCount {
            let timestamp = Double(index) * frameDuration
            let samples = touchesAt(index, timestamp).map(sample)
            let classified = classifier.classify(
                samples: samples, timestamp: timestamp, configuration: GestureConfiguration())
            let frame = TouchDebugFrame(
                timestamp: timestamp,
                classified: classified,
                recognizerState: "idle",
                isDragging: false,
                isPassThrough: false
            )
            frames.append(TouchDebugRecordedFrame(wallClock: 1000 + timestamp, frame: frame))
        }

        return TouchDebugSession(
            scenario: scenario.rawValue,
            startedAt: 1000,
            endedAt: 1000 + Double(frameCount) * frameDuration,
            appVersion: "test",
            frames: frames
        )
    }

    /// A realistic capture shape: the thumb rests alone for the first 10 frames
    /// (0.5s), then two fingers land and scroll while the thumb stays put.
    private func scrollWithThumbSession(frameCount: Int = 30) -> TouchDebugSession {
        recordSession(
            scenario: .twoFingerScrollWithIncidental, frameCount: frameCount
        ) { index, _ in
            // A realistic resting thumb: elongated (20/10) and pressing harder (z≈2).
            let thumb = self.createTouch(
                x: 0.5, y: 0.15, zTotal: 2.0, fingerID: 9, pathIndex: 9,
                majorAxis: 20, minorAxis: 10)
            guard index >= 10 else { return [thumb] }

            let fingerY = 0.4 + 0.015 * Float(index - 10)
            let scrollVelocity = MTPoint(x: 0, y: 0.5)
            return [
                self.createTouch(
                    x: 0.35, y: fingerY, fingerID: 1, pathIndex: 1, velocity: scrollVelocity),
                self.createTouch(
                    x: 0.55, y: fingerY, fingerID: 2, pathIndex: 2, velocity: scrollVelocity),
                thumb,
            ]
        }
    }

    /// Three fingers dragging together, no incidental contact.
    private func cleanDragSession(frameCount: Int = 20) -> TouchDebugSession {
        recordSession(scenario: .threeFingerMiddleDrag, frameCount: frameCount) { index, _ in
            let y = 0.4 + 0.015 * Float(index)
            let velocity = MTPoint(x: 0, y: 0.5)
            return [
                self.createTouch(x: 0.3, y: y, fingerID: 1, pathIndex: 1, velocity: velocity),
                self.createTouch(x: 0.48, y: y, fingerID: 2, pathIndex: 2, velocity: velocity),
                self.createTouch(x: 0.66, y: y, fingerID: 3, pathIndex: 3, velocity: velocity),
            ]
        }
    }

    // MARK: - Defaults

    func testDefaultCalibrationMatchesRealHardwareReadings() {
        let calibration = TouchClassifierCalibration.default

        // Observed on a real MacBook trackpad: fingertip z≈1 axes≈10/10,
        // thumb z≈2 axes≈20/10, palm z>5. The size-evidence onset
        // (majorAxis × 1.2) must sit between a fingertip and a thumb.
        let sizeOnset = calibration.maxTypicalDigitMajorAxis * 1.2
        XCTAssertGreaterThan(sizeOnset, 10, "A fingertip must not trip size evidence")
        XCTAssertLessThan(sizeOnset, 20, "A thumb-sized contact must gain size evidence")

        // Pressure normalization: even a clicking fingertip (z≈2.5) must stay
        // below the onset, a palm press (z≈5) must exceed it.
        let clickPressure = 2.5 / calibration.maxTypicalDigitZTotal
            * calibration.maxTypicalDigitMajorAxis
        let palmPressure = 5.0 / calibration.maxTypicalDigitZTotal
            * calibration.maxTypicalDigitMajorAxis
        XCTAssertLessThanOrEqual(clickPressure, sizeOnset)
        XCTAssertGreaterThan(palmPressure, sizeOnset)

        XCTAssertEqual(calibration.extraContactIgnoreConfidence, 0.65)
    }

    // MARK: - Store

    func testStoreRoundTripAndReset() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("middledrag-calibration-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TouchCalibrationStore(directory: directory)

        XCTAssertNil(store.load(), "Fresh store should have no calibration")

        var calibration = TouchClassifierCalibration.default
        calibration.maxTypicalDigitMajorAxis = 0.33
        calibration.extraContactIgnoreConfidence = 0.7
        try store.save(calibration)

        XCTAssertEqual(store.load(), calibration)

        store.reset()
        XCTAssertNil(store.load(), "Reset should remove the stored calibration")
    }

    // MARK: - Validation

    func testValidatorAcceptsScrollWithIncidental() {
        let session = scrollWithThumbSession()
        let step = CalibrationStep.wizardSequence.first {
            $0.scenario == .twoFingerScrollWithIncidental
        }!

        let verdict = CalibrationValidator.validate(
            frames: session.frames.map(\.frame), step: step)

        XCTAssertTrue(verdict.accepted, verdict.message)
    }

    func testValidatorRejectsMissingIncidentalContact() {
        let session = recordSession(
            scenario: .twoFingerScrollWithIncidental, frameCount: 20
        ) { index, _ in
            let fingerY = 0.4 + 0.015 * Float(index)
            let velocity = MTPoint(x: 0, y: 0.5)
            return [
                self.createTouch(x: 0.35, y: fingerY, fingerID: 1, pathIndex: 1, velocity: velocity),
                self.createTouch(x: 0.55, y: fingerY, fingerID: 2, pathIndex: 2, velocity: velocity),
            ]
        }
        let step = CalibrationStep.wizardSequence.first {
            $0.scenario == .twoFingerScrollWithIncidental
        }!

        let verdict = CalibrationValidator.validate(
            frames: session.frames.map(\.frame), step: step)

        XCTAssertFalse(verdict.accepted, "Two contacts cannot validate an incidental-contact step")
    }

    func testValidatorRejectsTooFewFrames() {
        let session = scrollWithThumbSession(frameCount: 4)
        let step = CalibrationStep.wizardSequence.first {
            $0.scenario == .twoFingerScrollWithIncidental
        }!

        let verdict = CalibrationValidator.validate(
            frames: session.frames.map(\.frame), step: step)

        XCTAssertFalse(verdict.accepted)
    }

    func testValidatorRejectsWrongContactCountForCleanStep() {
        let session = scrollWithThumbSession()  // 3 contacts
        let step = CalibrationStep.wizardSequence.first { $0.scenario == .twoFingerScroll }!

        let verdict = CalibrationValidator.validate(
            frames: session.frames.map(\.frame), step: step)

        XCTAssertFalse(verdict.accepted, "A clean step must reject frames with extra contacts")
    }

    // MARK: - Derivation

    func testDerivationUsesRecordedSamples() {
        let sessions = [cleanDragSession(frameCount: 20), scrollWithThumbSession(frameCount: 30)]

        let summary = CalibrationDerivation.derive(from: sessions)

        XCTAssertGreaterThanOrEqual(summary.digitSampleCount, 30)
        XCTAssertGreaterThanOrEqual(summary.incidentalSampleCount, 15)
        // All synthetic digits have majorAxis 10 (real fingertip scale).
        XCTAssertEqual(summary.derived.maxTypicalDigitMajorAxis, 10, accuracy: 1.0)
        XCTAssertEqual(summary.derived.maxTypicalDigitZTotal, 1.0, accuracy: 0.2)
        XCTAssertLessThanOrEqual(summary.derived.minIncidentalStationaryDuration, 0.4 + 0.001)
        XCTAssertGreaterThanOrEqual(summary.derived.minIncidentalStationaryDuration, 0.05)
    }

    func testDerivationKeepsDefaultsWithoutEnoughData() {
        let summary = CalibrationDerivation.derive(from: [scrollWithThumbSession(frameCount: 3)])

        XCTAssertEqual(summary.derived, .default, "Sparse data must not move thresholds")
    }

    // MARK: - Calibration Affects Classification

    func testRaisedIgnoreConfidenceDisablesIncidentalRejection() {
        let classifier = TouchClassifier()
        classifier.calibration.extraContactIgnoreConfidence = 0.99

        let samples = [
            sample(createTouch(x: 0.35, y: 0.58, fingerID: 1, pathIndex: 1)),
            sample(createTouch(x: 0.55, y: 0.60, fingerID: 2, pathIndex: 2)),
            sample(
                createTouch(
                    x: 0.82, y: 0.52, zTotal: 5.0, fingerID: 99, pathIndex: 99,
                    majorAxis: 25, minorAxis: 15)),
        ]

        let frame = classifier.classify(
            samples: samples, timestamp: 0, configuration: GestureConfiguration())

        XCTAssertEqual(
            frame.digitCount, 3,
            "With an unreachable ignore threshold every contact stays a digit")
    }

    func testIncidentalFilterDisabledCountsEveryContact() {
        let classifier = TouchClassifier()
        var configuration = GestureConfiguration()
        configuration.incidentalFilterEnabled = false

        let samples = [
            sample(createTouch(x: 0.35, y: 0.58, fingerID: 1, pathIndex: 1)),
            sample(createTouch(x: 0.55, y: 0.60, fingerID: 2, pathIndex: 2)),
            sample(
                createTouch(
                    x: 0.82, y: 0.52, zTotal: 5.0, fingerID: 99, pathIndex: 99,
                    majorAxis: 25, minorAxis: 15)),
        ]

        let frame = classifier.classify(samples: samples, timestamp: 0, configuration: configuration)

        XCTAssertEqual(frame.digitCount, 3, "Filter off: the blatant contact counts as a digit")
        XCTAssertEqual(frame.incidentalCount, 0)
    }

    // MARK: - Session Replay (plan step 10)

    func testReplayFromJSONFixtureReproducesDigitCounts() throws {
        let original = scrollWithThumbSession()

        // Round-trip through a JSON file exactly like a captured fixture would be.
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("middledrag-fixture-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        try original.jsonData().write(to: fixtureURL)

        let loaded = try TouchDebugSession.fromJSONData(Data(contentsOf: fixtureURL))
        let replayed = TouchSessionReplayer.replay(session: loaded)

        XCTAssertEqual(replayed.count, original.frames.count)
        for (index, frame) in replayed.enumerated() {
            XCTAssertEqual(
                frame.digitCount,
                original.frames[index].frame.classified.digitCount,
                "Replay must reproduce the recorded classification at frame \(index)")
        }

        // The session's steady state: two digits, thumb ignored.
        let steadyState = replayed.dropFirst(replayed.count / 2)
        XCTAssertTrue(
            steadyState.allSatisfy { $0.digitCount == 2 },
            "Steady-state frames should classify the resting thumb as incidental")
    }

    // MARK: - Real Recording Fixtures

    /// Loads a fixture recorded on real hardware with the debug recorder.
    private func loadFixture(_ name: String) throws -> TouchDebugSession {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try TouchDebugSession.fromJSONData(Data(contentsOf: url))
    }

    func testRealPalmRestNeverTriggersMiddleDrag() throws {
        let session = try loadFixture("palm-rest.json")

        let recognizer = GestureRecognizer()
        let delegate = MockGestureRecognizerDelegate()
        recognizer.delegate = delegate

        var framesWithThreeDigits = 0
        var touchedFrames = 0
        for frame in TouchSessionReplayer.replay(session: session) {
            if frame.rawCount > 0 { touchedFrames += 1 }
            if frame.digitCount == 3 { framesWithThreeDigits += 1 }
            recognizer.processClassifiedFrame(
                frame, timestamp: frame.timestamp, modifierFlags: [])
        }

        XCTAssertFalse(
            delegate.didStartCalled,
            "A resting palm (recorded on real hardware) must never start MiddleDrag")
        XCTAssertLessThan(
            Double(framesWithThreeDigits) / Double(max(touchedFrames, 1)), 0.05,
            "Palm fragments should almost never be classified as exactly three digits")
    }

    func testRealThreeFingerDragWithThumbClickSurvives() throws {
        // Real recording: three-finger drags with a thumb that rests, lifts,
        // re-lands, and physically clicks mid-drag. The drag must never be
        // cancelled — no four-finger system gesture occurs in this capture.
        let session = try loadFixture("three-finger-drag-with-thumb-click.json")

        let recognizer = GestureRecognizer()
        let delegate = MockGestureRecognizerDelegate()
        recognizer.delegate = delegate

        for frame in TouchSessionReplayer.replay(session: session) {
            recognizer.processClassifiedFrame(
                frame, timestamp: frame.timestamp, modifierFlags: [])
        }

        XCTAssertTrue(
            delegate.didBeginDraggingCalled,
            "The recording contains real three-finger drags that should be recognized")
        XCTAssertFalse(
            delegate.didCancelDraggingCalled,
            "A thumb resting, re-landing, or clicking mid-drag must never cancel the drag")
    }

    func testRealFingerWithRestingThumbNeverTriggersMiddleDrag() throws {
        let session = try loadFixture("one-finger-with-thumb.json")

        let recognizer = GestureRecognizer()
        let delegate = MockGestureRecognizerDelegate()
        recognizer.delegate = delegate

        for frame in TouchSessionReplayer.replay(session: session) {
            recognizer.processClassifiedFrame(
                frame, timestamp: frame.timestamp, modifierFlags: [])
        }

        XCTAssertFalse(
            delegate.didStartCalled,
            "One moving finger plus a resting thumb (real recording) must never start MiddleDrag")
    }

    func testReplayedSessionDrivesRecognizerWithoutFalseStart() throws {
        let session = scrollWithThumbSession()

        let recognizer = GestureRecognizer()
        let delegate = MockGestureRecognizerDelegate()
        recognizer.delegate = delegate

        for frame in TouchSessionReplayer.replay(session: session) {
            recognizer.processClassifiedFrame(
                frame, timestamp: frame.timestamp, modifierFlags: [])
        }

        XCTAssertFalse(
            delegate.didStartCalled,
            "Two scrolling fingers plus a resting thumb must not start MiddleDrag on replay")
    }
}
