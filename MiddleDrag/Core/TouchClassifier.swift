import Foundation

struct TouchSample: Sendable, Codable {
    let frame: Int32
    let timestamp: Double
    let pathIndex: Int32
    let state: UInt32
    let fingerID: Int32
    let handID: Int32
    let position: MTPoint
    let velocity: MTPoint
    let zTotal: Float
    let zDensity: Float
    let angle: Float
    let majorAxis: Float
    let minorAxis: Float

    var isActive: Bool {
        state == TouchState.touching.rawValue || state == TouchState.active.rawValue
    }

    init(touch: MTTouch) {
        self.frame = touch.frame
        self.timestamp = touch.timestamp
        self.pathIndex = touch.pathIndex
        self.state = touch.state
        self.fingerID = touch.fingerID
        self.handID = touch.handID
        self.position = touch.normalizedVector.position
        self.velocity = touch.normalizedVector.velocity
        self.zTotal = touch.zTotal
        self.zDensity = touch.zDensity
        self.angle = touch.angle
        self.majorAxis = touch.majorAxis
        self.minorAxis = touch.minorAxis
    }
}

struct TouchFeatures: Sendable, Codable {
    let speed: Float
    let contactAreaEstimate: Float
    let aspectRatio: Float
    let age: Double
    let stationaryDuration: Double
    let totalMovement: Float
    let movementCorrelationWithCluster: Float
    let distanceToDigitCluster: Float
    let clusterSpeed: Float
}

enum TouchRole: String, Sendable, Codable {
    case digit
    case probableThumb
    case probablePalm
    case ignored
    case uncertain
}

struct TouchScoreBreakdown: Sendable, Codable {
    let sizeScore: Float
    let shapeScore: Float
    let stationaryScore: Float
    let clusterScore: Float
    let confidence: Float
    let reasons: [String]
}

struct ClassifiedTouch: Sendable, Codable {
    let sample: TouchSample
    let features: TouchFeatures
    let role: TouchRole
    let confidence: Float
    let scoreBreakdown: TouchScoreBreakdown

    var countsAsDigit: Bool {
        role == .digit || role == .uncertain
    }
}

struct ClassifiedTouchFrame: Sendable, Codable {
    let timestamp: Double
    let rawTouches: [TouchSample]
    let classifiedTouches: [ClassifiedTouch]

    var digitTouches: [ClassifiedTouch] {
        classifiedTouches.filter(\.countsAsDigit)
    }

    var incidentalTouches: [ClassifiedTouch] {
        classifiedTouches.filter { !$0.countsAsDigit }
    }

    var uncertainTouches: [ClassifiedTouch] {
        classifiedTouches.filter { $0.role == .uncertain }
    }

    var rawCount: Int {
        rawTouches.count
    }

    var digitCount: Int {
        digitTouches.count
    }

    var incidentalCount: Int {
        incidentalTouches.count
    }
}

final class TouchClassifier {
    private struct TouchHistory {
        var firstSeen: Double
        var lastSeen: Double
        var lastPosition: MTPoint
        var stationarySince: Double
        var totalMovement: Float
        var lockedRole: TouchRole?
    }

    // Non-calibrated constants; the user/device-specific thresholds live in
    // `calibration`. Velocity thresholds are in device units/sec, measured from
    // real trackpad recordings: resting contacts jitter around 0.02 (p90 ≈ 0.1),
    // actively moving digits around 0.4.
    private enum Tuning {
        static let digitLikeConfidence: Float = 0.35
        /// Per-frame position jump this large means a new or reused touch path.
        static let positionJumpEpsilon: Float = 0.008
        static let movementDeadband: Float = 0.003
        static let neverMovedLimit: Float = 0.03
        /// Contact counts as still below onset, definitely moving above onset+span.
        static let movingSpeedOnset: Float = 0.1
        static let movingSpeedSpan: Float = 0.15
        /// Speed that resets the stationary clock in touch history.
        static let stationaryResetSpeed: Float = 0.3
        /// sizeScore above which a contact anchors the palm-satellite rule.
        static let heelSizeScoreOnset: Float = 0.8
    }

