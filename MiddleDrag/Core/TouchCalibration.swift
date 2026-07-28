import Foundation

// MARK: - Calibration Values

/// Per-user/per-device thresholds for touch classification. The size defaults
/// come from readings on a real MacBook trackpad: fingertip zTotal ≈ 1 with
/// axes ≈ 10/10, resting thumb zTotal ≈ 2 with axes ≈ 20/10, palm zTotal > 5.
/// The calibration wizard replaces them with per-user values.
struct TouchClassifierCalibration: Codable, Sendable, Equatable {
    var maxTypicalDigitMajorAxis: Float
    var maxTypicalDigitMinorAxis: Float
    var maxTypicalDigitZTotal: Float
    var minIncidentalStationaryDuration: Double
    var incidentalMovementCorrelationMax: Float
    var incidentalClusterDistanceMin: Float
    var thumbLikeShapeScoreThreshold: Float
    var palmLikeSizeScoreThreshold: Float
    var extraContactIgnoreConfidence: Float
    var uncertainContactPassThroughConfidence: Float

    static let `default` = TouchClassifierCalibration(
        maxTypicalDigitMajorAxis: 11.0,
        maxTypicalDigitMinorAxis: 10.0,
        // Fingertips reach z≈2.5 when physically clicking; palms exceed 5.
        maxTypicalDigitZTotal: 2.5,
        minIncidentalStationaryDuration: 0.1,
        incidentalMovementCorrelationMax: 0.35,
        incidentalClusterDistanceMin: 0.28,
        thumbLikeShapeScoreThreshold: 1.5,
        palmLikeSizeScoreThreshold: 0.92,
        extraContactIgnoreConfidence: 0.65,
        // Real-hardware separation is stark: fingertip size evidence is 0.000
        // at p95 while thumbs measure 0.26+ (p5), so 0.2 flags essentially every
        // thumb frame as uncertain with no fingertip false positives.
        uncertainContactPassThroughConfidence: 0.2
    )
}

// MARK: - Wizard Steps

/// One guided step of the calibration flow (plan section 7). The wizard never
/// tells the user where to put the incidental contact — it asks for a natural
/// hand posture and infers patterns from the recorded data.
struct CalibrationStep: Sendable {
    let scenario: TouchDebugScenario
    let instruction: String
    let expectedDigits: Int
    let expectsIncidental: Bool
    let expectsMotion: Bool
    let duration: TimeInterval

    static let wizardSequence: [CalibrationStep] = [
        CalibrationStep(
            scenario: .palmRest,
            instruction:
                "Place your hand naturally on the trackpad without intending a gesture. Hold still.",
            expectedDigits: 0, expectsIncidental: true, expectsMotion: false, duration: 4),
        CalibrationStep(
            scenario: .oneFingerWithIncidental,
            instruction:
                "Move one finger around while resting your hand naturally on the trackpad.",
            expectedDigits: 1, expectsIncidental: true, expectsMotion: true, duration: 5),
        CalibrationStep(
            scenario: .clickWithIncidental,
            instruction:
                "Click normally with one finger while resting your hand naturally on the trackpad.",
            expectedDigits: 1, expectsIncidental: true, expectsMotion: false, duration: 4),
        CalibrationStep(
            scenario: .twoFingerScroll,
            instruction: "Scroll up and down with two fingers, hand lifted off the trackpad.",
            expectedDigits: 2, expectsIncidental: false, expectsMotion: true, duration: 5),
        CalibrationStep(
            scenario: .twoFingerScrollWithIncidental,
            instruction:
                "Scroll with two fingers while resting your hand naturally on the trackpad.",
            expectedDigits: 2, expectsIncidental: true, expectsMotion: true, duration: 5),
        CalibrationStep(
            scenario: .threeFingerMiddleDrag,
            instruction: "Perform the three-finger MiddleDrag gesture without any extra contact.",
            expectedDigits: 3, expectsIncidental: false, expectsMotion: true, duration: 5),
        CalibrationStep(
            scenario: .threeFingerMiddleDragWithIncidental,
            instruction:
                "Perform the three-finger MiddleDrag gesture while resting your hand naturally.",
            expectedDigits: 3, expectsIncidental: true, expectsMotion: true, duration: 5),
        CalibrationStep(
            scenario: .fourFingerSystemGesture,
            instruction: "Perform a four-finger swipe (e.g. Mission Control gesture).",
            expectedDigits: 4, expectsIncidental: false, expectsMotion: true, duration: 4),
    ]
}

