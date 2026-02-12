import XCTest

@testable import MiddleDragCore

// MARK: - Mock Implementations

/// Mock settings provider for testing SystemGestureHelper
class MockTrackpadSettingsProvider: TrackpadSettingsProvider {
    var settings: [String: Int] = [:]

    func getSetting(forKey key: String, domain: String) -> Int? {
        return settings[key]
    }

    func setSetting(_ value: Int, forKey key: String) {
        settings[key] = value
    }

    func clearSettings() {
        settings.removeAll()
    }
}

/// Mock process runner for testing SystemGestureHelper
class MockProcessRunner: ProcessRunner {
    var executedCommands: [(executable: String, arguments: [String])] = []
    var shouldSucceed = true

    func run(executable: String, arguments: [String]) -> Bool {
        executedCommands.append((executable, arguments))
        return shouldSucceed
    }

    func reset() {
        executedCommands.removeAll()
        shouldSucceed = true
    }
}

final class SystemGestureHelperTests: XCTestCase {

    var mockSettingsProvider: MockTrackpadSettingsProvider!
    var mockProcessRunner: MockProcessRunner!

    // Store original providers for restoration
    var originalSettingsProvider: TrackpadSettingsProvider!
    var originalProcessRunner: ProcessRunner!

    override func setUp() {
        super.setUp()
        // Save originals
        originalSettingsProvider = SystemGestureHelper.settingsProvider
        originalProcessRunner = SystemGestureHelper.processRunner

        // Create and inject mocks
        mockSettingsProvider = MockTrackpadSettingsProvider()
        mockProcessRunner = MockProcessRunner()
        SystemGestureHelper.settingsProvider = mockSettingsProvider
        SystemGestureHelper.processRunner = mockProcessRunner
    }

    override func tearDown() {
        // Restore originals
        SystemGestureHelper.settingsProvider = originalSettingsProvider
        SystemGestureHelper.processRunner = originalProcessRunner
        mockSettingsProvider = nil
        mockProcessRunner = nil
        super.tearDown()
    }

    // MARK: - TrackpadKey Tests

    func testTrackpadKeyRawValues() {
        XCTAssertEqual(
            SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue,
            "TrackpadThreeFingerVertSwipeGesture"
        )
        XCTAssertEqual(
            SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue,
            "TrackpadThreeFingerHorizSwipeGesture"
        )
        XCTAssertEqual(
            SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue,
            "TrackpadFourFingerVertSwipeGesture"
        )
        XCTAssertEqual(
            SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue,
            "TrackpadFourFingerHorizSwipeGesture"
        )
    }

