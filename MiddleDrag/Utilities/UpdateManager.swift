import Foundation
import Sparkle

/// Manages app updates via Sparkle framework
/// Offline by default - only checks for updates when explicitly enabled by user
/// Thread-safety: Sparkle framework is designed to be accessed from main thread
final class UpdateManager: NSObject, @unchecked Sendable {

    static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController?

    // MARK: - Preferences Keys

    private enum Keys {
        static let automaticallyChecksForUpdates = "automaticallyChecksForUpdates"
    }

    // MARK: - Public Properties

    /// Whether automatic update checks are enabled (opt-in, default false)
    var automaticallyChecksForUpdates: Bool {
        get {
            // Default to false (offline by default)
            UserDefaults.standard.object(forKey: Keys.automaticallyChecksForUpdates) as? Bool ?? false
        }
        set {
            let previousValue = UserDefaults.standard.object(forKey: Keys.automaticallyChecksForUpdates) as? Bool ?? false

            UserDefaults.standard.set(newValue, forKey: Keys.automaticallyChecksForUpdates)
            updaterController?.updater.automaticallyChecksForUpdates = newValue

            // Start updater when enabling automatic checks
            if newValue && !previousValue {
                updaterController?.startUpdater()
            }

            Log.info("Auto-update checks \(newValue ? "enabled" : "disabled")", category: .app)
        }
    }

    /// Whether an update check can be performed right now
    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    /// Initialize Sparkle updater
    /// Call this from AppDelegate after app finishes launching
    func initialize() {
        // Create the updater controller
        // Using nil for userDriver to use the standard UI
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,  // Don't start automatically
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Configure based on user preference (default: no automatic checks)
        if let updater = updaterController?.updater {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates

            // Only start the updater if user has opted in to automatic checks
            // Otherwise, it will only check when user manually triggers it
            if automaticallyChecksForUpdates {
                updaterController?.startUpdater()
            }
        }

        Log.info("UpdateManager initialized (auto-check: \(automaticallyChecksForUpdates))", category: .app)
    }

    // MARK: - Public Methods

    /// Manually check for updates (always available via menu)
    @MainActor func checkForUpdates() {
        guard let controller = updaterController else {
            Log.error("Cannot check for updates: updaterController is not initialized", category: .app)
            return
        }

        let updater = controller.updater

        // Ensure updater is started for manual check
        if !updater.sessionInProgress {
            controller.startUpdater()
        }

        // Verify updater is ready
        guard updater.canCheckForUpdates else {
            Log.warning("Cannot check for updates: updater is not ready", category: .app)
            return
        }

        controller.checkForUpdates(nil)
        Log.info("Manual update check triggered", category: .app)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateManager: SPUUpdaterDelegate {

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        // Only stable channel for now
        // Could add "beta" channel later if needed
        return Set()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.info("Update available: \(item.displayVersionString)", category: .app)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.info("No updates available", category: .app)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Log.error("Update check failed: \(error.localizedDescription)", category: .app)
    }
}