    /// Thresholds driving the score curves. Callers that share a classifier
    /// across threads must guard mutation with their own lock (MultitouchManager
    /// already wraps all access in `touchClassifierLock`).
    var calibration: TouchClassifierCalibration = .default

    private var histories: [Int32: TouchHistory] = [:]

    func reset() {
        histories.removeAll()
    }

    func classify(
        touches: UnsafeMutableRawPointer,
        count: Int,
        timestamp: Double,
        configuration: GestureConfiguration
    ) -> ClassifiedTouchFrame {
        var samples: [TouchSample] = []
        if count > 0 {
            let touchArray = unsafe touches.bindMemory(to: MTTouch.self, capacity: count)
            for i in 0..<count {
                unsafe samples.append(TouchSample(touch: touchArray[i]))
            }
        }
        return classify(samples: samples, timestamp: timestamp, configuration: configuration)
    }

    /// Sample-based entry point; also used to replay recorded sessions.
    func classify(
        samples rawSamples: [TouchSample],
        timestamp: Double,
        configuration: GestureConfiguration
    ) -> ClassifiedTouchFrame {
        let samples = rawSamples.filter { sample in
            sample.isActive && passesLegacyFilters(sample, configuration: configuration)
        }

        guard !samples.isEmpty else {
            pruneHistories(activeIDs: [])
            return ClassifiedTouchFrame(timestamp: timestamp, rawTouches: [], classifiedTouches: [])
        }

        updateHistories(samples: samples, timestamp: timestamp)

        let classified = classify(
            samples: samples,
            timestamp: timestamp,
            filteringEnabled: configuration.incidentalFilterEnabled
        )
        pruneHistories(activeIDs: Set(samples.map(\.fingerID)))

        return ClassifiedTouchFrame(
            timestamp: timestamp,
            rawTouches: samples,
            classifiedTouches: classified
        )
    }

    private func passesLegacyFilters(
        _ sample: TouchSample,
        configuration: GestureConfiguration
    ) -> Bool {
        if configuration.exclusionZoneEnabled,
           sample.position.y < configuration.exclusionZoneSize {
            return false
        }

        if configuration.contactSizeFilterEnabled,
           sample.zTotal > configuration.maxContactSize {
            return false
        }

        return true
    }

    private func updateHistories(samples: [TouchSample], timestamp: Double) {
        for sample in samples {
            let id = sample.fingerID
            if var history = histories[id] {
                let movement = sample.position.distance(to: history.lastPosition)
                let speed = hypot(sample.velocity.x, sample.velocity.y)
                // Per-frame position deltas are tiny at 120Hz even when dragging,
                // so genuine motion is detected from the device-reported velocity;
                // the position jump only catches new/reused touch paths.
                if movement > Tuning.positionJumpEpsilon || speed > Tuning.stationaryResetSpeed {
                    history.stationarySince = timestamp
                }
                // Deadband keeps sensor jitter from accumulating into apparent travel.
                if movement > Tuning.movementDeadband {
                    history.totalMovement += movement
                }
                history.lastSeen = timestamp
                history.lastPosition = sample.position
                histories[id] = history
            } else {
                histories[id] = TouchHistory(
                    firstSeen: timestamp,
                    lastSeen: timestamp,
                    lastPosition: sample.position,
                    stationarySince: timestamp,
                    totalMovement: 0,
                    lockedRole: nil
                )
            }
        }
    }

    private func pruneHistories(activeIDs: Set<Int32>) {
        histories = histories.filter { activeIDs.contains($0.key) }
    }