    func testTrackpadKeyAllCases() {
        let allCases = SystemGestureHelper.TrackpadKey.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.threeFingerVertSwipe))
        XCTAssertTrue(allCases.contains(.threeFingerHorizSwipe))
        XCTAssertTrue(allCases.contains(.fourFingerVertSwipe))
        XCTAssertTrue(allCases.contains(.fourFingerHorizSwipe))
    }

    // MARK: - GestureValue Tests

    func testGestureValueRawValues() {
        XCTAssertEqual(SystemGestureHelper.GestureValue.disabled.rawValue, 0)
        XCTAssertEqual(SystemGestureHelper.GestureValue.enabled.rawValue, 2)
    }

    // MARK: - trackpadDomain Tests

    func testTrackpadDomain() {
        XCTAssertEqual(
            SystemGestureHelper.trackpadDomain,
            "com.apple.AppleMultitouchTrackpad"
        )
    }

    // MARK: - getTrackpadSetting Tests

    func testGetTrackpadSettingReturnsValueWhenSet() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)

        let result = SystemGestureHelper.getTrackpadSetting(.threeFingerVertSwipe)

        XCTAssertEqual(result, 2)
    }

    func testGetTrackpadSettingReturnsNilWhenNotSet() {
        mockSettingsProvider.clearSettings()

        let result = SystemGestureHelper.getTrackpadSetting(.threeFingerVertSwipe)

        XCTAssertNil(result)
    }

    func testGetTrackpadSettingReturnsCorrectValueForEachKey() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            1, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            3, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        XCTAssertEqual(SystemGestureHelper.getTrackpadSetting(.threeFingerVertSwipe), 0)
        XCTAssertEqual(SystemGestureHelper.getTrackpadSetting(.threeFingerHorizSwipe), 2)
        XCTAssertEqual(SystemGestureHelper.getTrackpadSetting(.fourFingerVertSwipe), 1)
        XCTAssertEqual(SystemGestureHelper.getTrackpadSetting(.fourFingerHorizSwipe), 3)
    }

    // MARK: - getAllSettings Tests

    func testGetAllSettingsReturnsEmptyWhenNoSettings() {
        mockSettingsProvider.clearSettings()

        let settings = SystemGestureHelper.getAllSettings()

        XCTAssertTrue(settings.isEmpty)
    }

    func testGetAllSettingsReturnsAllSetValues() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let settings = SystemGestureHelper.getAllSettings()

        XCTAssertEqual(settings.count, 4)
        XCTAssertEqual(settings[.threeFingerVertSwipe], 0)
        XCTAssertEqual(settings[.threeFingerHorizSwipe], 2)
        XCTAssertEqual(settings[.fourFingerVertSwipe], 2)
        XCTAssertEqual(settings[.fourFingerHorizSwipe], 2)
    }

    func testGetAllSettingsOnlyReturnsSetKeys() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)

        let settings = SystemGestureHelper.getAllSettings()

        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings[.threeFingerVertSwipe], 2)
    }

    // MARK: - hasConflictingSettings Tests

    func testHasConflictingSettingsReturnsFalseWhenAllDisabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertFalse(hasConflicts)
    }

    func testHasConflictingSettingsReturnsFalseWhenNotSet() {
        mockSettingsProvider.clearSettings()

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertFalse(hasConflicts)
    }

    func testHasConflictingSettingsReturnsTrueWhenVertEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertTrue(hasConflicts)
    }

    func testHasConflictingSettingsReturnsTrueWhenHorizEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertTrue(hasConflicts)
    }

    func testHasConflictingSettingsReturnsTrueWhenBothEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertTrue(hasConflicts)
    }

    func testHasConflictingSettingsIgnoresFourFingerSettings() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertFalse(hasConflicts)
    }

    // MARK: - recommendedSettings Tests

    func testRecommendedSettingsContainsExpectedValues() {
        let recommended = SystemGestureHelper.recommendedSettings

        XCTAssertEqual(recommended.count, 4)

        // Check 3-finger gestures are disabled
        let threeFingerVert = recommended.first { $0.0 == .threeFingerVertSwipe }
        XCTAssertNotNil(threeFingerVert)
        XCTAssertEqual(threeFingerVert?.1, .disabled)

        let threeFingerHoriz = recommended.first { $0.0 == .threeFingerHorizSwipe }
        XCTAssertNotNil(threeFingerHoriz)
        XCTAssertEqual(threeFingerHoriz?.1, .disabled)

        // Check 4-finger gestures are enabled
        let fourFingerVert = recommended.first { $0.0 == .fourFingerVertSwipe }
        XCTAssertNotNil(fourFingerVert)
        XCTAssertEqual(fourFingerVert?.1, .enabled)

        let fourFingerHoriz = recommended.first { $0.0 == .fourFingerHorizSwipe }
        XCTAssertNotNil(fourFingerHoriz)
        XCTAssertEqual(fourFingerHoriz?.1, .enabled)
    }

    // MARK: - applyRecommendedSettings Tests

    func testApplyRecommendedSettingsExecutesCorrectCommands() {
        mockProcessRunner.shouldSucceed = true

        let success = SystemGestureHelper.applyRecommendedSettings()

        XCTAssertTrue(success)
        // Should have 4 defaults write commands + 1 killall Dock
        XCTAssertEqual(mockProcessRunner.executedCommands.count, 5)

        // Check the defaults write commands
        for i in 0..<4 {
            XCTAssertEqual(mockProcessRunner.executedCommands[i].executable, "/usr/bin/defaults")
            XCTAssertEqual(mockProcessRunner.executedCommands[i].arguments[0], "write")
            XCTAssertEqual(
                mockProcessRunner.executedCommands[i].arguments[1],
                SystemGestureHelper.trackpadDomain)
        }

        // Check killall Dock command
        XCTAssertEqual(mockProcessRunner.executedCommands[4].executable, "/usr/bin/killall")
        XCTAssertEqual(mockProcessRunner.executedCommands[4].arguments, ["Dock"])
    }

    func testApplyRecommendedSettingsReturnsFalseOnFailure() {
        mockProcessRunner.shouldSucceed = false

        let success = SystemGestureHelper.applyRecommendedSettings()

        XCTAssertFalse(success)
        // Should have 4 defaults write commands but no killall (fails before dock restart)
        XCTAssertEqual(mockProcessRunner.executedCommands.count, 4)
    }

    func testApplyRecommendedSettingsWritesCorrectValues() {
        mockProcessRunner.shouldSucceed = true

        _ = SystemGestureHelper.applyRecommendedSettings()

        // Extract the values written
        let writtenValues = mockProcessRunner.executedCommands.prefix(4).map {
            cmd -> (String, String) in
            let key = cmd.arguments[2]
            let value = cmd.arguments[4]
            return (key, value)
        }

        // Verify 3-finger gestures are set to 0 (disabled)
        let threeFingerVertCmd = writtenValues.first {
            $0.0 == SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue
        }
        XCTAssertEqual(threeFingerVertCmd?.1, "0")

        let threeFingerHorizCmd = writtenValues.first {
            $0.0 == SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue
        }
        XCTAssertEqual(threeFingerHorizCmd?.1, "0")

        // Verify 4-finger gestures are set to 2 (enabled)
        let fourFingerVertCmd = writtenValues.first {
            $0.0 == SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue
        }
        XCTAssertEqual(fourFingerVertCmd?.1, "2")

        let fourFingerHorizCmd = writtenValues.first {
            $0.0 == SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue
        }
        XCTAssertEqual(fourFingerHorizCmd?.1, "2")
    }

    // MARK: - restartDock Tests

    func testRestartDockExecutesKillallCommand() {
        mockProcessRunner.reset()

        SystemGestureHelper.restartDock()

        XCTAssertEqual(mockProcessRunner.executedCommands.count, 1)
        XCTAssertEqual(mockProcessRunner.executedCommands[0].executable, "/usr/bin/killall")
        XCTAssertEqual(mockProcessRunner.executedCommands[0].arguments, ["Dock"])
    }

    // MARK: - describeCurrentSettings Tests

    func testDescribeCurrentSettingsWhenAllDisabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertEqual(description, "All system gestures are disabled")
    }

    func testDescribeCurrentSettingsWhenNoneSet() {
        mockSettingsProvider.clearSettings()

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertEqual(description, "All system gestures are disabled")
    }

    func testDescribeCurrentSettingsWhenThreeFingerVertEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("3-finger vertical swipe (Mission Control): Enabled"))
        XCTAssertFalse(description.contains("3-finger horizontal swipe"))
    }

    func testDescribeCurrentSettingsWhenThreeFingerHorizEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("3-finger horizontal swipe (Spaces): Enabled"))
        XCTAssertFalse(description.contains("3-finger vertical swipe"))
    }

    func testDescribeCurrentSettingsWhenFourFingerVertEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("4-finger vertical swipe (Mission Control): Enabled"))
    }

    func testDescribeCurrentSettingsWhenFourFingerHorizEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("4-finger horizontal swipe (Spaces): Enabled"))
    }

    func testDescribeCurrentSettingsWhenAllEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("3-finger vertical swipe (Mission Control): Enabled"))
        XCTAssertTrue(description.contains("3-finger horizontal swipe (Spaces): Enabled"))
        XCTAssertTrue(description.contains("4-finger vertical swipe (Mission Control): Enabled"))
        XCTAssertTrue(description.contains("4-finger horizontal swipe (Spaces): Enabled"))
    }

    func testDescribeCurrentSettingsFormatsMultipleLinesCorrectly() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        // Should be joined by newlines
        let lines = description.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
    }

    // MARK: - Default Implementation Tests

    func testDefaultTrackpadSettingsProviderExists() {
        let provider = DefaultTrackpadSettingsProvider()
        XCTAssertNotNil(provider)
    }

    func testDefaultProcessRunnerExists() {
        let runner = DefaultProcessRunner()
        XCTAssertNotNil(runner)
    }

    // MARK: - describeConflictingSettings Tests

    func testDescribeConflictingSettingsWhenNoConflicts() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        XCTAssertEqual(description, "No conflicting gestures detected")
    }

    func testDescribeConflictingSettingsWhenNoneSet() {
        mockSettingsProvider.clearSettings()

        let description = SystemGestureHelper.describeConflictingSettings()

        XCTAssertEqual(description, "No conflicting gestures detected")
    }

    func testDescribeConflictingSettingsOnlyShowsThreeFingerGestures() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        // Should only show 3-finger gestures, not 4-finger
        XCTAssertTrue(description.contains("3-finger vertical swipe"))
        XCTAssertTrue(description.contains("3-finger horizontal swipe"))
        XCTAssertFalse(description.contains("4-finger"))
    }

    func testDescribeConflictingSettingsWhenOnlyVertEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        XCTAssertTrue(description.contains("3-finger vertical swipe (Mission Control): Enabled"))
        XCTAssertFalse(description.contains("3-finger horizontal swipe"))
    }

    func testDescribeConflictingSettingsWhenOnlyHorizEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        XCTAssertTrue(description.contains("3-finger horizontal swipe (Spaces): Enabled"))
        XCTAssertFalse(description.contains("3-finger vertical swipe"))
    }

    func testDescribeConflictingSettingsIgnoresFourFingerGestures() {
        // Only 4-finger enabled, no 3-finger
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        // Should say no conflicts since 4-finger gestures don't conflict
        XCTAssertEqual(description, "No conflicting gestures detected")
    }
}
