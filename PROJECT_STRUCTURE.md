# MiddleDrag Project Structure

## Refactored Architecture

The project has been refactored from two large files into a modular, maintainable structure:

```
MiddleDrag/
├── Core/                           # Core functionality
│   ├── MultitouchFramework.swift       # Private API bindings and framework management
│   ├── GestureRecognizer.swift         # Gesture detection and state management
│   ├── MouseEventGenerator.swift       # Mouse event generation and cursor control
│   └── TouchDeviceProviding.swift      # Protocol for touch device abstraction
│
├── Models/                         # Data models
│   ├── TouchModels.swift               # Touch data structures (MTPoint, MTTouch, etc.)
│   └── GestureModels.swift             # Gesture state and configuration models
│
├── Managers/                       # Business logic managers
│   ├── MultitouchManager.swift         # Main coordinator for gesture system
│   ├── DeviceMonitor.swift             # Device monitoring and callback management
│   ├── AccessibilityMonitor.swift      # Monitors accessibility permission state
│   └── AccessibilityWrappers.swift     # Wrappers for accessibility API interactions
│
├── UI/                             # User interface
│   ├── MenuBarController.swift         # Menu bar UI management
│   └── AlertHelper.swift               # Alert dialogs and user notifications
│
├── Utilities/                      # Helper utilities
│   ├── PreferencesManager.swift        # User preferences persistence
│   ├── LaunchAtLoginManager.swift      # Launch at login functionality
│   ├── AnalyticsManager.swift          # Analytics and telemetry management
│   ├── ScreenHelper.swift              # Screen and display utilities
│   ├── SystemGestureHelper.swift       # System gesture coordination
│   ├── UpdateManager.swift             # Handles Sparkle auto-updates
│   └── WindowHelper.swift              # Window management utilities
│
├── MiddleDragApp.swift             # SwiftUI app entry point
├── AppDelegate.swift               # Application delegate
├── Info.plist                      # App configuration
└── MiddleDrag.entitlements         # App entitlements

├── MiddleDragTests/                # Unit test target
│   ├── AccessibilityMonitorTests.swift     # Tests for accessibility monitor
│   ├── AlertHelperTests.swift              # Tests for alert helper
│   ├── AnalyticsManagerTests.swift         # Tests for analytics manager
│   ├── DeviceMonitorTests.swift            # Tests for device monitoring
│   ├── GestureModelsTests.swift            # Tests for gesture models
│   ├── GestureRecognizerTests.swift        # Tests for gesture recognition logic
│   ├── LaunchAtLoginManagerTests.swift     # Tests for launch at login
│   ├── MenuBarControllerTests.swift        # Tests for menu bar controller
│   ├── MouseEventGeneratorTests.swift      # Tests for mouse event generation
│   ├── MultitouchFrameworkTests.swift      # Tests for multitouch framework
│   ├── MultitouchManagerTests.swift        # Tests for multitouch manager
│   ├── PreferencesManagerTests.swift       # Tests for preferences manager
│   ├── ScreenHelperTests.swift             # Tests for screen helper
│   ├── SystemGestureHelperTests.swift      # Tests for system gesture helper
│   ├── TouchModelsTests.swift              # Tests for touch data structures
│   ├── WindowHelperTests.swift             # Tests for window helper
│   └── Mocks/                              # Mock objects for testing
│       └── MockDeviceMonitor.swift         # Mock device monitor for tests
│
.github/                            # GitHub configuration
├── workflows/                          # CI/CD workflows
│   └── *.yml                           # GitHub Actions workflow files
└── ISSUE_TEMPLATE/                     # Issue templates

Root Files:
├── README.md                       # Project documentation
├── PROJECT_STRUCTURE.md            # This file
├── LICENSE                         # MIT License
├── CODE_OF_CONDUCT.md              # Community guidelines
├── CONTRIBUTING.md                 # Contribution guide
├── SECURITY.md                     # Security policy
├── build.sh                        # Build automation script
├── bump-version.sh                 # Version bump script
├── codecov.yml                     # Codecov configuration
└── .gitignore                      # Git ignore rules
```

## Architecture Benefits

### 1. **Separation of Concerns**
- Each class has a single, well-defined responsibility
- Easy to understand and modify individual components
- Clear boundaries between layers

### 2. **Modular Design**
- Core functionality separated from UI
- Models independent of implementation
- Managers coordinate between components

### 3. **Testability**
- Each component can be tested in isolation
- Mock delegates and protocols for testing
- Clear interfaces between modules
- Comprehensive test coverage with 17 test files

### 4. **Maintainability**
- Easy to locate specific functionality
- Reduced file sizes (no more 500+ line files)
- Logical grouping of related code
