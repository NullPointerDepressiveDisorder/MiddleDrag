# MiddleDrag Project Structure

## Refactored Architecture

The project has been refactored from two large files into a modular, maintainable structure:

```
MiddleDrag/
├── Core/                       # Core functionality
│   ├── MultitouchFramework.swift    # Private API bindings and framework management
│   ├── GestureRecognizer.swift      # Gesture detection and state management
│   └── MouseEventGenerator.swift    # Mouse event generation and cursor control
│
├── Models/                     # Data models
│   ├── TouchModels.swift           # Touch data structures (MTPoint, MTTouch, etc.)
│   └── GestureModels.swift         # Gesture state and configuration models
│
├── Managers/                   # Business logic managers
│   ├── MultitouchManager.swift     # Main coordinator for gesture system
│   └── DeviceMonitor.swift         # Device monitoring and callback management
│
├── UI/                         # User interface
│   ├── MenuBarController.swift     # Menu bar UI management
│   └── AlertHelper.swift           # Alert dialogs and user notifications
│
├── Utilities/                  # Helper utilities
│   ├── PreferencesManager.swift    # User preferences persistence
│   └── LaunchAtLoginManager.swift  # Launch at login functionality
│
├── MiddleDragApp.swift        # SwiftUI app entry point
├── AppDelegate.swift           # Application delegate
├── Info.plist                  # App configuration
└── MiddleDrag.entitlements    # App entitlements
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

### Model Layer
- **TouchModels**: Raw touch data structures
- **GestureModels**: Application state and configuration

### Manager Layer
- **MultitouchManager**: Main coordinator, implements business logic
- **DeviceMonitor**: Manages device lifecycle and callbacks

### UI Layer
- **MenuBarController**: All menu bar UI logic
- **AlertHelper**: Centralized alert management

### Utility Layer
- **PreferencesManager**: UserDefaults persistence
- **LaunchAtLoginManager**: System integration for auto-launch

## Design Patterns Used

1. **Delegate Pattern**: For loose coupling between components
2. **Singleton Pattern**: For shared managers (with care)
3. **Observer Pattern**: Using NotificationCenter for preferences
4. **Factory Pattern**: Device creation in MultitouchFramework
5. **Strategy Pattern**: Configurable gesture recognition

## Adding New Features

To add a new feature, identify which layer it belongs to:

1. **New gesture type?** → Modify GestureRecognizer
2. **New mouse action?** → Extend MouseEventGenerator
3. **New preference?** → Update UserPreferences model
4. **New menu item?** → Add to MenuBarController
5. **New device support?** → Extend DeviceMonitor

## Dependencies

The refactored code maintains minimal dependencies:
- No external Swift packages required
- Uses only system frameworks
- Private framework access isolated to one file
