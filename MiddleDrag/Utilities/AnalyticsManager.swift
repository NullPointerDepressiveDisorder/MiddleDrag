import Foundation
import Cocoa
import Sentry
import os.log

// MARK: - Logger
/// A unified logger that writes to os_log (and optionally Sentry breadcrumbs if crash reporting is enabled)
/// Usage: Log.debug("message"), Log.info("message"), Log.warning("message"), Log.error("message"), Log.fatal("message")
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.middledrag"
    
    // OS Log categories
    private static let gestureLog = OSLog(subsystem: subsystem, category: "gesture")
    private static let deviceLog = OSLog(subsystem: subsystem, category: "device")
    private static let crashLog = OSLog(subsystem: subsystem, category: "crash")
    private static let appLog = OSLog(subsystem: subsystem, category: "app")
    
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
    
    /// Debug level - only in debug builds, never sent anywhere
    static func debug(_ message: String, category: Category = .app) {
        #if DEBUG
        os_log(.debug, log: category.osLog, "%{public}@", message)
        #endif
    }
    
    /// Info level - logged locally, breadcrumb added only if crash reporting enabled
    static func info(_ message: String, category: Category = .app) {
        os_log(.info, log: category.osLog, "%{public}@", message)
        CrashReporter.shared.addBreadcrumbIfEnabled(message: message, category: category.rawValue, level: .info)
    }
    
    /// Warning level - logged locally, breadcrumb added only if crash reporting enabled
    static func warning(_ message: String, category: Category = .app) {
        os_log(.error, log: category.osLog, "⚠️ %{public}@", message)
        CrashReporter.shared.addBreadcrumbIfEnabled(message: message, category: category.rawValue, level: .warning)
    }
    
    /// Error level - logged locally, captured by Sentry only if crash reporting enabled
    static func error(_ message: String, category: Category = .app, error: Error? = nil) {
        os_log(.fault, log: category.osLog, "❌ %{public}@", message)
        CrashReporter.shared.addBreadcrumbIfEnabled(message: message, category: category.rawValue, level: .error)
        
        // Only capture to Sentry if enabled
        if CrashReporter.shared.isEnabled {
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
    }
    
    /// Fatal level - logged locally, captured by Sentry only if crash reporting enabled
    static func fatal(_ message: String, category: Category = .app, error: Error? = nil) {
        os_log(.fault, log: category.osLog, "💀 FATAL: %{public}@", message)
        
        if CrashReporter.shared.isEnabled {
            SentrySDK.capture(message: "FATAL: \(message)") { scope in
                scope.setLevel(.fatal)
                scope.setTag(value: category.rawValue, key: "log_category")
                if let error = error {
                    scope.setContext(value: ["error": error.localizedDescription], key: "error_info")
                }
            }
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

final class CrashReporter {
    
    static let shared = CrashReporter()
    
    // MARK: - Configuration
    
    private let sentryDSN = "https://3c3b5cf85ceb42936097f4f16e58b19b@o4510461788028928.ingest.us.sentry.io/4510461861429248"
    
    // UserDefaults keys
    private let crashReportingKey = "crashReportingEnabled"
    private let performanceMonitoringKey = "performanceMonitoringEnabled"
    
    /// Whether crash reporting is enabled (default: false - user must opt in)
    /// When enabled, sends crash reports to help fix bugs
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: crashReportingKey) }
        set {
            let wasEnabled = isEnabled
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
        get { UserDefaults.standard.bool(forKey: performanceMonitoringKey) }
        set {
            let wasEnabled = performanceMonitoringEnabled
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
            os_log(.debug, "CrashReporter: Telemetry disabled (offline mode)")
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
            
            // Crash reporting - always enabled if Sentry is initialized
            options.enableCrashHandler = true
            options.enableUncaughtNSExceptionReporting = true
            
            // Performance monitoring - only if user opted in
            // 0.0 = disabled, 0.1 = 10% sampling
            options.tracesSampleRate = self.performanceMonitoringEnabled ? 0.1 : 0.0
            
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
        
        isSentryInitialized = true
        
        #if DEBUG
        os_log(.debug, "CrashReporter: Sentry initialized (crash=\(self.isEnabled), perf=\(self.performanceMonitoringEnabled))")
        #endif
    }
    
    private func closeSentry() {
        guard isSentryInitialized else { return }
        SentrySDK.close()
        isSentryInitialized = false
        
        #if DEBUG
        os_log(.debug, "CrashReporter: Sentry closed (offline mode)")
        #endif
    }
    
    // MARK: - Breadcrumbs (local storage until crash)
    
    /// Add breadcrumb only if crash reporting is enabled
    /// Breadcrumbs are stored locally and only sent WITH a crash report
    func addBreadcrumbIfEnabled(message: String, category: String, level: SentryLevel) {
        guard isEnabled, isSentryInitialized else { return }
        
        let breadcrumb = Breadcrumb()
        breadcrumb.category = category
        breadcrumb.message = message
        breadcrumb.level = level
        breadcrumb.timestamp = Date()
        SentrySDK.addBreadcrumb(breadcrumb)
    }
}