// MARK: - Step Validation

/// Live validation of a recorded calibration step (plan section 8): checks the
/// sample actually contains what the instruction asked for before accepting it.
enum CalibrationValidator {

    struct Verdict: Sendable {
        let accepted: Bool
        let message: String
    }

    /// Speed above which a contact counts as moving. Measured from real
    /// recordings: resting-contact jitter reaches ~0.1, moving digits ~0.4.
    private static let movingSpeed: Float = 0.25

    static func validate(frames: [TouchDebugFrame], step: CalibrationStep) -> Verdict {
        let touchedFrames = frames.filter { $0.classified.rawCount > 0 }
        guard touchedFrames.count >= 10 else {
            return Verdict(accepted: false, message: "Not enough touch data — try again.")
        }

        let expectedRaw = step.expectedDigits + (step.expectsIncidental ? 1 : 0)
        let rawCounts = touchedFrames.map(\.classified.rawCount).sorted()
        let medianRaw = rawCounts[rawCounts.count / 2]

        if step.expectsIncidental {
            guard medianRaw > step.expectedDigits else {
                return Verdict(
                    accepted: false,
                    message:
                        "No extra contact detected — rest your hand on the trackpad while doing this."
                )
            }
        } else {
            guard medianRaw == expectedRaw else {
                return Verdict(
                    accepted: false,
                    message:
                        "Expected \(expectedRaw) contact(s) but mostly saw \(medianRaw) — try again."
                )
            }
        }

        if step.expectsMotion {
            let movingFraction = fractionOfFrames(touchedFrames) { frame in
                let movingCount = frame.classified.rawTouches.filter {
                    hypot($0.velocity.x, $0.velocity.y) > movingSpeed
                }.count
                return movingCount >= min(step.expectedDigits, 1)
            }
            guard movingFraction > 0.3 else {
                return Verdict(
                    accepted: false, message: "No movement detected — keep the gesture moving.")
            }
        }

        // A real four-finger gesture must never lose a moving contact to the
        // incidental classification (plan section 8).
        if step.scenario == .fourFingerSystemGesture {
            let misclassified = touchedFrames.contains { frame in
                frame.classified.incidentalTouches.contains {
                    hypot($0.sample.velocity.x, $0.sample.velocity.y) > movingSpeed
                }
            }
            guard !misclassified else {
                return Verdict(
                    accepted: false,
                    message:
                        "A moving contact was misclassified as incidental — calibration cannot proceed from this sample."
                )
            }
        }

        return Verdict(accepted: true, message: "Sample accepted.")
    }

    private static func fractionOfFrames(
        _ frames: [TouchDebugFrame], where predicate: (TouchDebugFrame) -> Bool
    ) -> Double {
        guard !frames.isEmpty else { return 0 }
        return Double(frames.filter(predicate).count) / Double(frames.count)
    }
}

// MARK: - Threshold Derivation

/// Derives calibration thresholds from labeled recording sessions. Fields with
/// too little supporting data keep their defaults, so a partial calibration can
/// never be worse than no calibration.
enum CalibrationDerivation {

    struct Summary: Sendable {
        var digitSampleCount = 0
        var incidentalSampleCount = 0
        var derived: TouchClassifierCalibration = .default
    }

    private static let minDigitSamples = 30
    private static let minIncidentalSamples = 15

