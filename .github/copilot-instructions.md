# Copilot Coding Agent Instructions for MiddleDrag

## Repository Overview

**MiddleDrag** is a macOS menu bar app that enables middle-click and middle-drag functionality using three-finger trackpad gestures. It converts three-finger taps into middle mouse clicks and three-finger drags into middle mouse drags for use in 3D/CAD applications like Blender and Fusion 360.

- **Language**: Swift 5.0+
- **Platform**: macOS 15.0+ (Sequoia)
- **Framework**: SwiftUI + AppKit (menu bar app)
- **Build Tool**: Xcode 16.0+ / xcodebuild
- **Size**: Small (~15 Swift source files)
- **Dependencies**: Sentry (crash reporting), SimpleAnalytics (anonymous usage)

## Build Instructions

> **IMPORTANT**: This is a macOS-only project. It requires macOS with Xcode installed and cannot be built on Linux.

### CI Build Command (GitHub Actions)
The CI workflow (`objective-c-xcode.yml`) runs on `macos-15` runners:
```bash
xcodebuild -scheme MiddleDrag \
  -project MiddleDrag.xcodeproj \
  -configuration Release \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Local Build (macOS Only)
**Always use the build script for local development:**
```bash
# Release build
./build.sh

# Debug build and run
./build.sh --debug --run
```

The build script handles:
- Private framework linking (`MultitouchSupport`)
- Code signing setup
- Architecture detection

### Build Output Location
- `build/` directory (created by build.sh)
- `~/Library/Developer/Xcode/DerivedData/` (when building with Xcode)

## Project Structure

```
MiddleDrag/
├── MiddleDrag/                      # Main app source code
│   ├── MiddleDragApp.swift          # @main entry point (SwiftUI)
│   ├── AppDelegate.swift            # Application lifecycle
│   ├── Info.plist                   # App configuration
│   ├── MiddleDrag.entitlements      # App entitlements (sandbox disabled)
│   ├── Core/                        # Core gesture/mouse functionality
│   │   ├── GestureRecognizer.swift  # Gesture detection state machine
│   │   ├── MouseEventGenerator.swift # Mouse event synthesis
│   │   └── MultitouchFramework.swift # Private API bindings
│   ├── Managers/                    # Business logic coordinators
│   │   ├── MultitouchManager.swift  # Main coordinator (shared singleton)
│   │   └── DeviceMonitor.swift      # Trackpad device monitoring
│   ├── Models/                      # Data structures
│   │   ├── GestureModels.swift      # GestureState, GestureConfiguration, UserPreferences
│   │   └── TouchModels.swift        # MTPoint, MTTouch structures
│   ├── UI/                          # User interface
│   │   ├── MenuBarController.swift  # NSStatusItem menu bar
│   │   └── AlertHelper.swift        # NSAlert dialogs
│   └── Utilities/                   # Helpers
│       ├── PreferencesManager.swift   # UserDefaults persistence
│       ├── LaunchAtLoginManager.swift # Login item management
│       └── AnalyticsManager.swift     # Sentry + SimpleAnalytics
├── MiddleDrag.xcodeproj/            # Xcode project
├── build.sh                         # Primary build script
├── run-debug.sh                     # Run debug build from DerivedData
└── setup-debug.sh                   # Debug environment setup
```

## CI/CD Workflows

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| Build | `objective-c-xcode.yml` | Push/PR to `main` | Validates build compiles |
| Release | `release.yml` | Tag `v*` or manual | Creates GitHub release with ZIP |
| Homebrew | `update-homebrew.yml` | Release published | Updates homebrew tap |

**CI runs on `macos-15` runners.** Changes that break the build will fail CI.

## Key Implementation Details

### Private Framework Access
The app uses Apple's private `MultitouchSupport.framework` for raw trackpad touch data. Bindings are in `Core/MultitouchFramework.swift` using `@_silgen_name`.

### Code Signing
- Development: Ad-hoc signing (`CODE_SIGN_IDENTITY="-"`)
- CI: No code signing (`CODE_SIGNING_REQUIRED=NO`)
- App requires Accessibility permissions at runtime

### Swift Package Dependencies
Defined in `project.pbxproj`:
- `sentry-cocoa` (v9.0.0+) - Crash reporting
- `simpleanalytics/swift-package` (v0.4.1+) - Anonymous analytics

## Code Conventions

- **Naming**: Swift standard (camelCase for variables, PascalCase for types)
- **MARK comments**: Use `// MARK: -` for section organization
- **Singletons**: `MultitouchManager.shared`, `PreferencesManager.shared`, etc.
- **Notifications**: Use `NotificationCenter` with custom `Notification.Name` extensions
- **Preferences**: Stored in `UserPreferences` struct, persisted via `PreferencesManager`

## Testing Notes

- **No automated tests** exist in this repository
- **Manual testing required**: Test on actual macOS hardware with trackpad
- Testing requires Accessibility permissions granted in System Settings

## Adding New Features

| Feature Type | Location |
|-------------|----------|
| New gesture | `Core/GestureRecognizer.swift` |
| New mouse action | `Core/MouseEventGenerator.swift` |
| New preference | `Models/GestureModels.swift` (UserPreferences) + `UI/MenuBarController.swift` |
| New menu item | `UI/MenuBarController.swift` |
| New device support | `Managers/DeviceMonitor.swift` |

## Trust These Instructions

These instructions have been validated against the actual repository. Trust them unless you encounter:
- Build errors with specific messages not covered here
- Missing files referenced in this document
- Outdated version requirements

Only search the codebase if these instructions are incomplete or produce errors.
