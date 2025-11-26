#!/bin/bash

# MiddleDrag build script
# Builds the app without Xcode, using command line tools

echo "Building MiddleDrag..."

# Create build directory
mkdir -p build

# Compile Swift files
swiftc \
    -o build/MiddleDrag \
    -framework SwiftUI \
    -framework Cocoa \
    -framework CoreGraphics \
    -framework CoreFoundation \
    -F/System/Library/PrivateFrameworks \
    -framework MultitouchSupport \
    MiddleDrag/*.swift

# Check if compilation succeeded
if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

# Create app bundle structure
APP_BUNDLE="build/MiddleDrag.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Move executable
mv build/MiddleDrag "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp MiddleDrag/Info.plist "$APP_BUNDLE/Contents/"

# Create a simple icon (you can replace with actual icon)
echo "📐" > "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "✅ Build complete!"
echo "📍 App location: $APP_BUNDLE"
echo ""
echo "To run:"
echo "  open $APP_BUNDLE"
echo ""
echo "⚠️  Remember to grant accessibility permissions in System Settings"