    private func classify(
        samples: [TouchSample], timestamp: Double, filteringEnabled: Bool
    ) -> [ClassifiedTouch] {
        guard !samples.isEmpty else { return [] }

        let baseScores = samples.map { sample in
            let features = featuresFor(sample, in: samples, timestamp: timestamp)
            return (sample, features, score(sample: sample, features: features))
        }

        // Palm-satellite pass: a resting palm fragments into several contacts, and
        // in real recordings a heel-sized contact is present in every multi-contact
        // palm frame. When such a heel exists, every stationary companion contact
        // is a resting-hand fragment regardless of its own size — some fragments
        // are fingertip-sized. Moving contacts are never demoted.
        let scoredSamples = baseScores.map { sample, features, breakdown in
            (
                sample, features,
                satelliteAdjusted(
                    breakdown, sample: sample, features: features, among: baseScores)
            )
        }

        // Filtering disabled: report honest scores (for the debug window) but
        // count every contact as a digit and never lock roles.
        guard filteringEnabled else {
            return scoredSamples.map { sample, features, breakdown in
                ClassifiedTouch(
                    sample: sample, features: features, role: .digit,
                    confidence: breakdown.confidence, scoreBreakdown: breakdown)
            }
        }

        let strongCount = scoredSamples.filter {
            $0.2.confidence >= calibration.extraContactIgnoreConfidence
        }.count
        let digitLikeCount = scoredSamples.filter { $0.2.confidence < Tuning.digitLikeConfidence }.count
        // Discount incidental candidates only when every contact is accounted for:
        // at least one stands out and all the others look digit-like. Ambiguous
        // middle-band contacts keep everything counted (conservative). A frame of
        // uniformly strong contacts (full palm rest) is ignored entirely; a frame
        // of uniformly digit-like contacts (real 4-finger gesture) is kept entirely.
        let shouldIgnoreIncidentalCandidates =
            strongCount >= 1 && digitLikeCount == samples.count - strongCount

        return scoredSamples.map { sample, features, breakdown in
            ClassifiedTouch(
                sample: sample,
                features: features,
                role: roleFor(
                    sample: sample,
                    breakdown: breakdown,
                    shouldIgnore: shouldIgnoreIncidentalCandidates
                ),
                confidence: breakdown.confidence,
                scoreBreakdown: breakdown
            )
        }
    }

    /// Raises a contact's stationary score when a palm-heel-sized companion
    /// contact is present and this contact is not moving.
    private func satelliteAdjusted(
        _ breakdown: TouchScoreBreakdown,
        sample: TouchSample,
        features: TouchFeatures,
        among scored: [(TouchSample, TouchFeatures, TouchScoreBreakdown)]
    ) -> TouchScoreBreakdown {
        let maxCompanionSize = scored
            .filter { $0.0.fingerID != sample.fingerID }
            .map(\.2.sizeScore)
            .max() ?? 0
        let heelGate = clamp((maxCompanionSize - Tuning.heelSizeScoreOnset) / 0.1)
        let satelliteScore = heelGate * stillness(of: features.speed)

        guard satelliteScore > breakdown.stationaryScore else { return breakdown }

        let stationaryScore = satelliteScore
        let motionEvidence = stationaryScore * 0.7 + breakdown.clusterScore * 0.3
        let sizeEvidence = breakdown.sizeScore * 0.75 + breakdown.shapeScore * 0.25

        return TouchScoreBreakdown(
            sizeScore: breakdown.sizeScore,
            shapeScore: breakdown.shapeScore,
            stationaryScore: stationaryScore,
            clusterScore: breakdown.clusterScore,
            confidence: clamp(max(sizeEvidence, motionEvidence)),
            reasons: breakdown.reasons + ["resting while palm contact present"]
        )
    }

    /// 1 when the contact is clearly still, 0 when clearly moving (device units/sec).
    private func stillness(of speed: Float) -> Float {
        clamp(((Tuning.movingSpeedOnset + Tuning.movingSpeedSpan) - speed) / Tuning.movingSpeedSpan)
    }

