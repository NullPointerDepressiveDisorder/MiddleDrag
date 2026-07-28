import Foundation

// MARK: - Debug Frame

/// One classified touch frame enriched with the recognizer/event state that was
/// current when it was processed. This is what the debug window displays and
/// what recording sessions capture.
struct TouchDebugFrame: Sendable, Codable {
    let timestamp: Double
    let classified: ClassifiedTouchFrame
    let recognizerState: String
    let isDragging: Bool
    let isPassThrough: Bool
}

// MARK: - Recording Session

/// Scenario labels for guided capture, mirroring the calibration plan.
enum TouchDebugScenario: String, CaseIterable, Sendable, Codable {
    case oneFinger = "One finger"
    case oneFingerWithIncidental = "One finger with incidental contact"
    case twoFingerScroll = "Two-finger scroll"
    case twoFingerScrollWithIncidental = "Two-finger scroll with incidental contact"
    case threeFingerMiddleDrag = "Three-finger MiddleDrag"
    case threeFingerMiddleDragWithIncidental = "Three-finger MiddleDrag with incidental contact"
    case fourFingerSystemGesture = "Four-finger system gesture"
    case palmRest = "Palm/hand rest"
    case clickWithIncidental = "Normal click with incidental contact"
    case unlabeled = "Unlabeled"
}

struct TouchDebugRecordedFrame: Sendable, Codable {
    /// Wall-clock time (`Date().timeIntervalSince1970`) so sessions can be
    /// correlated with external notes; `frame.timestamp` stays in the
    /// multitouch framework's own clock.
    let wallClock: Double
    let frame: TouchDebugFrame
}

struct TouchDebugSession: Sendable, Codable {
    var scenario: String
    var startedAt: Double
    var endedAt: Double
    var appVersion: String
    var frames: [TouchDebugRecordedFrame]

    var isEmpty: Bool { frames.isEmpty }
}

// MARK: - Export

extension TouchDebugSession {
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func fromJSONData(_ data: Data) throws -> TouchDebugSession {
        try JSONDecoder().decode(TouchDebugSession.self, from: data)
    }

    static let csvHeader = [
        "wallClock", "timestamp", "frame", "pathIndex", "fingerID", "handID", "state",
        "x", "y", "vx", "vy",
        "zTotal", "zDensity", "angle", "majorAxis", "minorAxis",
        "role", "confidence",
        "sizeScore", "shapeScore", "stationaryScore", "clusterScore",
        "speed", "aspectRatio", "age", "stationaryDuration", "totalMovement",
        "movementCorrelation", "distanceToCluster", "clusterSpeed",
        "recognizerState", "isDragging", "isPassThrough", "scenario",
    ].joined(separator: ",")

    /// One row per classified touch per frame, for analysis in external tools.
    func csvData() -> Data {
        var lines = [Self.csvHeader]

        for recorded in frames {
            let frame = recorded.frame
            for touch in frame.classified.classifiedTouches {
                let sample = touch.sample
                let features = touch.features
                let breakdown = touch.scoreBreakdown
                let fields: [String] = [
                    String(recorded.wallClock),
                    String(sample.timestamp),
                    String(sample.frame),
                    String(sample.pathIndex),
                    String(sample.fingerID),
                    String(sample.handID),
                    String(sample.state),
                    String(sample.position.x),
                    String(sample.position.y),
                    String(sample.velocity.x),
                    String(sample.velocity.y),
                    String(sample.zTotal),
                    String(sample.zDensity),
                    String(sample.angle),
                    String(sample.majorAxis),
                    String(sample.minorAxis),
                    touch.role.rawValue,
                    String(touch.confidence),
                    String(breakdown.sizeScore),
                    String(breakdown.shapeScore),
                    String(breakdown.stationaryScore),
                    String(breakdown.clusterScore),
                    String(features.speed),
                    String(features.aspectRatio),
                    String(features.age),
                    String(features.stationaryDuration),
                    String(features.totalMovement),
                    String(features.movementCorrelationWithCluster),
                    String(features.distanceToDigitCluster),
                    String(features.clusterSpeed),
                    frame.recognizerState,
                    String(frame.isDragging),
                    String(frame.isPassThrough),
                    csvEscaped(scenario),
                ]
                lines.append(fields.joined(separator: ","))
            }
        }

        return Data(lines.joined(separator: "\n").utf8)
    }

    private func csvEscaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
