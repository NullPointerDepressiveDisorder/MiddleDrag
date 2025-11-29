# MiddleDrag

A macOS menu bar app that enables middle-click and middle-drag functionality using three-finger trackpad gestures.

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

1. Clone the repository
2. Open `MiddleDrag.xcodeproj` in Xcode
3. Build and run (⌘R)

### Debug Build

For development with console output:

```bash
./build.sh --debug --run
```

## Compatibility

- Tested on macOS 14 (Sonoma) and macOS 15 (Sequoia)
- Compatible with macOS 26 beta (Tahoe) with adjusted API usage
- Works with both built-in MacBook trackpads and external Magic Trackpads

## Known Limitations

- Requires Accessibility permissions to generate mouse events
- Physical trackpad clicks with 3 fingers may still trigger system gestures (soft taps work best)
- Some applications may not respond to synthetic middle mouse events

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Inspired by the need for middle-click functionality on macOS trackpads
- Uses the MultitouchSupport private framework for raw touch access
