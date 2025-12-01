# GEMINI.md

## Project Overview

This project, **MiddleDrag**, is a macOS menu bar application written in Swift. Its primary purpose is to provide middle-click and middle-drag functionality using three-finger gestures on a MacBook trackpad or an external Magic Trackpad.

The application captures raw touch data from the trackpad using Apple's private `MultitouchSupport.framework`. A custom `GestureRecognizer` processes this data to identify three-finger taps (for middle-clicks) and three-finger drags (for panning in applications like CAD software or 3D modeling tools).

To execute the mouse events, it uses the Accessibility API (`CoreGraphics`). A `CGEventTap` is implemented to intercept and suppress conflicting, system-generated mouse events that might otherwise interfere with the app's functionality.

The application has no main window and runs entirely from the menu bar, where users can enable/disable it, adjust settings, and configure it to launch at login.

## Building and Running

The project can be built using either Xcode or the provided shell script.

### Prerequisites

*   Xcode 15.0 or later
*   macOS 14.0 SDK or later

### Build via Shell Script

The `build.sh` script handles the build process and links the required private framework.

**Build for Release:**
```bash
./build.sh
```
The final `MiddleDrag.app` will be located in the `build/` directory and the script will offer to copy it to `/Applications`.

**Build and Run for Debugging:**
```bash
./build.sh --debug --run
```
This command builds the debug configuration and immediately launches the application, showing live console output.

### Build via Xcode

1.  Open `MiddleDrag.xcodeproj` in Xcode.
2.  Select your development team in the "Signing & Capabilities" section of the project settings.
3.  Build and run the project using the `⌘R` shortcut.

## Development Conventions

*   **Architecture:** The app follows a manager-based architecture. A central `MultitouchManager` coordinates various components.
*   **Core Logic:** Gesture detection is isolated in `Core/GestureRecognizer.swift`, which uses a delegate pattern to communicate events.
*   **UI:** The UI is minimal and managed by `UI/MenuBarController.swift`.
*   **Dependencies:** The project relies on a private Apple framework (`MultitouchSupport`) which is linked at build time.
*   **Asynchronous Operations:** Gesture processing is performed on a background GCD queue (`com.middledrag.gesture`) to keep the main thread responsive.
*   **Settings:** User preferences are managed by `PreferencesManager.swift` and stored in `UserDefaults`.
