import XCTest

@testable import MiddleDrag

// MARK: - Mock Alert Presenter

/// Mock presenter for testing AlertHelper without displaying modals
class MockAlertPresenter: AlertPresenter {
    var presentedAlerts: [NSAlert] = []
    var openedURLs: [URL] = []
    var modalResponse: NSApplication.ModalResponse = .alertFirstButtonReturn

    func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        presentedAlerts.append(alert)
        return modalResponse
    }

    func openURL(_ url: URL) {
        openedURLs.append(url)
    }

    func reset() {
        presentedAlerts.removeAll()
        openedURLs.removeAll()
        modalResponse = .alertFirstButtonReturn
    }
}

/// Tests for AlertHelper.
final class AlertHelperTests: XCTestCase {

    var mockPresenter: MockAlertPresenter!
    var originalPresenter: AlertPresenter!

    // Also need to mock SystemGestureHelper for configuration prompt tests
    var mockSettingsProvider: MockTrackpadSettingsProvider!
    var originalSettingsProvider: TrackpadSettingsProvider!

    override func setUp() {
        super.setUp()
        // Save and replace AlertHelper presenter
        originalPresenter = AlertHelper.presenter
        mockPresenter = MockAlertPresenter()
        AlertHelper.presenter = mockPresenter

        // Save and replace SystemGestureHelper settings provider
        originalSettingsProvider = SystemGestureHelper.settingsProvider
        mockSettingsProvider = MockTrackpadSettingsProvider()
        SystemGestureHelper.settingsProvider = mockSettingsProvider
    }

    override func tearDown() {
        // Restore originals
        AlertHelper.presenter = originalPresenter
        SystemGestureHelper.settingsProvider = originalSettingsProvider
        mockPresenter = nil
        mockSettingsProvider = nil
        super.tearDown()
    }

    // MARK: - Existence Tests

    func testAlertHelperClassExists() {
        // Verify the AlertHelper type is accessible
        let helperType = AlertHelper.self
        XCTAssertNotNil(helperType)
    }

    // MARK: - URL Constant Tests

    func testTrackpadSettingsURLIsValid() {
        let url = AlertHelper.trackpadSettingsURL
        XCTAssertNotNil(url, "Trackpad settings URL should be valid")
        XCTAssertEqual(url?.scheme, "x-apple.systempreferences")
    }

