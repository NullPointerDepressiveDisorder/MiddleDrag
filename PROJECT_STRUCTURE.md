# MiddleDrag Project Structure

## Refactored Architecture

The project has been refactored from two large files into a modular, maintainable structure:

```
MiddleDrag/
├── Core/                               # Core functionality
│   ├── MultitouchFramework.swift           # Private API bindings and framework management
│   ├── GestureRecognizer.swift             # Gesture detection and state management
│   ├── MouseEventGenerator.swift           # Mouse event generation and cursor control
│   └── TouchDeviceProviding.swift          # Protocol for device monitoring/dependency injection
│
├── Models/                             # Data models
│   ├── TouchModels.swift                   # Touch data structures (MTPoint, MTTouch, etc.)
│   └── GestureModels.swift                 # Gesture state and configuration models
│
├── Managers/                           # Business logic managers
│   ├── MultitouchManager.swift             # Main coordinator for gesture system
│   ├── DeviceMonitor.swift                 # Device monitoring and callback management
│   ├── AccessibilityMonitor.swift          # Accessibility permission polling and app handling
│   └── AccessibilityWrappers.swift         # Wrappers for accessibility system APIs (testability)
│
├── UI/                                 # User interface
│   ├── MenuBarController.swift             # Menu bar UI management
│   └── AlertHelper.swift                   # Alert dialogs and user notifications
│
├── Utilities/                          # Helper utilities
│   ├── PreferencesManager.swift            # User preferences persistence
│   ├── LaunchAtLoginManager.swift          # Launch at login functionality
│   ├── AnalyticsManager.swift              # Analytics and telemetry management
│   ├── ScreenHelper.swift                  # Multi-monitor screen coordinate handling
│   ├── SystemGestureHelper.swift           # System trackpad settings and process management
│   ├── UpdateManager.swift                 # App updates via Sparkle framework
│   └── WindowHelper.swift                  # Window detection under cursor
│
├── MiddleDragApp.swift                 # SwiftUI app entry point
├── AppDelegate.swift                   # Application delegate
├── Info.plist                          # App configuration
└── MiddleDrag.entitlements             # App entitlements
│
MiddleDragTests/                        # Unit test target
├── GestureModelsTests.swift                # Tests for gesture models
├── GestureRecognizerTests.swift            # Tests for gesture recognition logic
├── TouchModelsTests.swift                  # Tests for touch data structures
├── MouseEventGeneratorTests.swift          # Tests for mouse event generation
├── MultitouchFrameworkTests.swift          # Tests for multitouch framework bindings
├── MultitouchManagerTests.swift            # Tests for main coordinator
├── DeviceMonitorTests.swift                # Tests for device monitoring
├── AccessibilityMonitorTests.swift         # Tests for accessibility permissions
├── MenuBarControllerTests.swift            # Tests for menu bar UI
├── AlertHelperTests.swift                  # Tests for alert dialogs
├── PreferencesManagerTests.swift           # Tests for preferences persistence
├── LaunchAtLoginManagerTests.swift         # Tests for launch at login
├── AnalyticsManagerTests.swift             # Tests for analytics
├── ScreenHelperTests.swift                 # Tests for screen coordinate handling
├── SystemGestureHelperTests.swift          # Tests for system gesture settings
├── WindowHelperTests.swift                 # Tests for window detection
└── Mocks/                                  # Mock objects for testing
    └── MockDeviceMonitor.swift             # Mock device monitor
│
.github/                                # GitHub configuration
├── workflows/                              # CI/CD workflows
│   └── *.yml                               # GitHub Actions workflow files
├── ISSUE_TEMPLATE/                         # Issue templates
│
Root Files:
├── README.md                           # Project documentation
├── PROJECT_STRUCTURE.md                # This file
├── LICENSE                             # MIT License
├── CODE_OF_CONDUCT.md                  # Community guidelines
├── CONTRIBUTING.md                     # Contribution guide
├── SECURITY.md                         # Security policy
├── build.sh                            # Build automation script
├── bump-version.sh                     # Version bump script
├── codecov.yml                         # Codecov configuration
└── .gitignore                          # Git ignore rules
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

### 4. **Maintainability**
- Easy to locate specific functionality
- Reduced file sizes (no more 500+ line files)
- Logical grouping of related code

### 5. **Extensibility**
- Easy to add new gesture types
- Simple to support new device types
- UI can be extended without touching core logic

## Component Responsibilities

### Core Layer
- **MultitouchFramework**: Interfaces with private Apple framework
- **GestureRecognizer**: Converts touch data into gestures
- **MouseEventGenerator**: Handles all mouse event synthesis
- **TouchDeviceProviding**: Protocol for device monitoring and dependency injection

### Model Layer
- **TouchModels**: Raw touch data structures
- **GestureModels**: Application state and configuration

### Manager Layer
- **MultitouchManager**: Main coordinator, implements business logic
- **DeviceMonitor**: Manages device lifecycle and callbacks
- **AccessibilityMonitor**: Manages accessibility permission polling and app handling
- **AccessibilityWrappers**: Wrappers for system accessibility APIs (enables testability)

### UI Layer
- **MenuBarController**: All menu bar UI logic
- **AlertHelper**: Centralized alert management

### Utility Layer
- **PreferencesManager**: UserDefaults persistence
- **LaunchAtLoginManager**: System integration for auto-launch
- **AnalyticsManager**: Analytics and telemetry management
- **ScreenHelper**: Multi-monitor screen coordinate conversion (Cocoa ↔ Quartz)
- **SystemGestureHelper**: Trackpad settings and process management for testing
- **UpdateManager**: App updates via Sparkle framework (offline by default)
- **WindowHelper**: Detects window information under the cursor

### Test Layer
- Comprehensive unit tests for all components
- Mock objects for isolated testing
- Tests for gesture recognition, touch models, and UI components

## Design Patterns Used

1. **Delegate Pattern**: For loose coupling between components
2. **Singleton Pattern**: For shared managers (with care)
3. **Observer Pattern**: Using NotificationCenter for preferences
4. **Factory Pattern**: Device creation in MultitouchFramework
5. **Strategy Pattern**: Configurable gesture recognition
6. **Protocol-Oriented Design**: For dependency injection and testability

## Adding New Features

To add a new feature, identify which layer it belongs to:

1. **New gesture type?** → Modify GestureRecognizer
2. **New mouse action?** → Extend MouseEventGenerator
3. **New preference?** → Update PreferencesManager and GestureModels
4. **New menu item?** → Add to MenuBarController
5. **New device support?** → Extend DeviceMonitor
6. **New test?** → Add to MiddleDragTests target
7. **Accessibility feature?** → Update AccessibilityMonitor
8. **Multi-monitor handling?** → Update ScreenHelper

## Dependencies

The refactored code maintains minimal dependencies:
- No external Swift packages required (except Sparkle for updates and Sentry for analytics/error reporting)
- Uses only system frameworks
- Private framework access isolated to one file

## CI/CD Infrastructure

- **GitHub Actions**: Automated build, test, and release workflows
- **Codecov**: Code coverage reporting and tracking
- **Build Scripts**: `build.sh` for local builds, `bump-version.sh` for version management
