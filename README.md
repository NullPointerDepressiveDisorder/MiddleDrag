# MiddleDrag

**Three-finger trackpad gestures for middle-click and middle-drag on macOS.**

Finally use your MacBook for CAD work without carrying a mouse.

[![macOS 15+](https://img.shields.io/badge/macOS-15.0+-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Homebrew](https://img.shields.io/badge/Homebrew-tap-brown?logo=homebrew)](https://github.com/NullPointerDepressiveDisorder/homebrew-tap)
[![GitHub release](https://img.shields.io/github/v/release/NullPointerDepressiveDisorder/MiddleDrag)](https://github.com/NullPointerDepressiveDisorder/MiddleDrag/releases)
[![Downloads](https://img.shields.io/github/downloads/NullPointerDepressiveDisorder/MiddleDrag/total?color=brightgreen)](https://github.com/NullPointerDepressiveDisorder/MiddleDrag/releases)
[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B59309%2Fgithub.com%2FNullPointerDepressiveDisorder%2FMiddleDrag.svg?type=shield&issueType=license)](https://app.fossa.com/projects/custom%2B59309%2Fgithub.com%2FNullPointerDepressiveDisorder%2FMiddleDrag?ref=badge_shield&issueType=license)
[![codecov](https://codecov.io/github/NullPointerDepressiveDisorder/MiddleDrag/graph/badge.svg?token=8PR656FVXE)](https://codecov.io/github/NullPointerDepressiveDisorder/MiddleDrag)

<p align="center">
  <img src="docs/assets/demo.gif" alt="MiddleDrag Demo">
</p>

## The Problem

Professional 3D software expects middle-mouse-button navigation. MacBook trackpads don't have one.

For years, CAD users on Mac have been forced to either carry an external mouse, use awkward four-key modifier combinations, or fight with unreliable workarounds. Forum threads dating back to 2017 are filled with users pleading for a solution.

**MiddleDrag fixes this.** Three-finger tap for middle-click. Three-finger drag for middle-drag. Works alongside Mission Control and other system gestures.

## Who This Is For

MiddleDrag is essential for users of applications with **broken or missing trackpad navigation**:

| Application | Native Trackpad Support | MiddleDrag Value |
|-------------|------------------------|------------------|
| **FreeCAD** | ❌ Broken gestures | Essential — native gestures misfire constantly |
| **OnShape** | ❌ Force-click only | Essential — no tap gestures, causes hand strain |
| **ZBrush** | ❌ None | Essential — zero multi-touch recognition |
| **SketchUp Pro** | ❌ 4-key combos | Essential — Ctrl+Cmd+Shift+drag is unusable |
| **SolidWorks** | ❌ N/A (Windows VM) | Essential — only zoom works through Parallels |
| **Cinema 4D** | ⚠️ Alt-key required | High — every action needs a modifier key |
| **Fusion 360** | ⚠️ Buggy | High — breaks after updates and sleep cycles |
| **Maya** | ⚠️ Erratic | High — viewport spins without input |
| **Rhino** | ✅ Good | Moderate — sleep-wake bug breaks gestures |
| **Blender** | ✅ Good | Optional — native support works, but Alt-key conflicts exist |

Also useful for **browsers** (middle-click to open links in new tabs, close tabs) and **any application** expecting middle-mouse input.

## Features

- **Three-finger tap** → Middle mouse click
- **Three-finger drag** → Middle mouse drag (pan/orbit in 3D apps)
- **Works with system gestures** — Mission Control, Exposé, and other macOS gestures remain functional
- **Native macOS app** — Menu bar interface, no terminal configuration required
- **Configurable** — Adjust sensitivity and smoothing to your preference
- **Launch at login** — Set it and forget it

## Installation

### Homebrew (Recommended)

```bash
brew tap nullpointerdepressivedisorder/tap
brew install --cask middledrag
```

### Manual Download

1. Download from [Releases](https://github.com/NullPointerDepressiveDisorder/MiddleDrag/releases)
2. Move `MiddleDrag.app` to Applications
3. Launch and grant Accessibility permissions when prompted

### Gatekeeper Notice

MiddleDrag isn't notarized with Apple (standard for open source apps). On first launch:

Close the alert, then go to **System Settings → Privacy & Security → Click "Open Anyway"**

Or run in Terminal: **(Recommended)**

```bash
xattr -cr /Applications/MiddleDrag.app
```

## Usage

MiddleDrag runs in your menu bar as a hand icon.

| Gesture | Action |
|---------|--------|
| Three-finger tap | Middle click |
| Three-finger drag | Middle drag (pan/orbit) |

### Settings

- **Enabled** — Toggle gesture recognition
- **Drag Sensitivity** — Cursor speed during drag (0.5x – 2x)
- **Require Exactly 3 Fingers** — Ignore 4+ finger touches
- **Launch at Login** — Auto-start with macOS

## Why MiddleDrag?

### vs. BetterTouchTool ($10-24)

BetterTouchTool is powerful but overwhelming. Hundreds of options, complex interface, middle-click buried among features you'll never use. MiddleDrag does one thing well.

### vs. Middle ($8)

Middle costs $8 for functionality that should be free. It's also closed-source. MiddleDrag is MIT-licensed and community-maintained.

### vs. MiddleClick (open source)

MiddleClick requires terminal commands for all configuration — no GUI. MiddleDrag provides a native macOS settings interface. Both are open source, but MiddleDrag is actively maintained for modern macOS versions.

## Requirements

- macOS 15.0 (Sequoia) or later
- Built-in trackpad or Magic Trackpad
- Accessibility permissions

## How It Works

MiddleDrag uses Apple's private MultitouchSupport framework to intercept raw touch data *before* the system gesture recognizer processes it. This allows three-finger gestures to generate middle-mouse events while leaving Mission Control and other system gestures intact.

Technical flow:

1. MultitouchSupport framework provides raw touch coordinates
2. GestureRecognizer detects three-finger tap/drag patterns
3. Accessibility API generates synthetic middle-mouse events
4. CGEventTap suppresses conflicting system click events

## Building from Source

```bash
git clone https://github.com/NullPointerDepressiveDisorder/MiddleDrag.git
cd MiddleDrag
./build.sh
```

Or open `MiddleDrag.xcodeproj` in Xcode 16+.

<details>
<summary>Project Structure</summary>

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

</details>

## Compatibility

| macOS Version | Status |
|---------------|--------|
| macOS 15 (Sequoia) | ✅ Supported |
| macOS 26 beta (Tahoe) | ✅ Compatible |

Works with built-in MacBook trackpads and external Magic Trackpads.

## Troubleshooting

<details>
<summary>Gestures not working</summary>

1. Check Accessibility permissions: **System Settings → Privacy & Security → Accessibility**
2. Toggle "Enabled" in the menu bar
3. Restart the app

</details>

<details>
<summary>After updating, gestures stopped</summary>

macOS treats each app version as a new application. Re-grant permissions:

1. **System Settings → Privacy & Security → Accessibility**
2. Toggle MiddleDrag **off** then **on**
3. Restart MiddleDrag

</details>

<details>
<summary>Conflicts with system gestures</summary>

Use soft taps instead of physical clicks. The app is designed to coexist with system gestures, but pressing down hard may still trigger Mission Control.

</details>

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT License](LICENSE)

---

<p align="center">
  <i>Built for the CAD users who've been asking for this since 2017.</i>
</p>

[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B59309%2Fgithub.com%2FNullPointerDepressiveDisorder%2FMiddleDrag.svg?type=large&issueType=license)](https://app.fossa.com/projects/custom%2B59309%2Fgithub.com%2FNullPointerDepressiveDisorder%2FMiddleDrag?ref=badge_large&issueType=license)
[![](https://codecov.io/github/NullPointerDepressiveDisorder/MiddleDrag/graphs/sunburst.svg?token=8PR656FVXE)](https://codecov.io/github/NullPointerDepressiveDisorder/MiddleDrag)
