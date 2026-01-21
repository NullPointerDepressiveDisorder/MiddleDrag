import Foundation
import Cocoa
import Sentry
import os.log

// MARK: - Logger
/// A unified logger that writes to os_log (always) and Sentry (if enabled)
/// Usage: Log.debug("message"), Log.info("message"), Log.warning("message"), Log.error("message"), Log.fatal("message")
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.middledrag"
    
    // OS Log categories
    private static let gestureLog = OSLog(subsystem: subsystem, category: "gesture")
    private static let deviceLog = OSLog(subsystem: subsystem, category: "device")
    private static let crashLog = OSLog(subsystem: subsystem, category: "crash")
    private static let appLog = OSLog(subsystem: subsystem, category: "app")
    
    // Session ID to distinguish different testing/debugging sessions
    static let sessionID: String = {
        // Generate a short, readable session ID (e.g., "2026-01-16-abc123")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let randomStr = unsafe String(format: "%06x", arc4random_uniform(0xFFFFFF))
        return "\(dateStr)-\(randomStr)"
    }()
    
    enum Category: String {
        case gesture
        case device
        case crash
        case app
        
        var osLog: OSLog {
            switch self {
            case .gesture: return Log.gestureLog
            case .device: return Log.deviceLog
            case .crash: return Log.crashLog
            case .app: return Log.appLog
            }
        }
    }
    
    private static func attributes(category: Category) -> [String: Any] {
        var attrs: [String: Any] = ["category": category.rawValue]
        attrs["session_id"] = sessionID
        return attrs
    }
    
    /// Check if Sentry logging should be enabled (only if telemetry is enabled)
    private static var shouldLogToSentry: Bool {
        return CrashReporter.shared.anyTelemetryEnabled
    }
    
    /// Debug level - only in debug builds
    static func debug(_ message: String, category: Category = .app) {
        #if DEBUG
        unsafe os_log(.debug, log: category.osLog, "%{public}@", message)
        #endif
        // Only log to Sentry if telemetry is enabled (offline by default)
        if shouldLogToSentry {
            SentrySDK.logger.debug(message, attributes: attributes(category: category))
        }
    }
    
    /// Info level
    static func info(_ message: String, category: Category = .app) {
        unsafe os_log(.info, log: category.osLog, "%{public}@", message)
        // Only log to Sentry if telemetry is enabled (offline by default)
        if shouldLogToSentry {
            SentrySDK.logger.info(message, attributes: attributes(category: category))
        }
    }
    
    /// Warning level
    static func warning(_ message: String, category: Category = .app) {
        unsafe os_log(.error, log: category.osLog, "⚠️ %{public}@", message)
        // Only log to Sentry if telemetry is enabled (offline by default)
        if shouldLogToSentry {
            SentrySDK.logger.warn(message, attributes: attributes(category: category))
        }
    }
    
    /// Error level
    static func error(_ message: String, category: Category = .app, error: Error? = nil) {
        unsafe os_log(.fault, log: category.osLog, "❌ %{public}@", message)
        // Only log to Sentry if telemetry is enabled (offline by default)
        if shouldLogToSentry {
            var attrs = attributes(category: category)
            if let error = error {
                attrs["error"] = error.localizedDescription
            }
            SentrySDK.logger.error(message, attributes: attrs)
        }
    }
    
    /// Fatal level
    static func fatal(_ message: String, category: Category = .app, error: Error? = nil) {
        unsafe os_log(.fault, log: category.osLog, "💀 FATAL: %{public}@", message)
        // Only log to Sentry if telemetry is enabled (offline by default)
        if shouldLogToSentry {
            var attrs = attributes(category: category)
            attrs["level"] = "fatal"
            if let error = error {
                attrs["error"] = error.localizedDescription
            }
            SentrySDK.logger.fatal(message, attributes: attrs)
        }
    }
}


// MARK: - Crash Reporter
/// Optional crash reporting for MiddleDrag using Sentry
///
/// ## Privacy-First Design:
/// - **Offline by default** - No network calls until user opts in
/// - **Crash reporting** (opt-in) - Only sends data when app crashes
/// - **Performance monitoring** (opt-in) - Sends traces during normal use to help improve app
/// - All data is anonymous (no PII collected)
/// - Users control both settings independently
///
/// ## Network Behavior:
/// - Both settings OFF (default): Zero network calls, ever
/// - Crash reporting ON only: Network call only when app crashes
/// - Performance monitoring ON: Network calls during normal operation (sampled)

/// Thread-safety: Uses UserDefaults (internally synchronized) and Sentry SDK (thread-safe)
final class CrashReporter: @unchecked Sendable {
    
    static let shared = CrashReporter()
    
    // MARK: - Configuration
    
    private let sentryDSN = "https://3c3b5cf85ceb42936097f4f16e58b19b@o4510461788028928.ingest.us.sentry.io/4510461861429248"
    
    // UserDefaults keys
    private let crashReportingKey = "crashReportingEnabled"
    private let performanceMonitoringKey = "performanceMonitoringEnabled"
    
