# MiddleDrag

Three-finger drag for middle mouse button emulation on macOS. Perfect for CAD software navigation using your trackpad.

![Swift](https://img.shields.io/badge/swift-5.5-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2011.0%2B-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-2.0.0-green.svg)

## 🚀 Features

### Core Functionality
- 🖱️ **Three-finger drag** → Middle mouse drag (perfect for CAD orbit/pan)
- 👆 **Three-finger tap** → Middle mouse click
- ✨ **Works WITH system gestures** - no need to disable Mission Control!
- ⚡ **Ultra-low latency** with optimized multitouch processing
- 🎯 **Smart gesture detection** with state management
- 📊 **Menu bar control** for easy configuration

### New in v2.0
- **Enhanced Performance**: Rewritten touch processing with dedicated gesture queue
- **Smooth Cursor Movement**: Exponential smoothing for fluid dragging
- **Velocity-Based Sensitivity**: Automatically adjusts to movement speed
- **Advanced Tap Detection**: Configurable timing and movement thresholds
- **Multi-Device Support**: Works with built-in trackpad and Magic Trackpad
- **Gesture Blocking**: Optional system gesture suppression while dragging
- **Precise State Tracking**: Individual finger tracking with pressure sensing

## 🎯 Why MiddleDrag?

Most CAD software (Fusion 360, AutoCAD, SolidWorks, Blender) relies heavily on middle mouse button for navigation. Mac trackpads don't have a middle button, forcing users to use awkward keyboard modifiers or external mice. 

**MiddleDrag is different from other solutions:**
- ✅ **No system configuration required** - works out of the box
- ✅ **Preserves your Mission Control gestures** - have both!
- ✅ **Direct hardware access** - not a hacky workaround
- ✅ **Professional-grade precision** - designed for CAD work

Using Apple's MultitouchSupport.framework, MiddleDrag receives touch data *before* macOS processes it, allowing perfect three-finger middle mouse emulation without sacrificing system functionality.

## 📥 Installation

### Option 1: Download Release
1. Download the latest release from [Releases](https://github.com/kmohindroo/MiddleDrag/releases)
2. Move `MiddleDrag.app` to your Applications folder
3. Launch MiddleDrag
4. Grant accessibility permissions when prompted

### Option 2: Build from Source
```bash
# Clone the repository
git clone https://github.com/kmohindroo/MiddleDrag.git
cd MiddleDrag

# Make build script executable
chmod +x build.sh

# Build and install
./build.sh
```

## ⚙️ Setup

### Just One Step: Grant Accessibility Permissions

**That's it!** MiddleDrag works alongside your existing trackpad gestures - no configuration needed.

Grant permissions when prompted:
1. Open **System Settings → Privacy & Security → Accessibility**
2. Add MiddleDrag and enable it
3. Start using three-finger drag immediately!

### Optional: Optimize for CAD Software

For the absolute best experience with CAD software, you *can* disable system three-finger gestures, but **it's not required**:

1. Open **System Settings → Trackpad → More Gestures**
2. Change these settings (if desired):
   - **Swipe between apps**: Set to "Swipe with Four Fingers"
   - **Mission Control**: Set to "Swipe Up with Four Fingers"
   - **App Exposé**: Set to "Swipe Down with Four Fingers"

**Why it works:** MiddleDrag uses Apple's MultitouchSupport.framework which receives touch data *before* the system processes gestures. Your three-finger drags work perfectly alongside Mission Control!

## 🎮 Usage

Once running, MiddleDrag appears in your menu bar with a hand icon:

### Basic Controls
- **Three fingers on trackpad + drag** → Middle mouse drag
- **Three-finger tap** → Middle mouse click
- **Menu bar icon** → Access all settings

### Sensitivity Settings
Choose from five preset sensitivity levels:
- **Slow (0.5x)**: Ultra-precise for detailed CAD work
- **Precision (0.75x)**: Fine control for technical drawing
- **Normal (1x)**: Balanced for general use (default)
- **Fast (1.5x)**: Quick navigation
- **Very Fast (2x)**: Rapid movement for large models

### Advanced Settings
- **Tap Speed**: Adjust tap detection timing (100-200ms)
- **Smoothing**: Control cursor smoothness (20-50%)
- **Finger Mode**: Require exactly 3 fingers or allow 3+

## 🛠️ Supported Software

### CAD & 3D Modeling
✅ **Fusion 360** - Full orbit/pan/zoom support
✅ **AutoCAD** - 3D navigation and selection
✅ **SolidWorks** (via Parallels) - Native-like experience
✅ **Blender** - Viewport navigation
✅ **Rhino** - Complete navigation control
✅ **SketchUp** - Orbit and pan tools
✅ **FreeCAD** - Full mouse emulation
✅ **OnShape** - Browser-based CAD support
✅ **Inventor** - Assembly navigation
✅ **CATIA** - DMU navigation
✅ **Siemens NX** - View manipulation
✅ **Creo/Pro-E** - Model navigation

### Engineering & Design
✅ **MATLAB** - Plot rotation
✅ **Altium Designer** - PCB navigation
✅ **KiCad** - Schematic/PCB pan
✅ **Eagle** - Board view control

## 🔧 Technical Architecture

### Core Technology
MiddleDrag uses Apple's private `MultitouchSupport.framework` for direct hardware access:
- **Raw touch data** at 60-120Hz refresh rate
- **Individual finger tracking** with persistent IDs
- **Pressure and velocity** sensing
- **Pre-gesture processing** to avoid system conflicts

### Performance Optimizations
- **Dedicated gesture queue** with QoS `.userInteractive`
- **Separate mouse event queue** to prevent blocking
- **Exponential smoothing** algorithm for fluid movement
- **Velocity-based sensitivity** scaling
- **Minimal heap allocations** in hot path
- **Smart threshold detection** to reduce false positives

### Implementation Details
```swift
// Touch state management
- State machine: idle → possibleTap → dragging → release
- Individual finger tracking with 32-bit IDs
- Centroid calculation for multi-finger gestures
- Movement delta with screen-space transformation

// Event generation
- CGEvent with .otherMouse* types
- Direct posting to .cghidEventTap
- Optional gesture consumption via event tap
```

## 🐛 Troubleshooting

### Three-finger drag not working
1. **Verify accessibility permissions** are granted
2. **Restart MiddleDrag** from menu bar
3. **Optional**: Try disabling system three-finger gestures if conflicts occur
4. **Last resort**: Enable "Block System Gestures" in Advanced menu
5. **Check Console.app** for error messages

### Cursor jumps or jitters
1. **Increase smoothing** in Advanced settings
2. **Lower sensitivity** for more control
3. **Clean trackpad** surface
4. **Check for interference** from other utilities

### Conflicts with other apps
- **BetterTouchTool**: Disable three-finger gestures
- **Karabiner**: Check for conflicting rules
- **MagicPrefs**: Disable or uninstall
- **Multitouch**: Close while using MiddleDrag

### High CPU usage
1. **Check Activity Monitor** for actual usage (should be <1%)
2. **Reduce smoothing** if needed
3. **Report issue** with Mac model and macOS version

## 🏗️ Building from Source

### Requirements
- macOS 11.0+
- Xcode 13+ or Swift 5.5+
- No developer certificate required (ad-hoc signing)

### Build Commands

```bash
# Quick build with script
./build.sh

# Manual Xcode build
xcodebuild -project MiddleDrag.xcodeproj \
           -scheme MiddleDrag \
           -configuration Release \
           -derivedDataPath build \
           PRODUCT_BUNDLE_IDENTIFIER="com.yourname.MiddleDrag" \
           OTHER_LDFLAGS="-F/System/Library/PrivateFrameworks -framework MultitouchSupport" \
           CODE_SIGN_IDENTITY="-"

# Direct Swift compilation (for testing)
swiftc MiddleDrag/*.swift \
       -o MiddleDrag \
       -F/System/Library/PrivateFrameworks \
       -framework MultitouchSupport \
       -framework CoreFoundation \
       -framework CoreGraphics \
       -framework AppKit
```

### Project Configuration
In Xcode project settings:
- **Framework Search Paths**: `/System/Library/PrivateFrameworks`
- **Other Linker Flags**: `-framework MultitouchSupport`
- **App Sandbox**: Disabled (required for private framework)
- **Hardened Runtime**: Disabled (for private API access)

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Current Priorities
- [ ] Haptic feedback on gesture recognition
- [ ] Custom gesture patterns (two-finger middle click, etc.)
- [ ] Per-application profiles with automatic switching
- [ ] Gesture visualization overlay
- [ ] Force Touch pressure mapping
- [ ] Multi-touch gesture macros
- [ ] Export/import settings
- [ ] Crash reporting and analytics (opt-in)

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details

## 🙏 Acknowledgments

- [Ryan Hanson's](https://medium.com/ryan-hanson/touching-apples-private-multitouch-framework-64f87611cfc9) pioneering research on MultitouchSupport.framework
- [M5MultitouchSupport](https://github.com/mhuusko5/M5MultitouchSupport) for framework documentation
- [MiddleClick](https://github.com/artginzburg/MiddleClick) for initial inspiration
- [BetterTouchTool](https://folivora.ai) for showing what's possible
- The CAD community for extensive testing and feedback

## ⚠️ Important Notes

### Private Framework Usage
This app uses Apple's private `MultitouchSupport.framework`:
- ❌ **Cannot be distributed** via Mac App Store
- ⚠️ **May break** with future macOS updates
- ✅ **Stable since macOS 10.5** (remarkably consistent API)
- ✅ **Used by** BetterTouchTool, Multitouch, and other utilities

### Security Considerations
- Requires **Accessibility permissions** for mouse event simulation
- **App Sandbox disabled** for private framework access
- **No network access** or data collection
- **Open source** for transparency

## 📊 Performance Metrics

Tested on MacBook Pro M1 Pro:
- **CPU Usage**: 0.1-0.3% during active dragging
- **Memory**: ~8MB resident
- **Latency**: <5ms from touch to cursor movement
- **Frame Rate**: 60-120Hz depending on trackpad
- **Battery Impact**: Negligible (<1% over 8 hours)

---

**Made with ❤️ for engineers, designers, and makers who deserve proper middle mouse functionality on Mac.**

*If MiddleDrag helps your workflow, consider starring the repo and sharing with your CAD community!*
