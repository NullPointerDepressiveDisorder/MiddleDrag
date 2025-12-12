#!/bin/bash

# MiddleDrag Build Script
# Builds the app with proper framework linking and code signing

set -e  # Exit on error

# Configuration
APP_NAME="MiddleDrag"
BUILD_DIR="build"
BUNDLE_ID="com.middledrag.MiddleDrag"

# Parse arguments
CONFIGURATION="Release"
RUN_AFTER=false
CLEAN_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean|-c)
            CLEAN_BUILD=true
            shift
            ;;
        --debug|-d)
            CONFIGURATION="Debug"
            shift
            ;;
        --run|-r)
            RUN_AFTER=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./build.sh [options]"
            echo ""
            echo "Options:"
            echo "  --clean, -c    Clean previous build"
            echo "  --debug, -d    Build debug configuration"
            echo "  --run, -r      Run after building"
            echo "  --help, -h     Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🔨 Building MiddleDrag ($CONFIGURATION)..."

# Clean previous build
if [ "CLEAN_BUILD" = true ]; then
    echo "Cleaning previous build..."
    rm -rf "$BUILD_DIR"
fi

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
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [ -z "$APP_PATH" ]; then
    echo "❌ Build failed: Could not find $APP_NAME.app"
    exit 1
fi

echo "✅ Build successful!"
echo "📦 App location: $APP_PATH"

# Run if requested
if [ "$RUN_AFTER" = true ]; then
    echo ""
    echo "🚀 Running $APP_NAME..."
    echo "📝 Debug output:"
    echo "================"
    "$APP_PATH/Contents/MacOS/$APP_NAME"
    exit 0
fi

# For release builds, offer to copy to Applications
if [ "$CONFIGURATION" = "Release" ]; then
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
fi

echo "🎉 Done!"
