import ServiceManagement
import Cocoa

// MARK: - Protocol

/// Protocol for managing login items
protocol LoginItemServiceProtocol {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

// MARK: - Implementation

/// Wrapper around SMAppService
@available(macOS 13.0, *)
class SystemLoginItemService: LoginItemServiceProtocol {

    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        return service.status == .enabled
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

// MARK: - Manager

/// Manages launch at login functionality
class LaunchAtLoginManager {
    
    static let shared = LaunchAtLoginManager()
    
    // Injected dependency
    private let service: LoginItemServiceProtocol?

    private init() {
        if #available(macOS 13.0, *) {
            self.service = SystemLoginItemService()
        } else {
            self.service = nil
        }
    }

    // Testable init
    init(service: LoginItemServiceProtocol) {
        self.service = service
    }
    
    /// Configure launch at login
    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            configureLaunchAtLoginModern(enabled)
        } else {
            configureLaunchAtLoginLegacy(enabled)
        }
    }
    
    @available(macOS 13.0, *)
    private func configureLaunchAtLoginModern(_ enabled: Bool) {
        guard let service = service else { return }

        do {
            if enabled {
                try service.register()
                Log.info("Launch at login enabled", category: .app)
            } else {
                try service.unregister()
                Log.info("Launch at login disabled", category: .app)
            }
        } catch {
            Log.error("Failed to configure launch at login: \(error.localizedDescription)", category: .app, error: error)
        }
    }
    
    private func configureLaunchAtLoginLegacy(_ enabled: Bool) {
        // For older macOS versions, we would use LSSharedFileList
        // or SMLoginItemSetEnabled, but these are deprecated
        Log.warning("Launch at login not available on macOS < 13.0", category: .app)
    }
    
    /// Check if launch at login is enabled
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return service?.isEnabled ?? false
        } else {
            return false
        }
    }
}
