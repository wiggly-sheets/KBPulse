#!/bin/bash
# build-dmg.sh - Build the KBPulse app (with the embedded kbpulse CLI) and,
# unless asked for the app alone, package it as a DMG.
# Usage: ./build-dmg.sh [app|dmg] [release|debug]

set -euo pipefail

MODE="dmg"
if [[ "${1:-}" == "app" || "${1:-}" == "dmg" ]]; then
	MODE="$1"
	shift
fi

BUILD_TYPE="$(printf '%s' "${1:-release}" | tr '[:upper:]' '[:lower:]')"
case "$BUILD_TYPE" in
	release) CONFIGURATION="Release" ;;
	debug) CONFIGURATION="Debug" ;;
	*)
		echo "Usage: ./build-dmg.sh [app|dmg] [release|debug]" >&2
		exit 1
		;;
esac

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_ROOT/KBPulse.xcodeproj"
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
APP_NAME="KBPulse"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_BUNDLE="$PROJECT_ROOT/build/$APP_NAME.app"
DMG_PATH="$PROJECT_ROOT/build/$APP_NAME.dmg"

echo "=== KBPulse Build Script ==="
echo "Building $APP_NAME ($CONFIGURATION)…"

# Pick whichever shared scheme builds the app. The project has been renamed
# more than once, so accept both capitalisations instead of hard-coding one.
SCHEMES=$(xcodebuild -list -project "$PROJECT_FILE" 2>/dev/null \
	| sed -n '/Schemes:/,$p' | tail -n +2 | sed 's/^[[:space:]]*//')
if printf '%s\n' "$SCHEMES" | grep -qx "KBPulse"; then
	SCHEME="KBPulse"
elif printf '%s\n' "$SCHEMES" | grep -qx "kbpulse"; then
	SCHEME="kbpulse"
else
	echo "Error: no KBPulse app scheme found in the project." >&2
	exit 1
fi

# The Makefile stamps a release version through these two variables. A local
# build without them keeps MARKETING_VERSION from the Xcode project.
VERSION_FLAGS=""
if [ -n "${MARKETING_VERSION:-}" ]; then
	VERSION_FLAGS="$VERSION_FLAGS MARKETING_VERSION=$MARKETING_VERSION"
fi
if [ -n "${CURRENT_PROJECT_VERSION:-}" ]; then
	VERSION_FLAGS="$VERSION_FLAGS CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION"
fi

# The app target depends on the CLI target and embeds the resulting binary in
# Contents/Helpers. Let xcodebuild's exit status decide success.
xcodebuild -project "$PROJECT_FILE" \
	-scheme "$SCHEME" \
	-configuration "$CONFIGURATION" \
	-derivedDataPath "$DERIVED_DATA" \
	CODE_SIGNING_ALLOWED=NO \
	$VERSION_FLAGS \
	build

ACTUAL_APP="$PRODUCTS_DIR/$APP_NAME.app"
if [ ! -d "$ACTUAL_APP" ]; then
	echo "Error: built app bundle not found at $ACTUAL_APP" >&2
	exit 1
fi
if [ ! -x "$ACTUAL_APP/Contents/Helpers/kbpulse" ]; then
	echo "Error: kbpulse CLI was not embedded in the app bundle." >&2
	exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$(dirname "$APP_BUNDLE")"
cp -R "$ACTUAL_APP" "$APP_BUNDLE"
echo "App bundle: $APP_BUNDLE"

# Ad-hoc sign the bundle, including the embedded CLI helper, so the copy in
# ~/Applications is a valid target for the system.
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "Signed ad-hoc: $APP_BUNDLE"

if [ "$MODE" = "app" ]; then
	echo "Build complete!"
	exit 0
fi

# Create the DMG from a staging folder containing the app and the usual
# drag-to-Applications shortcut.
DMG_TEMP="$PROJECT_ROOT/build/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$ACTUAL_APP" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

echo "Creating DMG…"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" \
	-srcfolder "$DMG_TEMP" \
	-ov -format UDZO \
	"$DMG_PATH"

rm -rf "$DMG_TEMP"

echo "DMG created at $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"

if codesign --verify --deep "$APP_BUNDLE" 2>/dev/null; then
	echo "Code signature valid"
else
	echo "No code signature (expected for an unsigned build)"
fi

echo "Build complete!"