    private func roleFor(
        sample: TouchSample,
        breakdown: TouchScoreBreakdown,
        shouldIgnore: Bool
    ) -> TouchRole {
        // Sticky roles: once a contact is ignored it stays ignored for its lifetime,
        // so the digit count cannot flap when the moving fingers pause mid-gesture.
        if let locked = histories[sample.fingerID]?.lockedRole {
            return locked
        }

        if shouldIgnore, breakdown.confidence >= calibration.extraContactIgnoreConfidence {
            let role: TouchRole =
                breakdown.sizeScore >= calibration.palmLikeSizeScoreThreshold
                ? .probablePalm : .probableThumb
            histories[sample.fingerID]?.lockedRole = role
            return role
        }

        if breakdown.confidence >= calibration.uncertainContactPassThroughConfidence {
            // Still counts as a digit (conservative), but marked ambiguous — the
            // recognizer forgives uncertain extras during an active drag, and the
            // debug UI shows them yellow. Assigned regardless of gating so a
            // thumb landing mid-gesture is flagged immediately.
            return .uncertain
        }

        return .digit
    }

    /// The reference digit cluster for a candidate contact: the other contacts,
    /// limited to the three smallest so a large palm cannot drag the centroid.
    /// Excluding the candidate itself keeps a resting thumb from diluting the very
    /// cluster it is being compared against.
    private func clusterExcluding(
        _ sample: TouchSample, from samples: [TouchSample]
    ) -> [TouchSample] {
        let others = samples.filter { $0.fingerID != sample.fingerID }
        guard others.count > 3 else { return others }
        return others
            .sorted { contactMagnitude($0) < contactMagnitude($1) }
            .prefix(3)
            .map { $0 }
    }

    private func featuresFor(
        _ sample: TouchSample,
        in samples: [TouchSample],
        timestamp: Double
    ) -> TouchFeatures {
        let speed = hypot(sample.velocity.x, sample.velocity.y)
        let major = max(sample.majorAxis, 0)
        let minor = max(sample.minorAxis, 0)
        let area = major * minor
        let aspectRatio = minor > 0.0001 ? major / minor : 1
        let history = histories[sample.fingerID]
        let age = timestamp - (history?.firstSeen ?? timestamp)
        let stationaryDuration = timestamp - (history?.stationarySince ?? timestamp)
        let totalMovement = history?.totalMovement ?? 0

        let cluster = clusterExcluding(sample, from: samples)
        let clusterCentroid = centroid(of: cluster.map(\.position))
        let distanceToCluster =
            cluster.isEmpty ? 0 : sample.position.distance(to: clusterCentroid)
        let clusterVelocity = centroid(of: cluster.map(\.velocity))
        let clusterSpeed = hypot(clusterVelocity.x, clusterVelocity.y)
        let movementCorrelation = velocityCorrelation(sample.velocity, clusterVelocity)

        return TouchFeatures(
            speed: speed,
            contactAreaEstimate: area,
            aspectRatio: aspectRatio,
            age: age,
            stationaryDuration: stationaryDuration,
            totalMovement: totalMovement,
            movementCorrelationWithCluster: movementCorrelation,
            distanceToDigitCluster: distanceToCluster,
            clusterSpeed: clusterSpeed
        )
    }

