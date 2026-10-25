#!/bin/bash
# Builds a universal (Apple silicon + Intel) WorldZones.app into ./build.
#   ./build.sh          build only
#   ./build.sh install  also copy it to ~/Applications
#   ./build.sh dmg      also package build/WorldZones-<version>.dmg for other Macs
set -euo pipefail
cd "$(dirname "$0")"

APP=WorldZones
# Keep SwiftPM intermediates out of this folder (it lives inside a notes vault).
SCRATCH="${TMPDIR:-/tmp}/worldzones-build"
BUNDLE="build/$APP.app"

BINARIES=()
for ARCH in arm64 x86_64; do
    ARGS=(-c release --scratch-path "$SCRATCH-$ARCH" --triple "$ARCH-apple-macosx14.0")
    swift build "${ARGS[@]}"
    BINARIES+=("$(swift build "${ARGS[@]}" --show-bin-path)/$APP")
done

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$BUNDLE/Contents/MacOS/$APP"
cp Info.plist "$BUNDLE/Contents/Info.plist"

swift Scripts/make-icon.swift "$SCRATCH"
iconutil -c icns "$SCRATCH/AppIcon.iconset" -o "$BUNDLE/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$BUNDLE"
echo "Built $BUNDLE"

if [[ "${1:-}" == "install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x "$APP" || true
    rm -rf "$HOME/Applications/$APP.app"
    cp -R "$BUNDLE" "$HOME/Applications/"
    echo "Installed to ~/Applications/$APP.app"
fi

if [[ "${1:-}" == "dmg" ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
    DMG="build/$APP-$VERSION.dmg"
    STAGE="$SCRATCH/dmg"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$BUNDLE" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    echo "Packaged $DMG"
fi