    static func derive(from sessions: [TouchDebugSession]) -> Summary {
        var summary = Summary()
        var calibration = TouchClassifierCalibration.default

        var digitTouches: [ClassifiedTouch] = []
        var incidentalCandidates: [ClassifiedTouch] = []

        for session in sessions {
            guard let step = stepFor(session: session) else { continue }
            for recorded in session.frames {
                let touches = recorded.frame.classified.classifiedTouches
                if step.expectsIncidental {
                    // Ground truth is the instruction, not the classifier: the extra
                    // contacts beyond the intended digit count are the slowest ones.
                    guard touches.count > step.expectedDigits else { continue }
                    let bySpeed = touches.sorted { $0.features.speed < $1.features.speed }
                    let extraCount = touches.count - step.expectedDigits
                    incidentalCandidates.append(contentsOf: bySpeed.prefix(extraCount))
                    digitTouches.append(contentsOf: bySpeed.dropFirst(extraCount))
                } else if touches.count == step.expectedDigits {
                    digitTouches.append(contentsOf: touches)
                }
            }
        }

        summary.digitSampleCount = digitTouches.count
        summary.incidentalSampleCount = incidentalCandidates.count

        if digitTouches.count >= minDigitSamples {
            calibration.maxTypicalDigitMajorAxis = clampValue(
                percentile(digitTouches.map(\.sample.majorAxis), 0.95), min: 2.0, max: 40.0)
            calibration.maxTypicalDigitMinorAxis = clampValue(
                percentile(digitTouches.map(\.sample.minorAxis), 0.95), min: 1.5, max: 30.0)
            calibration.maxTypicalDigitZTotal = clampValue(
                percentile(digitTouches.map(\.sample.zTotal), 0.95), min: 0.3, max: 8.0)
        }

        if incidentalCandidates.count >= minIncidentalSamples {
            calibration.minIncidentalStationaryDuration = Double(
                clampValue(
                    percentile(
                        incidentalCandidates.map { Float($0.features.stationaryDuration) }, 0.25),
                    min: 0.05, max: 0.4))
            calibration.incidentalMovementCorrelationMax = clampValue(
                percentile(
                    incidentalCandidates.map(\.features.movementCorrelationWithCluster), 0.75),
                min: 0.2, max: 0.7)
            calibration.incidentalClusterDistanceMin = clampValue(
                percentile(incidentalCandidates.map(\.features.distanceToDigitCluster), 0.25),
                min: 0.1, max: 0.5)
            calibration.thumbLikeShapeScoreThreshold = clampValue(
                percentile(incidentalCandidates.map(\.features.aspectRatio), 0.25),
                min: 1.3, max: 2.5)
        }

        // Separate the confidence threshold only when both distributions exist:
        // midway between what clean digits score and what incidental contacts score.
        if digitTouches.count >= minDigitSamples,
            incidentalCandidates.count >= minIncidentalSamples
        {
            let digitHigh = percentile(digitTouches.map(\.confidence), 0.95)
            let incidentalLow = percentile(incidentalCandidates.map(\.confidence), 0.25)
            if incidentalLow > digitHigh {
                calibration.extraContactIgnoreConfidence = clampValue(
                    (digitHigh + incidentalLow) / 2, min: 0.5, max: 0.85)
                calibration.uncertainContactPassThroughConfidence = clampValue(
                    calibration.extraContactIgnoreConfidence - 0.45, min: 0.15, max: 0.4)
            }
        }

        summary.derived = calibration
        return summary
    }

    private static func stepFor(session: TouchDebugSession) -> CalibrationStep? {
        CalibrationStep.wizardSequence.first { $0.scenario.rawValue == session.scenario }
    }

    static func percentile(_ values: [Float], _ fraction: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = fraction * Float(sorted.count - 1)
        let lower = Int(position)
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let weight = position - Float(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    private static func clampValue(_ value: Float, min: Float, max: Float) -> Float {
        Swift.min(Swift.max(value, min), max)
    }
}

// MARK: - Persistence

/// Saves the derived calibration as JSON in Application Support.
final class TouchCalibrationStore: @unchecked Sendable {

    static let shared = TouchCalibrationStore()

    private let fileURL: URL

    /// Production store in `~/Library/Application Support/MiddleDrag/`.
    private convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        self.init(directory: base.appendingPathComponent("MiddleDrag", isDirectory: true))
    }

    /// Injectable directory for tests.
    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("touch-calibration.json")
    }

    func load() -> TouchClassifierCalibration? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(TouchClassifierCalibration.self, from: data)
    }

    func save(_ calibration: TouchClassifierCalibration) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(calibration).write(to: fileURL)
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Session Replay

/// Replays a recorded session's raw touches through a fresh classifier, for
/// regression tests against captured fixtures (plan step 10) and for evaluating
/// candidate calibrations against existing recordings.
enum TouchSessionReplayer {

    static func replay(
        session: TouchDebugSession,
        configuration: GestureConfiguration = GestureConfiguration(),
        calibration: TouchClassifierCalibration = .default
    ) -> [ClassifiedTouchFrame] {
        let classifier = TouchClassifier()
        classifier.calibration = calibration

        return session.frames.map { recorded in
            classifier.classify(
                samples: recorded.frame.classified.rawTouches,
                timestamp: recorded.frame.timestamp,
                configuration: configuration
            )
        }
    }
}
