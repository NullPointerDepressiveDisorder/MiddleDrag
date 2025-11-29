#!/bin/bash

# MiddleDrag Debug Setup Script
# This script helps set up accessibility permissions for debug builds

set -e

BUNDLE_ID="com.middledrag.MiddleDrag"
APP_NAME="MiddleDrag"

echo "🔧 MiddleDrag Debug Setup"
echo "========================="
echo ""

# Find the debug build - exclude Index.noindex
echo "📍 Looking for debug build..."
DEBUG_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -path "*/Build/Products/Debug/*" ! -path "*Index.noindex*" 2>/dev/null | head -1)

if [ -z "$DEBUG_APP" ]; then
    echo "❌ No debug build found in DerivedData."
    echo "   Please build the project in Xcode first (⌘B)"
    exit 1
fi

echo "✅ Found: $DEBUG_APP"
echo ""

# Check current accessibility status
echo "🔐 Checking accessibility permissions..."
if sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
    "SELECT client FROM access WHERE service='kTCCServiceAccessibility' AND client='$BUNDLE_ID'" 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "✅ Accessibility permission already granted for bundle ID"
else
    echo "⚠️  Accessibility permission not found"
fi
echo ""

# Options menu
echo "What would you like to do?"
echo ""
echo "  1) Open System Settings → Accessibility (recommended)"
echo "  2) Reset accessibility permissions (re-prompts on next launch)"
echo "  3) Show debug app path (to add manually)"
echo "  4) Run debug build directly"
echo "  5) Build and run with xcodebuild"
echo "  q) Quit"
echo ""
read -p "Choose an option: " choice

case $choice in
    1)
        echo ""
        echo "Opening System Settings..."
        echo "📋 Add this app: $DEBUG_APP"
        echo ""
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ;;
    2)
        echo ""
        echo "Resetting accessibility permissions for $BUNDLE_ID..."
        tccutil reset Accessibility "$BUNDLE_ID"
        echo "✅ Done! Run the app again to see the permission prompt."
        ;;
    3)
        echo ""
        echo "Debug app path:"
        echo "$DEBUG_APP"
        echo ""
        echo "You can drag this into System Settings → Privacy & Security → Accessibility"
        ;;
    4)
        echo ""
        if [ ! -f "$DEBUG_APP/Contents/MacOS/$APP_NAME" ]; then
            echo "❌ Executable not found. Rebuild in Xcode (⌘B)"
            exit 1
        fi
        echo "Running debug build..."
        echo "Console output will appear below:"
        echo "=================================="
        "$DEBUG_APP/Contents/MacOS/$APP_NAME"
        ;;
    5)
        echo ""
        echo "Building and running..."
        cd "$(dirname "$0")"
        xcodebuild -scheme MiddleDrag -configuration Debug build
        # Find the newly built app
        NEW_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -path "*/Build/Products/Debug/*" ! -path "*Index.noindex*" 2>/dev/null | head -1)
        if [ -n "$NEW_APP" ] && [ -f "$NEW_APP/Contents/MacOS/$APP_NAME" ]; then
            echo ""
            echo "Running $NEW_APP..."
            "$NEW_APP/Contents/MacOS/$APP_NAME"
        else
            echo "❌ Build succeeded but app not found"
        fi
        ;;
    q|Q)
        echo "Bye!"
        exit 0
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac
