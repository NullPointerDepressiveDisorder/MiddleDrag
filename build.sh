#!/bin/bash

# MiddleDrag Build Script
# Builds the app with proper framework linking and code signing

set -e  # Exit on error

echo "🔨 Building MiddleDrag..."

# Configuration
APP_NAME="MiddleDrag"
BUILD_DIR="build"
CONFIGURATION="Release"
BUNDLE_ID="com.kmohindroo.MiddleDrag"

# Clean previous build
echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"

# Create build directory
mkdir -p "$BUILD_DIR"

# Build with xcodebuild
echo "Building with Xcode..."
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    OTHER_LDFLAGS="-F/System/Library/PrivateFrameworks -framework MultitouchSupport -framework CoreFoundation -framework CoreGraphics" \
    FRAMEWORK_SEARCH_PATHS="/System/Library/PrivateFrameworks" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    ARCHS="$(uname -m)" \
    ONLY_ACTIVE_ARCH=NO

# Find the built app
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Build failed: Could not find $APP_NAME.app"
    exit 1
fi

echo "✅ Build successful!"
echo "📦 App location: $APP_PATH"

# Optional: Copy to Applications folder
read -p "Copy to /Applications? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Copying to /Applications..."
    rm -rf "/Applications/$APP_NAME.app" 2>/dev/null || true
    cp -R "$APP_PATH" "/Applications/"
    echo "✅ Copied to /Applications/$APP_NAME.app"
    
    # Set proper permissions
    chmod -R 755 "/Applications/$APP_NAME.app"
    
    # Kill existing instance if running
    killall "$APP_NAME" 2>/dev/null || true
    
    # Launch the app
    read -p "Launch $APP_NAME now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "/Applications/$APP_NAME.app"
        echo "🚀 $APP_NAME launched!"
    fi
fi

echo "🎉 Done!"
