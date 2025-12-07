import Foundation
import Cocoa
import Sentry
import os.log

// MARK: - Sentry Logger
/// A unified logger that writes to both os_log and Sentry breadcrumbs
/// Usage: Log.debug("message"), Log.info("message"), Log.warning("message"), Log.error("message"), Log.fatal("message")
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.middledrag"
    
    // OS Log categories
    private static let gestureLog = OSLog(subsystem: subsystem, category: "gesture")
    private static let deviceLog = OSLog(subsystem: subsystem, category: "device")
    private static let analyticsLog = OSLog(subsystem: subsystem, category: "analytics")
    private static let appLog = OSLog(subsystem: subsystem, category: "app")
    
    enum Category: String {
        case gesture
        case device
        case analytics
        case app
        
        var osLog: OSLog {
            switch self {
            case .gesture: return Log.gestureLog
            case .device: return Log.deviceLog
            case .analytics: return Log.analyticsLog
            case .app: return Log.appLog
            }
        }
    }
    
    /// Debug level - only in debug builds, not sent to Sentry
    static func debug(_ message: String, category: Category = .app) {
        #if DEBUG
        os_log(.debug, log: category.osLog, "%{public}@", message)
        #endif
    }
    
    /// Info level - logged locally and as Sentry breadcrumb
    static func info(_ message: String, category: Category = .app) {
        os_log(.info, log: category.osLog, "%{public}@", message)
        addBreadcrumb(message: message, category: category, level: .info)
    }
    
    /// Warning level - logged locally and as Sentry breadcrumb
    static func warning(_ message: String, category: Category = .app) {
        os_log(.error, log: category.osLog, "⚠️ %{public}@", message)
        addBreadcrumb(message: message, category: category, level: .warning)
    }
    
    /// Error level - logged locally, sent as Sentry breadcrumb AND captured as event
    static func error(_ message: String, category: Category = .app, error: Error? = nil) {
        os_log(.fault, log: category.osLog, "❌ %{public}@", message)
        addBreadcrumb(message: message, category: category, level: .error)
        
        // Also capture as Sentry event for errors
        if let error = error {
            SentrySDK.capture(error: error) { scope in
                scope.setContext(value: ["message": message], key: "log_context")
            }
        } else {
            SentrySDK.capture(message: message) { scope in
                scope.setLevel(.error)
                scope.setTag(value: category.rawValue, key: "log_category")
            }
        }
    }
    
    /// Fatal level - for unrecoverable errors, always captured
    static func fatal(_ message: String, category: Category = .app, error: Error? = nil) {
        os_log(.fault, log: category.osLog, "💀 FATAL: %{public}@", message)
        
        SentrySDK.capture(message: "FATAL: \(message)") { scope in
            scope.setLevel(.fatal)
            scope.setTag(value: category.rawValue, key: "log_category")
            if let error = error {
                scope.setContext(value: ["error": error.localizedDescription], key: "error_info")
            }
        }
    }
    
    private static func addBreadcrumb(message: String, category: Category, level: SentryLevel) {
        let breadcrumb = Breadcrumb()
        breadcrumb.category = category.rawValue
        breadcrumb.message = message
        breadcrumb.level = level
        breadcrumb.timestamp = Date()
        SentrySDK.addBreadcrumb(breadcrumb)
    }
}

// MARK: - Analytics Manager
/// Crash reporting for MiddleDrag using Sentry
///
/// ## Privacy:
/// - Sentry: Only captures crashes/errors, no PII
/// - No usage analytics or tracking
/// - Users can opt-out via app preferences

final class AnalyticsManager {
    
    static let shared = AnalyticsManager()
    
    // MARK: - Configuration
    
    private let sentryDSN = "https://3c3b5cf85ceb42936097f4f16e58b19b@o4510461788028928.ingest.us.sentry.io/4510461861429248"
    
    /// UserDefaults key for crash reporting opt-out
    private let analyticsEnabledKey = "analyticsEnabled"
    
    /// Whether crash reporting is enabled (defaults to true, user can opt out)
    var isEnabled: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: analyticsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: analyticsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: analyticsEnabledKey)
        }
    }
    
    // MARK: - Initialization
    
    private var isInitialized = false
    
    private init() {}
    
    /// Initialize crash reporting - call once at app launch in AppDelegate
    func initialize() {
        guard isEnabled, !isInitialized else { return }
        
        initializeSentry()
        
        isInitialized = true
        
        #if DEBUG
        Log.debug("Sentry crash reporting initialized", category: .analytics)
        #endif
    }
    
    // MARK: - Sentry Integration
    
    private var isSentryConfigured: Bool {
        return sentryDSN != "YOUR_SENTRY_DSN_HERE" && sentryDSN.hasPrefix("https://")
    }
    
    private func initializeSentry() {
        // Skip if DSN not configured
        guard isSentryConfigured else {
            #if DEBUG
            Log.debug("Sentry DSN not configured - skipping initialization", category: .analytics)
            #endif
            return
        }
        
        SentrySDK.start { options in
            options.dsn = self.sentryDSN
            options.debug = false
            
            // Enable automatic crash reporting
            options.enableCrashHandler = true
            
            // macOS-specific: enable uncaught exception reporting
            options.enableUncaughtNSExceptionReporting = true
            
            // Performance monitoring (optional, uses quota)
            options.tracesSampleRate = 0.1 // 10% of transactions
            
            // Environment
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
            
            // App version
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                options.releaseName = "middledrag@\(version)"
            }
        }
    }
    
    // MARK: - Public API
    
    /// Track error (sent to Sentry)
    func trackError(_ error: Error, context: [String: Any]? = nil) {
        guard isEnabled, isSentryConfigured else { return }
        
        SentrySDK.capture(error: error) { scope in
            if let context = context {
                scope.setContext(value: context, key: "custom")
            }
        }
        
        #if DEBUG
        Log.debug("Error tracked: \(error.localizedDescription)", category: .analytics)
        #endif
    }
    
    /// Add breadcrumb for crash context (no network call, just stored locally until crash)
    func addBreadcrumb(_ message: String, category: String = "app") {
        guard isEnabled, isSentryConfigured else { return }
        
        let breadcrumb = Breadcrumb()
        breadcrumb.category = category
        breadcrumb.message = message
        breadcrumb.level = .info
        breadcrumb.timestamp = Date()
        SentrySDK.addBreadcrumb(breadcrumb)
    }
}