    private func score(sample: TouchSample, features: TouchFeatures) -> TouchScoreBreakdown {
        var reasons: [String] = []

        let sizeMagnitude = contactMagnitude(sample)
        let sizeOnset = calibration.maxTypicalDigitMajorAxis * 1.2
        let sizeSpan = calibration.maxTypicalDigitMajorAxis * 1.1
        let sizeScore = clamp((sizeMagnitude - sizeOnset) / sizeSpan)
        if sizeScore > 0.5 {
            reasons.append("large contact")
        }

        let shapeScore = clamp(
            (features.aspectRatio - calibration.thumbLikeShapeScoreThreshold) / 1.2)
        if shapeScore > 0.5 {
            reasons.append("elongated contact")
        }

        // Differential motion: a contact that has never traveled while the other
        // digits are moving. A digit that pauses mid-gesture has prior travel and
        // therefore keeps a zero stationary score.
        let neverMovedGate = clamp((Tuning.neverMovedLimit - features.totalMovement) / 0.02)
        let clusterMoving = clamp(
            (features.clusterSpeed - Tuning.movingSpeedOnset) / Tuning.movingSpeedSpan)
        let candidateStill = stillness(of: features.speed)
        let sustainedOnset = Float(calibration.minIncidentalStationaryDuration)
        let sustained = clamp(
            (Float(features.stationaryDuration) - sustainedOnset) / (2 * sustainedOnset))
        let stationaryScore = neverMovedGate * clusterMoving * candidateStill * sustained
        if stationaryScore > 0.5 {
            reasons.append("stationary while digits move")
        }

        // Cluster relationship: geometric separation, or moving against the cluster.
        // Anti-correlation only counts when both the candidate and the cluster are
        // actually moving; zero velocity is not evidence of anything.
        let separationScore = clamp(
            (features.distanceToDigitCluster - calibration.incidentalClusterDistanceMin) / 0.25)
        let candidateMoving = clamp(
            (features.speed - Tuning.movingSpeedOnset) / Tuning.movingSpeedSpan)
        let bothMoving = min(candidateMoving, clusterMoving)
        let correlationMax = calibration.incidentalMovementCorrelationMax
        let antiCorrelationScore =
            bothMoving
            * clamp((correlationMax - features.movementCorrelationWithCluster) / correlationMax)
        let clusterScore = max(separationScore, antiCorrelationScore)
        if clusterScore > 0.5 {
            reasons.append("not moving with digit cluster")
        }

        // Two independent evidence paths: a contact is incidental because it looks
        // wrong (size/shape) or because it behaves wrong (still while digits move).
        // Either alone can cross the ignore threshold; a weighted sum of all four
        // could not, which is why a normal-sized resting thumb was never ignored.
        // A contact moving AGAINST the cluster (a thumb sliding into click position
        // while the digits drag) additionally floors into the uncertain band —
        // never high enough to ignore outright, but enough to flag ambiguity. The
        // floor is gated on partial size/shape evidence: thumbs have it, while
        // fingertip-sized palm fragments with chaotic landing velocities do not,
        // and must stay digit-like so the gating can discount the palm heel.
        let sizeEvidence = sizeScore * 0.75 + shapeScore * 0.25
        let motionEvidence = stationaryScore * 0.7 + clusterScore * 0.3
        let thumbSizePrior = clamp(sizeEvidence / 0.3)
        let confidence = max(
            sizeEvidence, motionEvidence, antiCorrelationScore * 0.45 * thumbSizePrior)

        return TouchScoreBreakdown(
            sizeScore: sizeScore,
            shapeScore: shapeScore,
            stationaryScore: stationaryScore,
            clusterScore: clusterScore,
            confidence: clamp(confidence),
            reasons: reasons
        )
    }

    private func contactMagnitude(_ sample: TouchSample) -> Float {
        // Normalize the minor axis and pressure onto the major-axis scale: a
        // contact at the typical digit maximum on any dimension registers like a
        // typically-sized digit contact. Palm fragments are often wide (large
        // minor axis) even when their major axis looks finger-like.
        let minorMagnitude =
            sample.minorAxis / calibration.maxTypicalDigitMinorAxis
            * calibration.maxTypicalDigitMajorAxis
        let pressureMagnitude =
            sample.zTotal / calibration.maxTypicalDigitZTotal
            * calibration.maxTypicalDigitMajorAxis
        return max(sample.majorAxis, minorMagnitude, pressureMagnitude)
    }

    private func centroid(of points: [MTPoint]) -> MTPoint {
        guard !points.isEmpty else { return MTPoint(x: 0, y: 0) }
        let total = points.reduce(MTPoint(x: 0, y: 0)) { partial, point in
            MTPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return MTPoint(x: total.x / Float(points.count), y: total.y / Float(points.count))
    }

    private func velocityCorrelation(_ a: MTPoint, _ b: MTPoint) -> Float {
        let aMagnitude = hypot(a.x, a.y)
        let bMagnitude = hypot(b.x, b.y)
        guard aMagnitude > 0.0001, bMagnitude > 0.0001 else { return 0 }

        let dot = a.x * b.x + a.y * b.y
        return clamp(dot / (aMagnitude * bMagnitude))
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