    // MARK: - UserDefaults Helpers
    
    /// Read crash reporting enabled state from UserDefaults
    private func readCrashReportingEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: crashReportingKey)
    }
    
    /// Read performance monitoring enabled state from UserDefaults
    private func readPerformanceMonitoringEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: performanceMonitoringKey)
    }
    
    /// Whether crash reporting is enabled (default: false - user must opt in)
    /// When enabled, sends crash reports to help fix bugs
    var isEnabled: Bool {
        get { readCrashReportingEnabled() }
        set {
            let wasEnabled = readCrashReportingEnabled()
            UserDefaults.standard.set(newValue, forKey: crashReportingKey)
            
            // Re-initialize or close Sentry based on new state
            if newValue && !wasEnabled {
                initializeSentryIfNeeded()
            } else if !newValue && wasEnabled && !performanceMonitoringEnabled {
                closeSentry()
            }
        }
    }
    
    /// Whether performance monitoring is enabled (default: false - user must opt in)
    /// When enabled, sends anonymous performance traces during normal app use
    /// This helps identify slow operations and improve app responsiveness
    var performanceMonitoringEnabled: Bool {
        get { readPerformanceMonitoringEnabled() }
        set {
            let wasEnabled = readPerformanceMonitoringEnabled()
            UserDefaults.standard.set(newValue, forKey: performanceMonitoringKey)
            
            // Re-initialize or close Sentry based on new state
            if newValue && !wasEnabled {
                initializeSentryIfNeeded()
            } else if !newValue && wasEnabled && !isEnabled {
                closeSentry()
            }
            // Note: If already initialized, sample rate change requires restart
        }
    }
    
    /// Returns true if any telemetry is enabled (for UI display)
    var anyTelemetryEnabled: Bool {
        return isEnabled || performanceMonitoringEnabled
    }
    
    // MARK: - Initialization
    
    private var isSentryInitialized = false
    
    private init() {}
    
    /// Call at app launch - only initializes Sentry if user has opted in
    func initializeIfEnabled() {
        guard anyTelemetryEnabled else {
            #if DEBUG
            SentrySDK.logger.debug("CrashReporter: Telemetry disabled (offline mode)")
            #endif
            return
        }
        initializeSentryIfNeeded()
    }
    
    // MARK: - Sentry Integration
    
    private var isSentryConfigured: Bool {
        return sentryDSN != "YOUR_SENTRY_DSN_HERE" && sentryDSN.hasPrefix("https://")
    }
    
    private func initializeSentryIfNeeded() {
        guard !isSentryInitialized, isSentryConfigured else { return }
        
        SentrySDK.start { options in
            options.dsn = self.sentryDSN
            options.debug = false
            
            // Enable structured logs for querying and analysis
            // This allows us to query logs in Sentry Discover and create dashboard widgets
            options.enableLogs = true
            
            // Crash reporting - always enabled if Sentry is initialized
            options.enableCrashHandler = true
            options.enableUncaughtNSExceptionReporting = true
            
            // Performance monitoring - only if user opted in
            // 0.0 = disabled, 0.1 = 10% sampling
            options.tracesSampleRate = self.performanceMonitoringEnabled ? 0.1 : 0.0
            
            // Environment
            if ProcessInfo.processInfo.environment["CI"] != nil {
                options.environment = "CI"
            } else {
                // Check if running from Xcode build (Debug) vs installed app (Release)
                // Xcode builds typically have the app in DerivedData or Build/Products/Debug
                let bundlePath = Bundle.main.bundlePath
                let isDebugBuild = bundlePath.contains("/DerivedData/") ||
                                   bundlePath.contains("/Build/Products/Debug/") ||
                                   bundlePath.contains("/Xcode/DerivedData/")
                
                #if DEBUG
                // Compile-time: definitely debug if DEBUG flag is set
                options.environment = "development"
                #else
                // Runtime: check if it looks like a debug build path
                // This handles cases where Release config is used but running from Xcode
                options.environment = isDebugBuild ? "development" : "production"
                #endif
            }
            
            // App version
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                options.releaseName = "middledrag@\(version)"
            }
        }
        
        // Set session ID as a tag for easy filtering in Sentry
        SentrySDK.configureScope { scope in
            scope.setTag(value: Log.sessionID, key: "session_id")
        }
        
        // Log session start
        SentrySDK.logger.info("Session started", attributes: [
            "session_id": Log.sessionID,
            "category": "app"
        ])
        
        isSentryInitialized = true
        
        #if DEBUG
        SentrySDK.logger.debug("CrashReporter: Sentry initialized (crash=\(self.isEnabled), perf=\(self.performanceMonitoringEnabled))")
        #endif
    }
    
    private func closeSentry() {
        guard isSentryInitialized else { return }
        SentrySDK.close()
        isSentryInitialized = false
        
        #if DEBUG
        SentrySDK.logger.debug("CrashReporter: Sentry closed (offline mode)")
        #endif
    }
}
