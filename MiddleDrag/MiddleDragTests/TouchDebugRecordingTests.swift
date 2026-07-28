import QuartzCore
import XCTest

@testable import MiddleDragCore

final class TouchDebugRecordingTests: XCTestCase {

    // MARK: - Helpers

    private func createTouch(
        x: Float,
        y: Float,
        zTotal: Float = 0.5,
        fingerID: Int32 = 1,
        pathIndex: Int32 = 1,
        velocity: MTPoint = MTPoint(x: 0, y: 0),
        majorAxis: Float = 0.1,
        minorAxis: Float = 0.1
    ) -> MTTouch {
        let position = MTPoint(x: x, y: y)
        let vector = MTVector(position: position, velocity: velocity)

        return MTTouch(
            frame: 7,
            timestamp: 1.25,
            pathIndex: pathIndex,
            state: 4,
            fingerID: fingerID,
            handID: 0,
            normalizedVector: vector,
            zTotal: zTotal,
            field9: 0,
            angle: 0.4,
            majorAxis: majorAxis,
            minorAxis: minorAxis,
            absoluteVector: vector,
            field14: 0,
            field15: 0,
            zDensity: 0.3
        )
    }

    private func makeDebugFrame() -> TouchDebugFrame {
        let classifier = TouchClassifier()
        var touches = [
            createTouch(
                x: 0.35, y: 0.58, fingerID: 1, pathIndex: 1, velocity: MTPoint(x: 0, y: 0.5)),
            createTouch(
                x: 0.55, y: 0.60, fingerID: 2, pathIndex: 2, velocity: MTPoint(x: 0, y: 0.5)),
            createTouch(
                x: 0.82, y: 0.52, zTotal: 5.0, fingerID: 99, pathIndex: 99,
                majorAxis: 25, minorAxis: 15),
        ]

        let classified = unsafe touches.withUnsafeMutableBytes { buffer -> ClassifiedTouchFrame in
            let pointer = buffer.baseAddress!
            return unsafe classifier.classify(
                touches: pointer, count: 3, timestamp: 1.25,
                configuration: GestureConfiguration())
        }

        return TouchDebugFrame(
            timestamp: 1.25,
            classified: classified,
            recognizerState: "idle",
            isDragging: false,
            isPassThrough: false
        )
    }

    private func makeSession() -> TouchDebugSession {
        TouchDebugSession(
            scenario: TouchDebugScenario.twoFingerScrollWithIncidental.rawValue,
            startedAt: 100,
            endedAt: 101,
            appVersion: "test",
            frames: [TouchDebugRecordedFrame(wallClock: 100.5, frame: makeDebugFrame())]
        )
    }

    // MARK: - JSON Round-Trip

    func testSessionJSONRoundTrip() throws {
        let session = makeSession()

        let data = try session.jsonData()
        let decoded = try TouchDebugSession.fromJSONData(data)

        XCTAssertEqual(decoded.scenario, session.scenario)
        XCTAssertEqual(decoded.frames.count, 1)

        let frame = decoded.frames[0].frame
        XCTAssertEqual(frame.recognizerState, "idle")
        XCTAssertEqual(frame.classified.rawCount, 3)
        XCTAssertEqual(frame.classified.digitCount, 2, "Incidental contact should survive encoding")

        let incidental = frame.classified.incidentalTouches
        XCTAssertEqual(incidental.count, 1)
        XCTAssertEqual(incidental[0].sample.fingerID, 99)
        XCTAssertGreaterThan(incidental[0].confidence, 0.6)
    }

    // MARK: - CSV Export

    func testSessionCSVHasHeaderAndOneRowPerTouch() throws {
        let session = makeSession()

        let csv = try XCTUnwrap(String(data: session.csvData(), encoding: .utf8))
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 4, "Header plus one row per classified touch")
        XCTAssertTrue(lines[0].hasPrefix("wallClock,timestamp,frame,pathIndex,fingerID"))
        XCTAssertTrue(
            lines.dropFirst().contains { $0.contains("probableThumb") || $0.contains("probablePalm") },
            "The incidental contact's role should appear in the CSV")
        XCTAssertTrue(
            lines.dropFirst().allSatisfy { $0.contains("idle") },
            "Recognizer state should appear on every row")
    }

    func testEmptySessionCSVHasOnlyHeader() {
        let session = TouchDebugSession(
            scenario: TouchDebugScenario.unlabeled.rawValue,
            startedAt: 0, endedAt: 0, appVersion: "test", frames: [])

        let csv = String(data: session.csvData(), encoding: .utf8)

        XCTAssertEqual(csv, TouchDebugSession.csvHeader)
    }

    // MARK: - Observer Delivery

    func testManagerDeliversDebugFramesToObserver() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        manager.start()
        defer { manager.stop() }

        let expectation = expectation(description: "debug frame delivered")
        expectation.assertForOverFulfill = false
        nonisolated(unsafe) var receivedFrame: TouchDebugFrame?
        manager.touchDebugObserver = { frame in
            unsafe receivedFrame = frame
            expectation.fulfill()
        }

        var touchData = [
            createTouch(
                x: 0.35, y: 0.58, fingerID: 1, pathIndex: 1, velocity: MTPoint(x: 0, y: 0.5)),
            createTouch(
                x: 0.55, y: 0.60, fingerID: 2, pathIndex: 2, velocity: MTPoint(x: 0, y: 0.5)),
            createTouch(
                x: 0.82, y: 0.52, zTotal: 5.0, fingerID: 99, pathIndex: 99,
                majorAxis: 25, minorAxis: 15),
        ]
        let touchCount = Int32(touchData.count)
        unsafe touchData.withUnsafeMutableBytes { buffer in
            guard let rawPointer = buffer.baseAddress else { return }
            let tempMonitor = unsafe DeviceMonitor()
            unsafe manager.deviceMonitor(
                tempMonitor,
                didReceiveTouches: rawPointer,
                count: touchCount,
                timestamp: CACurrentMediaTime()
            )
        }

        wait(for: [expectation], timeout: 2.0)

        let frame = unsafe receivedFrame
        XCTAssertEqual(frame?.classified.rawCount, 3)
        XCTAssertEqual(
            frame?.classified.digitCount, 2,
            "Observer should see the same classified frame the recognizer used")
        XCTAssertNotNil(frame?.recognizerState)
    }
}
