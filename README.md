# MiddleDrag

A macOS menu bar app that enables middle-click and middle-drag functionality using three-finger trackpad gestures.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Three-finger tap** → Middle mouse click
- **Three-finger drag** → Middle mouse drag (for panning in apps like Blender, CAD software, browsers, etc.)
- Works alongside system trackpad gestures without interference
- Configurable sensitivity and smoothing
- Menu bar icon with quick access to settings
- Launch at login support

## Requirements

- macOS 14.0 (Sonoma) or later
- Built-in trackpad or Magic Trackpad
- Accessibility permissions (required for mouse event generation)

## Installation

1. Download the latest release from the Releases page
2. Move `MiddleDrag.app` to your Applications folder
3. Launch the app
4. Grant Accessibility permissions when prompted (System Settings → Privacy & Security → Accessibility)

## Usage

Once running, MiddleDrag appears as a hand icon in your menu bar:

- **Three-finger tap**: Performs a middle mouse click (useful for opening links in new tabs, closing tabs, etc.)
- **Three-finger drag**: Performs a middle mouse drag (useful for panning/orbiting in 3D applications)

### Menu Bar Options

- **Enabled**: Toggle gesture recognition on/off
- **Drag Sensitivity**: Adjust how fast the cursor moves during drag (0.5x - 2x)
- **Advanced**:
  - Require Exactly 3 Fingers: Only recognize gestures with exactly 3 fingers
  - Block System Gestures: Attempt to prevent system gesture interference
- **Launch at Login**: Start MiddleDrag automatically when you log in

## How It Works

MiddleDrag uses Apple's private MultitouchSupport framework to receive raw touch data from the trackpad before it's processed by the system gesture recognizer. This allows it to:

1. Detect three-finger gestures independently
2. Generate synthetic middle mouse events via the Accessibility API
3. Suppress conflicting system-generated click events using a CGEventTap

## Building from Source

### Prerequisites

- Xcode 15.0 or later
- macOS 14.0 SDK or later

### Build

```bash
# Clone the repository
git clone https://github.com/yourusername/MiddleDrag.git
cd MiddleDrag

# Build release version
./build.sh

# Or build and run debug version
./build.sh --debug --run
```

### Xcode

1. Open `MiddleDrag.xcodeproj`
2. Select your signing team in project settings
3. Build and run (⌘R)

## Project Structure

```
MiddleDrag/
├── Core/
│   ├── GestureRecognizer.swift    # Gesture detection logic
│   ├── MouseEventGenerator.swift  # Mouse event synthesis
│   └── MultitouchFramework.swift  # Private API bindings
├── Managers/
│   ├── DeviceMonitor.swift        # Trackpad monitoring
│   └── MultitouchManager.swift    # Main coordinator
├── Models/
│   ├── GestureModels.swift        # Configuration types
│   └── TouchModels.swift          # Touch data structures
├── UI/
│   ├── AlertHelper.swift          # Dialog utilities
│   └── MenuBarController.swift    # Menu bar interface
└── Utilities/
    ├── LaunchAtLoginManager.swift # Login item management
    └── PreferencesManager.swift   # Settings persistence
```

## Compatibility

| macOS Version | Status |
|--------------|--------|
| macOS 14 (Sonoma) | ✅ Fully supported |
| macOS 15 (Sequoia) | ✅ Fully supported |
| macOS 26 beta (Tahoe) | ✅ Compatible |

Works with both built-in MacBook trackpads and external Magic Trackpads.

## Known Limitations

- Requires Accessibility permissions to generate mouse events
- Physical trackpad clicks (pressing down) with 3 fingers may still trigger system gestures - soft taps work best
- Some applications may not respond to synthetic middle mouse events

## Troubleshooting

### App doesn't respond to gestures
1. Check that Accessibility permissions are granted in System Settings
2. Try toggling the "Enabled" option in the menu bar
3. Restart the app

### Gestures conflict with system gestures
1. Use soft taps instead of physical clicks
2. Adjust your trackpad settings in System Settings if needed

### Menu bar icon shows disabled (slash through hand)
1. Check Accessibility permissions
2. Toggle "Enabled" in the menu

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by the need for middle-click functionality on macOS trackpads
- Uses the MultitouchSupport private framework for raw touch access
