#!/bin/bash

# Create App Bundle for Clippy
# This script creates a proper macOS app bundle from the Swift build

set -e

APP_NAME="Clippy"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"

echo "🔨 Building Clippy..."
swift build -c release

echo "📦 Creating app bundle..."

# Remove existing bundle
rm -rf "${APP_BUNDLE}"

# Create directory structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
cp "Sources/Info.plist" "${APP_BUNDLE}/Contents/"

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Sign the app (ad-hoc signing for local use)
echo "🔐 Signing app bundle..."
codesign --sign - --force --deep "${APP_BUNDLE}"

echo "✅ App bundle created: ${APP_BUNDLE}"
echo ""
echo "To install, either:"
echo "  1. Double-click ${APP_BUNDLE} to run"
echo "  2. Move to /Applications: mv ${APP_BUNDLE} /Applications/"
echo ""
echo "⚠️  Remember to grant Accessibility permissions in System Settings!"
