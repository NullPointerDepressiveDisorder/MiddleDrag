# MiddleDrag

Three-finger drag for middle mouse button emulation on macOS. Perfect for CAD software navigation using your trackpad.

![Swift](https://img.shields.io/badge/swift-5.0-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2011.0%2B-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Features

- 🖱️ **Three-finger drag** → Middle mouse drag (perfect for CAD orbit/pan)
- 👆 **Three-finger tap** → Middle mouse click
- ⚡ **Adjustable sensitivity** for precision or speed
- 🎯 **Minimal CPU usage** with native multitouch framework
- 📊 **Menu bar control** for easy enable/disable
- 🚀 **Launch at login** support

## Why MiddleDrag?

Most CAD software (Fusion 360, AutoCAD, SolidWorks, Blender) relies heavily on middle mouse button for navigation. Mac trackpads don't have a middle button, forcing users to use awkward keyboard modifiers or external mice. MiddleDrag solves this by converting three-finger gestures into middle mouse events.

## Installation

### Option 1: Download Release
1. Download the latest release from [Releases](https://github.com/yourusername/MiddleDrag/releases)
2. Move `MiddleDrag.app` to your Applications folder
3. Launch MiddleDrag
4. Grant accessibility permissions when prompted

### Option 2: Build from Source
```bash
# Clone the repository
git clone https://github.com/yourusername/MiddleDrag.git
cd MiddleDrag

# Build with Xcode
xcodebuild -project MiddleDrag.xcodeproj -scheme MiddleDrag -configuration Release build

# Or build directly with Swift
./build.sh
```

## Setup

### 1. Disable Conflicting System Gestures

MiddleDrag needs exclusive access to three-finger gestures. Disable these in System Settings:

1. Open **System Settings → Trackpad → More Gestures**
2. Change these settings:
   - **Swipe between apps**: Set to "Swipe with Four Fingers" or disable
   - **Mission Control**: Set to "Swipe Up with Four Fingers" or disable
   - **App Exposé**: Set to "Swipe Down with Four Fingers" or disable

### 2. Grant Accessibility Permissions

MiddleDrag needs accessibility permissions to simulate mouse events:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the lock to make changes
3. Add MiddleDrag to the list and enable it
4. Restart MiddleDrag

## Usage

Once running, MiddleDrag appears in your menu bar:

- **Three fingers on trackpad + drag** → Middle mouse drag
- **Three-finger tap** → Middle mouse click
- Click the menu bar icon to:
  - Toggle enabled/disabled
  - Adjust drag sensitivity
  - Set to launch at login
  - Access settings

### Sensitivity Settings

- **Low (Precision)**: Slower, more precise movement for detailed work
- **Medium**: Balanced for general use (default)
- **High (Fast)**: Faster movement for quick navigation

## Supported Software

Tested and working with:
- Fusion 360
- AutoCAD
- SolidWorks
- Blender
- Rhino
- SketchUp
- FreeCAD
- OnShape
- Inventor
- CATIA
- Siemens NX

## Technical Details

MiddleDrag uses Apple's private `MultitouchSupport.framework` to access raw trackpad data before macOS processes system gestures. This allows detecting three-finger touches even when Mission Control gestures are enabled.

**Note**: Because this uses a private framework:
- Cannot be distributed via Mac App Store
- Requires disabling App Sandbox
- May need updates for future macOS versions

## Troubleshooting

### Three-finger drag not working
1. Ensure system three-finger gestures are disabled (see Setup)
2. Check accessibility permissions are granted
3. Try restarting MiddleDrag

### Conflicts with other apps
- Disable BetterTouchTool's three-finger gestures
- Close other trackpad utilities while using MiddleDrag

### Performance issues
- Adjust sensitivity to a lower setting
- Check Activity Monitor for high CPU usage
- Report issues with your Mac model and macOS version

## Building from Source

### Requirements
- macOS 11.0+
- Xcode 13+ or Swift 5.5+
- Developer certificate (for signing)

### Build Instructions

```bash
# Clone repository
git clone https://github.com/yourusername/MiddleDrag.git
cd MiddleDrag

# Open in Xcode
open MiddleDrag.xcodeproj

# Or build from command line
xcodebuild -project MiddleDrag.xcodeproj \
           -scheme MiddleDrag \
           -configuration Release \
           -derivedDataPath build \
           PRODUCT_BUNDLE_IDENTIFIER="com.yourname.MiddleDrag" \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO

# Find built app
find build -name "MiddleDrag.app"
```

### Framework Search Paths
Add to build settings:
- Framework Search Paths: `/System/Library/PrivateFrameworks`
- Other Linker Flags: `-framework MultitouchSupport -framework CoreFoundation`

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Ideas

- [ ] Custom gesture patterns (two-finger middle click, etc.)
- [ ] Per-application profiles
- [ ] Gesture visualization overlay
- [ ] Force Touch support for pressure-sensitive dragging
- [ ] Windows/Linux versions using similar techniques

## License

MIT License - see [LICENSE](LICENSE) file for details

## Acknowledgments

- [Ryan Hanson's](https://medium.com/ryan-hanson/touching-apples-private-multitouch-framework-64f87611cfc9) research on MultitouchSupport.framework
- [M5MultitouchSupport](https://github.com/mhuusko5/M5MultitouchSupport) for framework documentation
- [MiddleClick](https://github.com/artginzburg/MiddleClick) for inspiration
- The CAD community for feedback and testing

## Disclaimer

This software uses private Apple frameworks and is provided as-is. It may stop working with future macOS updates. Use at your own risk.

---

**Made with ❤️ for engineers, designers, and makers who want to use their Mac trackpad with CAD software.**
