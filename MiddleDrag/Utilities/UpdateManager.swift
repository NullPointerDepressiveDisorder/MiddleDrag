import Foundation
import Sparkle

/// Manages app updates via Sparkle framework
/// Offline by default - only checks for updates when explicitly enabled by user
/// Thread-safety: All mutable state is isolated to @MainActor to prevent data races
@MainActor
public final class UpdateManager: NSObject {

    public static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController?
    
    /// Flag to track if initialization is in progress to prevent duplicate initialization
    private var isInitializing = false
    
    /// Flag to track if initialization is complete
    private var isInitialized = false
    
    /// Flag to track if an update check was requested before initialization completed
    private var pendingUpdateCheck = false

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

    /// Initialize Sparkle updater asynchronously to avoid blocking the main thread
    /// Call this from AppDelegate after app finishes launching
    /// The initialization is deferred to prevent app hanging during launch
    public func initialize() {
        guard !isInitializing && !isInitialized else {
            Log.info("UpdateManager already initialized or initializing", category: .app)
            return
        }
        
        isInitializing = true
        
        // Defer Sparkle initialization to avoid blocking the main thread during app launch
        // This prevents the 2+ second hang that occurs when Sparkle performs synchronous
        // operations on the main thread
        Task { @MainActor [weak self] in
            // Delay to let the app fully initialize and UI settle before Sparkle setup
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            self?.performInitialization()
        }
    }
    
    /// Perform the actual Sparkle initialization
    /// This is called after a short delay to let the app UI settle first
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
            if automaticallyChecksForUpdates {
                // Defer the start slightly to avoid blocking
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    self?.updaterController?.startUpdater()
                }
            }
        }
        
        isInitialized = true
        isInitializing = false

        Log.info("UpdateManager initialized (auto-check: \(automaticallyChecksForUpdates))", category: .app)
        
        // If user requested an update check before initialization completed, perform it now
        if pendingUpdateCheck {
            pendingUpdateCheck = false
            // Yield to let UI settle before potentially blocking Sparkle work
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.performUpdateCheck()
            }
        }
    }

    // MARK: - Public Methods

    /// Manually check for updates (always available via menu)
    /// If called before initialization completes, the check will be queued
    func checkForUpdates() {
        // If not yet initialized, queue the request
        if !isInitialized {
            Log.info("Update check requested before initialization - queuing", category: .app)
            pendingUpdateCheck = true
            return
        }
        
        // Dispatch to next runloop turn so the menu can close and UI remains responsive
        // before any potentially blocking Sparkle work begins
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.performUpdateCheck()
        }
    }
    
    /// Perform the actual update check
    /// Note: This should be called after yielding to let the UI process events first
    private func performUpdateCheck() {
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

        Log.info("Manual update check triggered", category: .app)
        
        // Trigger the check; Sparkle performs the work asynchronously internally
        controller.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateManager: SPUUpdaterDelegate {

    nonisolated public func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        // Only stable channel for now
        // Could add "beta" channel later if needed
        return Set()
    }

    nonisolated public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            Log.info("Update available: \(version)", category: .app)
        }
    }

    nonisolated public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            Log.info("No updates available", category: .app)
        }
    }

    nonisolated public func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let errorMessage = error.localizedDescription
        Task { @MainActor in
            Log.error("Update check failed: \(errorMessage)", category: .app)
        }
    }
}
