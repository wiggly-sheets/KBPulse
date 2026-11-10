#!/bin/bash
# build-dmg.sh - Build KBPulse app and create DMG
# Usage: ./build-dmg.sh [release|debug|both]

set -e

BUILD_TYPE="${1:-release}"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_ROOT/KBPulse.xcodeproj"
APP_NAME="KBPulseApp"
APP_BUNDLE="$PROJECT_ROOT/build/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$PROJECT_ROOT/build/$DMG_NAME"

echo "=== KBPulse Build Script ==="
echo "Building $APP_NAME in $BUILD_TYPE mode..."

buildScheme() {
	local scheme="$1"
	echo "Building scheme: $scheme"
	xcodebuild -project "$PROJECT_FILE" \
		-scheme "$scheme" \
		-configuration "$BUILD_TYPE" \
		-derivedDataPath "$PROJECT_ROOT/build/DerivedData" \
		CODE_SIGNING_ALLOWED=NO \
		PRODUCT_BUNDLE_IDENTIFIER="com.ethanrdoesmc.kbpulseapp" \
		build 2>&1 | grep -E "(^error|BUILD (SUCCES|FAIL))" || true
}

# Build the app
buildScheme "$APP_NAME"

if [ ! -d "$APP_BUNDLE" ] && [ "$BUILD_TYPE" != "both" ]; then
	# Copy app bundle to build dir with .app extension
	ACTUAL_APP=$(find "$PROJECT_ROOT/build/DerivedData" -name "KBPulseApp.app" -type d 2>/dev/null | head -1)
	if [ -n "$ACTUAL_APP" ]; then
		mkdir -p "$(dirname "$APP_BUNDLE")"
		cp -R "$ACTUAL_APP" "$APP_BUNDLE"
		echo "App bundle copied to $APP_BUNDLE"
	else
		echo "Error: Could not find built app bundle"
		exit 1
	fi
fi

# Create DMG
echo "Creating DMG..."

# Create temporary DMG build directory
DMG_TEMP="$PROJECT_ROOT/build/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp dir
ACTUAL_APP=$(find "$PROJECT_ROOT/build/DerivedData" -name "KBPulseApp.app" -type d 2>/dev/null | head -1)
if [ -n "$ACTUAL_APP" ]; then
	cp -R "$ACTUAL_APP" "$DMG_TEMP/"
else
	echo "Error: No app bundle found"
	exit 1
fi

# Create DMG using hdiutil
hdiutil create -volname "$APP_NAME" \
	-srcfolder "$DMG_TEMP" \
	-ov -format UDZO \
	"$DMG_PATH" 2>&1 | tail -5

# Clean up temp
rm -rf "$DMG_TEMP"

echo "DMG created at $DMG_PATH"
if [ -f "$DMG_PATH" ]; then
	echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
fi

# Optional: Verify the app
echo "Verifying app bundle..."
if [ -d "$APP_BUNDLE" ]; then
	codesign --verify --deep "$APP_BUNDLE" 2>/dev/null && echo "Code signature valid" || echo "No code signature (expected for ad-hoc build)"
fi

echo "Build complete!"
