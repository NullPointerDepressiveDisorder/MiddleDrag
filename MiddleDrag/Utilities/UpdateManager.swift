import Foundation
import Sparkle

/// Manages app updates via Sparkle framework
/// Offline by default - only checks for updates when explicitly enabled by user
/// Thread-safety: Sparkle framework is designed to be accessed from main thread,
/// but we defer heavy initialization to avoid blocking the main thread during app launch
final class UpdateManager: NSObject, @unchecked Sendable {

    static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController?
    
    /// Flag to track if initialization is in progress to prevent duplicate initialization
    private var isInitializing = false
    
    /// Flag to track if initialization is complete
    private var isInitialized = false

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
            
            // Dispatch to main thread for Sparkle operations
            DispatchQueue.main.async { [weak self] in
                self?.updaterController?.updater.automaticallyChecksForUpdates = newValue

                // Start updater when enabling automatic checks
                if newValue && !previousValue {
                    self?.updaterController?.startUpdater()
                }
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

    /// Initialize Sparkle updater asynchronously to avoid blocking the main thread
    /// Call this from AppDelegate after app finishes launching
    /// The initialization is deferred to prevent app hanging during launch
    func initialize() {
        guard !isInitializing && !isInitialized else {
            Log.info("UpdateManager already initialized or initializing", category: .app)
            return
        }
        
        isInitializing = true
        
        // Defer Sparkle initialization to avoid blocking the main thread during app launch
        // This prevents the 2+ second hang that occurs when Sparkle performs synchronous
        // operations on the main thread
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.performInitialization()
        }
    }
    
    /// Perform the actual Sparkle initialization on the main thread
    /// This is called after a short delay to let the app UI settle first
    @MainActor
    private func performInitialization() {
        guard isInitializing && !isInitialized else { return }
        
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
            // Defer the start to avoid blocking
            if automaticallyChecksForUpdates {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.updaterController?.startUpdater()
                }
            }
        }
        
        isInitialized = true
        isInitializing = false

        Log.info("UpdateManager initialized (auto-check: \(automaticallyChecksForUpdates))", category: .app)
    }

    // MARK: - Public Methods

    /// Manually check for updates (always available via menu)
    /// This method dispatches to the main thread asynchronously to avoid blocking
    func checkForUpdates() {
        // Dispatch to main thread asynchronously to avoid blocking the caller
        DispatchQueue.main.async { [weak self] in
            self?.performUpdateCheck()
        }
    }
    
    /// Perform the actual update check on the main thread
    /// This is separated to ensure non-blocking behavior
    @MainActor
    private func performUpdateCheck() {
        guard let controller = updaterController else {
            Log.error("Cannot check for updates: updaterController is not initialized", category: .app)
            return
        }

        let updater = controller.updater

        // Ensure updater is started for manual check
        // Using async dispatch to prevent blocking
        if !updater.sessionInProgress {
            controller.startUpdater()
        }

        // Verify updater is ready
        guard updater.canCheckForUpdates else {
            Log.warning("Cannot check for updates: updater is not ready", category: .app)
            return
        }

        // Log first, then trigger the check
        // The check itself runs asynchronously within Sparkle
        Log.info("Manual update check triggered", category: .app)
        
        // Defer the actual check to the next run loop iteration
        // This allows the UI to remain responsive during update processing
        DispatchQueue.main.async {
            controller.checkForUpdates(nil)
        }
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