    func testGitHubURLIsValid() {
        let url = AlertHelper.gitHubURL
        XCTAssertNotNil(url, "GitHub URL should be valid")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "github.com")
    }

    // MARK: - Bundle Version Tests

    func testBundleVersionCanBeRetrieved() {
        // Test version retrieval logic similar to AlertHelper.showAbout()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        // In test target, version might be nil or different, either is fine
        // We just verify the logic path doesn't crash
        let displayVersion = version ?? "Unknown"
        XCTAssertFalse(displayVersion.isEmpty)
    }

    // MARK: - About Alert Tests

    func testCreateAboutAlertMessageText() {
        let alert = AlertHelper.createAboutAlert()
        XCTAssertEqual(alert.messageText, "MiddleDrag")
    }

    func testCreateAboutAlertHasTwoButtons() {
        let alert = AlertHelper.createAboutAlert()
        XCTAssertEqual(alert.buttons.count, 2)
        XCTAssertEqual(alert.buttons[0].title, "OK")
        XCTAssertEqual(alert.buttons[1].title, "Open GitHub")
    }

    func testCreateAboutAlertStyle() {
        let alert = AlertHelper.createAboutAlert()
        XCTAssertEqual(alert.alertStyle, .informational)
    }

    func testCreateAboutAlertContainsVersionInfo() {
        let alert = AlertHelper.createAboutAlert()
        XCTAssertTrue(alert.informativeText.contains("Version"))
    }

    func testCreateAboutAlertContainsFeatures() {
        let alert = AlertHelper.createAboutAlert()
        XCTAssertTrue(alert.informativeText.contains("Features"))
        XCTAssertTrue(alert.informativeText.contains("Three-finger drag"))
    }

    func testShowAboutPresentsAlert() {
        mockPresenter.modalResponse = .alertFirstButtonReturn

        AlertHelper.showAbout()

        XCTAssertEqual(mockPresenter.presentedAlerts.count, 1)
        XCTAssertEqual(mockPresenter.presentedAlerts[0].messageText, "MiddleDrag")
    }

    func testShowAboutOpensGitHubOnSecondButton() {
        mockPresenter.modalResponse = .alertSecondButtonReturn

        AlertHelper.showAbout()

        XCTAssertEqual(mockPresenter.openedURLs.count, 1)
        XCTAssertEqual(mockPresenter.openedURLs[0], AlertHelper.gitHubURL)
    }

    func testShowAboutDoesNotOpenURLOnFirstButton() {
        mockPresenter.modalResponse = .alertFirstButtonReturn

        AlertHelper.showAbout()

        XCTAssertTrue(mockPresenter.openedURLs.isEmpty)
    }

    // MARK: - Quick Setup Alert Tests

    func testCreateQuickSetupAlertMessageText() {
        let alert = AlertHelper.createQuickSetupAlert()
        XCTAssertEqual(alert.messageText, "MiddleDrag Quick Setup")
    }

    func testCreateQuickSetupAlertHasTwoButtons() {
        let alert = AlertHelper.createQuickSetupAlert()
        XCTAssertEqual(alert.buttons.count, 2)
        XCTAssertEqual(alert.buttons[0].title, "Got it!")
        XCTAssertEqual(alert.buttons[1].title, "Open Trackpad Settings")
    }

    func testCreateQuickSetupAlertContainsInstructions() {
        let alert = AlertHelper.createQuickSetupAlert()
        XCTAssertTrue(alert.informativeText.contains("Three fingers drag"))
        XCTAssertTrue(alert.informativeText.contains("Middle mouse drag"))
    }

    func testShowQuickSetupPresentsAlert() {
        mockPresenter.modalResponse = .alertFirstButtonReturn

        AlertHelper.showQuickSetup()

        XCTAssertEqual(mockPresenter.presentedAlerts.count, 1)
        XCTAssertEqual(mockPresenter.presentedAlerts[0].messageText, "MiddleDrag Quick Setup")
    }

    func testShowQuickSetupOpensTrackpadSettingsOnSecondButton() {
        mockPresenter.modalResponse = .alertSecondButtonReturn

        AlertHelper.showQuickSetup()

        XCTAssertEqual(mockPresenter.openedURLs.count, 1)
        XCTAssertEqual(mockPresenter.openedURLs[0], AlertHelper.trackpadSettingsURL)
    }

    // MARK: - Already Optimal Alert Tests

    func testCreateGestureConfigurationAlreadyOptimalAlertMessageText() {
        let alert = AlertHelper.createGestureConfigurationAlreadyOptimalAlert()
        XCTAssertEqual(alert.messageText, "System Gestures Already Configured")
    }

    func testCreateGestureConfigurationAlreadyOptimalAlertHasOneButton() {
        let alert = AlertHelper.createGestureConfigurationAlreadyOptimalAlert()
        XCTAssertEqual(alert.buttons.count, 1)
        XCTAssertEqual(alert.buttons[0].title, "OK")
    }

    func testCreateGestureConfigurationAlreadyOptimalAlertContainsCheckmark() {
        let alert = AlertHelper.createGestureConfigurationAlreadyOptimalAlert()
        XCTAssertTrue(alert.informativeText.contains("✅"))
    }

    func testShowGestureConfigurationAlreadyOptimalPresentsAlert() {
        AlertHelper.showGestureConfigurationAlreadyOptimal()

        XCTAssertEqual(mockPresenter.presentedAlerts.count, 1)
        XCTAssertEqual(
            mockPresenter.presentedAlerts[0].messageText, "System Gestures Already Configured")
    }

    // MARK: - Configuration Prompt Alert Tests

    func testCreateGestureConfigurationPromptAlertMessageText() {
        let alert = AlertHelper.createGestureConfigurationPromptAlert()
        XCTAssertEqual(alert.messageText, "Configure System Gestures")
    }

    func testCreateGestureConfigurationPromptAlertHasThreeButtons() {
        let alert = AlertHelper.createGestureConfigurationPromptAlert()
        XCTAssertEqual(alert.buttons.count, 3)
        XCTAssertEqual(alert.buttons[0].title, "Apply Changes")
        XCTAssertEqual(alert.buttons[1].title, "Open Trackpad Settings")
        XCTAssertEqual(alert.buttons[2].title, "Cancel")
    }

    func testShowGestureConfigurationPromptReturnsTrueOnApply() {
        mockPresenter.modalResponse = .alertFirstButtonReturn

        let result = AlertHelper.showGestureConfigurationPrompt()

        XCTAssertTrue(result)
    }

    func testShowGestureConfigurationPromptReturnsFalseOnOpenSettings() {
        mockPresenter.modalResponse = .alertSecondButtonReturn

        let result = AlertHelper.showGestureConfigurationPrompt()

        XCTAssertFalse(result)
        XCTAssertEqual(mockPresenter.openedURLs.count, 1)
    }

    func testShowGestureConfigurationPromptReturnsFalseOnCancel() {
        mockPresenter.modalResponse = .alertThirdButtonReturn

        let result = AlertHelper.showGestureConfigurationPrompt()

        XCTAssertFalse(result)
        XCTAssertTrue(mockPresenter.openedURLs.isEmpty)
    }

    // MARK: - Success Alert Tests

    func testCreateGestureConfigurationSuccessAlertMessageText() {
        let alert = AlertHelper.createGestureConfigurationSuccessAlert()
        XCTAssertEqual(alert.messageText, "Settings Applied")
    }

    func testCreateGestureConfigurationSuccessAlertHasOneButton() {
        let alert = AlertHelper.createGestureConfigurationSuccessAlert()
        XCTAssertEqual(alert.buttons.count, 1)
        XCTAssertEqual(alert.buttons[0].title, "OK")
    }

    func testCreateGestureConfigurationSuccessAlertContainsChanges() {
        let alert = AlertHelper.createGestureConfigurationSuccessAlert()
        XCTAssertTrue(alert.informativeText.contains("3-finger Mission Control"))
        XCTAssertTrue(alert.informativeText.contains("4-finger"))
    }

    func testShowGestureConfigurationSuccessPresentsAlert() {
        AlertHelper.showGestureConfigurationSuccess()

        XCTAssertEqual(mockPresenter.presentedAlerts.count, 1)
        XCTAssertEqual(mockPresenter.presentedAlerts[0].messageText, "Settings Applied")
    }

    // MARK: - Failure Alert Tests

    func testCreateGestureConfigurationFailureAlertMessageText() {
        let alert = AlertHelper.createGestureConfigurationFailureAlert()
        XCTAssertEqual(alert.messageText, "Failed to Apply Settings")
    }

    func testCreateGestureConfigurationFailureAlertHasTwoButtons() {
        let alert = AlertHelper.createGestureConfigurationFailureAlert()
        XCTAssertEqual(alert.buttons.count, 2)
        XCTAssertEqual(alert.buttons[0].title, "Open Trackpad Settings")
        XCTAssertEqual(alert.buttons[1].title, "Cancel")
    }

    func testCreateGestureConfigurationFailureAlertStyle() {
        let alert = AlertHelper.createGestureConfigurationFailureAlert()
        XCTAssertEqual(alert.alertStyle, .warning)
    }

    func testCreateGestureConfigurationFailureAlertContainsManualSteps() {
        let alert = AlertHelper.createGestureConfigurationFailureAlert()
        XCTAssertTrue(alert.informativeText.contains("System Settings"))
        XCTAssertTrue(alert.informativeText.contains("Mission Control"))
    }

    func testShowGestureConfigurationFailureOpensSettingsOnFirstButton() {
        mockPresenter.modalResponse = .alertFirstButtonReturn

        AlertHelper.showGestureConfigurationFailure()

        XCTAssertEqual(mockPresenter.openedURLs.count, 1)
        XCTAssertEqual(mockPresenter.openedURLs[0], AlertHelper.trackpadSettingsURL)
    }

    func testShowGestureConfigurationFailureDoesNotOpenSettingsOnCancel() {
        mockPresenter.modalResponse = .alertSecondButtonReturn

        AlertHelper.showGestureConfigurationFailure()

        XCTAssertTrue(mockPresenter.openedURLs.isEmpty)
    }

    // MARK: - Default Implementation Tests

    func testDefaultAlertPresenterExists() {
        let presenter = DefaultAlertPresenter()
        XCTAssertNotNil(presenter)
    }
}
