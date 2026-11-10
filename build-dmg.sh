#!/bin/bash
# build-dmg.sh - Build KBPulse app and create DMG
# Usage: ./build-dmg.sh [release|debug]

set -e

BUILD_TYPE="${1:-release}"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_ROOT/KBPulse.xcodeproj"
APP_NAME="KBPulseApp"
APP_BUNDLE="$PROJECT_ROOT/build/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$PROJECT_ROOT/build/$DMG_NAME"

echo "Building $APP_NAME in $BUILD_TYPE mode..."

# Clean and build
rm -rf "$PROJECT_ROOT/build"
mkdir -p "$PROJECT_ROOT/build"

xcodebuild -project "$PROJECT_FILE" \
	-scheme "$APP_BUNDLE" \
	-configuration "$BUILD_TYPE" \
	-derivedDataPath "$PROJECT_ROOT/build/DerivedData" \
	CODE_SIGNING_ALLOWED=NO \
	PRODUCT_BUNDLE_IDENTIFIER="com.ethanrdoesmc.kbpulseapp" \
	build

# Copy app bundle to build dir with .app extension
APP_PATH="$PROJECT_ROOT/build/DerivedData/KBPulse-*/Build/Products/$BUILD_TYPE/KBPulseApp.app"
if [ -d "$APP_PATH" ]; then
	# Find the actual path (workspace name may differ)
	ACTUAL_APP=$(find "$PROJECT_ROOT/build/DerivedData" -name "KBPulseApp.app" -type d | head -1)
	if [ -n "$ACTUAL_APP" ]; then
		cp -R "$ACTUAL_APP" "$APP_BUNDLE"
		echo "App bundle copied to $APP_BUNDLE"
	else
		echo "Error: Could not find built app bundle"
		exit 1
	fi
else
	echo "Error: App build output not found at $APP_PATH"
	exit 1
fi

# Create DMG
echo "Creating DMG..."

# Create temporary DMG build directory
DMG_TEMP="$PROJECT_ROOT/build/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp dir
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create DMG using hdiutil
hdiutil create -volname "$APP_NAME" \
	-srcfolder "$DMG_TEMP" \
	-ov -format UDZO \
	"$DMG_PATH"

# Clean up temp
rm -rf "$DMG_TEMP"

echo "DMG created at $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"

# Optional: Verify the app
echo "Verifying app bundle..."
codesign --verify --deep "$APP_BUNDLE" 2>/dev/null && echo "Code signature valid" || echo "No code signature (expected for ad-hoc build)"

echo "Build complete!"
