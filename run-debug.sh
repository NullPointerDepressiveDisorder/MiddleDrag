#!/bin/bash

# Quick script to run the debug build with console output
# Usage: ./run-debug.sh

APP_NAME="MiddleDrag"

# Find the debug build - exclude Index.noindex which is Xcode's cache
DEBUG_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -path "*/Build/Products/Debug/*" ! -path "*Index.noindex*" 2>/dev/null | head -1)

if [ -z "$DEBUG_APP" ]; then
    echo "❌ No debug build found. Build in Xcode first (⌘B)"
    exit 1
fi

# Verify the executable exists
if [ ! -f "$DEBUG_APP/Contents/MacOS/$APP_NAME" ]; then
    echo "❌ App found but executable missing: $DEBUG_APP"
    echo "   Try rebuilding in Xcode (⌘B)"
    exit 1
fi

echo "🚀 Running: $DEBUG_APP"
echo "📝 Debug output:"
echo "================"

# Run the app - output goes to terminal
"$DEBUG_APP/Contents/MacOS/$APP_NAME"
