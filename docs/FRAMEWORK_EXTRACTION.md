# Extracting MiddleDragCore Framework

## Why

The test target currently compiles source files directly (dual target membership)
because it can't use MiddleDrag.app as a host in CI. This causes Swift 6.2 strict
concurrency checking to enforce `@MainActor` isolation at every call site within
the test target — breaking tests for `MultitouchManager` and `HIDDeviceWatcher`.

A framework target creates a real module boundary. Tests use `@testable import
MiddleDragCore`, which applies cross-module concurrency rules (more lenient for
callers) while still enforcing safety within the framework itself.

## What Goes Where

### MiddleDragCore.framework (new)
Every source file except the app entry point:

```
Core/
  GestureRecognizer.swift
  MouseEventGenerator.swift
  MultitouchFramework.swift
  TouchDeviceProviding.swift
Managers/
  AccessibilityMonitor.swift
  AccessibilityWrappers.swift
  DeviceMonitor.swift
  HIDDeviceWatcher.swift
  MultitouchManager.swift
Models/
  GestureModels.swift
  TouchModels.swift
UI/
  AlertHelper.swift
  MenuBarController.swift
Utilities/
  AnalyticsManager.swift
  LaunchAtLoginManager.swift
  PreferencesManager.swift
  ScreenHelper.swift
  SystemGestureHelper.swift
  UpdateManager.swift
  WindowHelper.swift
```

### MiddleDrag.app (existing, slimmed down)
Only the app entry point and lifecycle:

```
AppDelegate.swift
MiddleDragApp.swift
Info.plist
Assets.xcassets/
MiddleDrag.entitlements
MiddleDragDebug.entitlements
```

### MiddleDragTests → MiddleDragCoreTests (renamed/replaced)
Test files and mocks only — NO source files:

```
MiddleDragCoreTests/
  *Tests.swift
  Mocks/
```

Since the app target only contains thin entry points (`AppDelegate.swift`,
`MiddleDragApp.swift`) with no testable logic, all tests belong to the
framework. When creating the framework target in Step 1, check "Include Tests"
to get a `MiddleDragCoreTests` target with correct linking already set up.

## Step-by-Step

### 1. Create the Framework Target

1. In Xcode: File → New → Target
2. Choose **Framework** (macOS)
3. Name: `MiddleDragCore`
4. Language: Swift
5. ✅ Check **"Include Tests"** — this creates `MiddleDragCoreTests` with
   correct framework linking already configured

### 2. Configure the Framework Target

In MiddleDragCore target → Build Settings:

- **Swift Language Version**: 6.2 (match your app target)
- **Supported Platforms**: macOS
- **macOS Deployment Target**: 15.0 (match your app target)
- **Build Libraries for Distribution**: No (not needed for internal framework)
- **Defines Module**: Yes (should be default)

In Build Settings, search "Swift Compiler - Upcoming Features" and match your
app target's settings (strict concurrency, etc).

Copy any relevant xcconfig settings from `Frameworks/Debug.xcconfig` and
`Frameworks/Release.xcconfig` if they apply to compilation flags.

### 3. Add SPM Dependencies to the Framework

The framework needs Sentry and Sparkle since source files import them.

1. Select the MiddleDragCore framework target
2. General → Frameworks and Libraries → add:
   - `Sentry` (from sentry-cocoa package)
   - `Sparkle` (from Sparkle package)
3. These should already be available as SPM packages in your workspace

### 4. Move Source Files

For each source file listed under "MiddleDragCore.framework" above:

1. Select the file in Xcode's navigator
2. Open File Inspector (right sidebar, first tab)
3. Under **Target Membership**:
   - ✅ Check `MiddleDragCore`
   - ❌ Uncheck `MiddleDrag` (app target)
   - ❌ Uncheck `MiddleDragTests`

Do NOT move `AppDelegate.swift` or `MiddleDragApp.swift` — these stay in the
app target only.

### 5. Fix Access Control

The framework creates a module boundary. Anything the app target or tests need
to access must be `public` or `open` (or `package` if using package access).

**Types and protocols** that need to be `public`:

```swift
// MultitouchManager.swift
public final class MultitouchManager: @unchecked Sendable {
    public static let shared = MultitouchManager()
    public private(set) var isEnabled = false
    public private(set) var isMonitoring = false
    public private(set) var isInThreeFingerGesture = false
    public private(set) var isActivelyDragging = false
    public var configuration = GestureConfiguration()
    public static let restartCleanupDelay: TimeInterval = 0.5
    public static let minimumRestartInterval: TimeInterval = 0.6

    @MainActor public func start() { ... }
    @MainActor public func stop() { ... }
    public func restart() { ... }
    public func toggleEnabled() { ... }
    public func updateConfiguration(_ config: GestureConfiguration) { ... }
    public func forceReleaseStuckDrag() { ... }
}

// GestureModels.swift
public struct GestureConfiguration { ... }
public struct GestureData { ... }
public struct MTPoint { ... }
public enum ModifierKeyType { ... }

// TouchModels.swift
public struct MTTouch { ... }
public struct MTVector { ... }

// GestureRecognizer.swift
public class GestureRecognizer { ... }
public protocol GestureRecognizerDelegate { ... }

// DeviceMonitor.swift
public class DeviceMonitor: TouchDeviceProviding { ... }
public protocol DeviceMonitorDelegate { ... }

// TouchDeviceProviding.swift
public protocol TouchDeviceProviding { ... }

// PreferencesManager.swift
public class PreferencesManager { ... }
public struct UserPreferences { ... }

// MenuBarController.swift
public class MenuBarController { ... }

// AccessibilityMonitor.swift
public class AccessibilityMonitor { ... }

// AnalyticsManager.swift
public enum Log { ... }
public final class CrashReporter { ... }

// LaunchAtLoginManager.swift
public class LaunchAtLoginManager { ... }

// AlertHelper.swift — public static methods
// SystemGestureHelper.swift — public static methods
// UpdateManager.swift — public class
// ScreenHelper.swift — if used by app target
// WindowHelper.swift — if used by app target

// Notification.Name extensions
public extension Notification.Name {
    static let preferencesChanged = ...
    static let launchAtLoginChanged = ...
    static let deviceConnectionStateChanged = ...
}
```

**Approach**: Start by making everything that produces a compiler error `public`.
Build after each batch. The compiler will tell you exactly what's missing.

**Tip**: For types only used within the framework, keep them `internal` (default).
Only promote to `public` what the app target or tests actually reference.

### 6. Update the App Target

1. Add MiddleDragCore as a dependency:
   - Select MiddleDrag app target
   - General → Frameworks and Libraries → add `MiddleDragCore.framework`
   - Set Embed to "Embed & Sign"

2. Remove SPM dependencies from the app target that are now only used by the
   framework (Sentry, Sparkle) — unless AppDelegate also imports them directly.

3. Add import to app files:

```swift
// AppDelegate.swift
import Cocoa
import MiddleDragCore

// MiddleDragApp.swift
import SwiftUI
import MiddleDragCore
```

4. Remove all non-entry-point source files from the app target membership.

### 7. Update the Test Target

1. When creating the framework target (Step 1), check **"Include Tests"**.
   This creates `MiddleDragCoreTests` with the framework already linked.

2. Move all test files and mocks from `MiddleDragTests/` into
   `MiddleDragCoreTests/`.

3. Remove ALL source files from the test target membership. The test target
   should only contain test files and mocks.

4. Update imports in every test file:

```swift
// Before
@testable import MiddleDrag

// After
@testable import MiddleDragCore
```

5. Delete the old `MiddleDragTests` target (and its empty directory) since all
   tests now live in `MiddleDragCoreTests`.

6. Update the scheme: Edit Scheme → Test → remove `MiddleDragTests`, add
   `MiddleDragCoreTests` if not already present.

### 8. Handle Internal Test Access

`@testable import MiddleDragCore` grants access to `internal` members from tests.
This means you generally don't need to make things `public` just for testing.

However, some things that were accessible due to same-module compilation may need
adjustment:

- `fileprivate` members won't be accessible — promote to `internal` if tests
  need them
- `private` members won't be accessible — if tests need them, promote to
  `internal` or test through public interfaces

### 9. Update CI/Build Scripts

If `build.sh` or GitHub Actions workflows reference the scheme or target:

```bash
# Before (if building specific target)
xcodebuild -scheme MiddleDrag -target MiddleDrag build

# After (framework builds automatically as dependency)
# No change needed if building by scheme — Xcode resolves dependencies

# For testing
xcodebuild -scheme MiddleDrag test
# This will build MiddleDragCore → MiddleDrag → MiddleDragTests
```

Check `.github/workflows/build-and-test.yml` for any hardcoded target names
and update `MiddleDragTests` references to `MiddleDragCoreTests`.

### 10. Signing & Notarization

The framework needs the same signing:

1. MiddleDragCore target → Signing & Capabilities
2. Set Team to your Apple Developer Team
3. Set Signing Certificate to "Developer ID Application" (for release)
   or "Sign to Run Locally" (for debug)

For notarization, the framework is embedded inside the app bundle and gets
notarized along with it. No separate notarization step needed.

Check that the app's `_CodeSignature` includes the framework after building:
```bash
codesign --verify --deep --verbose MiddleDrag.app
```

### 11. Verify

Build order to catch errors incrementally:

1. Build MiddleDragCore framework alone (Product → Build)
   - Fix access control errors
2. Build MiddleDrag app (depends on framework)
   - Fix missing imports
3. Build MiddleDragCoreTests
   - Fix `@testable import` references
4. Run MiddleDragCoreTests — all tests should pass
5. Run the app and verify gesture behavior works
6. Run full CI pipeline

## Common Pitfalls

**"Missing required module 'MiddleDragCore'"** in tests
→ The test target doesn't link the framework. If you used "Include Tests" when
  creating the framework target, this should be automatic. Otherwise add it in
  MiddleDragCoreTests → General → Frameworks.

**"Cannot find type X in scope"** in app target
→ The type needs `public` access or you forgot `import MiddleDragCore`.

**"Use of unresolved identifier"** for Notification.Name constants
→ The extension defining `.preferencesChanged` etc. needs `public`.

**Tests fail with `@MainActor` errors after migration**
→ This is the whole point — verify that `@testable import` resolved it.
   If tests still fail, a file accidentally has dual target membership.
   Check File Inspector → Target Membership for the offending file.

**App crashes at launch after migration**
→ Check that the framework is embedded ("Embed & Sign" not "Do Not Embed").
   An unembedded framework causes a dylib-not-found crash.

**Sentry/Sparkle symbols not found**
→ These dependencies need to be linked to MiddleDragCore, not the app target.
   The app gets them transitively through the framework.

## Rollback Plan

If things go sideways, `git stash` or `git checkout .` reverts everything.
Do this work on a branch (`git checkout -b refactor/framework-extraction`).
