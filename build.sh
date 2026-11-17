#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Mole Friend"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "🐹 Building $APP_NAME.app..."

killall -9 MoleFriend 2>/dev/null || true
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES/ui"

# Copy HTML/CSS/JS frontend into bundle Resources
cp -R "$PROJECT_DIR/ui/"* "$RESOURCES/ui/"

# Write Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>
    <key>CFBundleExecutable</key>
    <string>MoleFriend</string>
    <key>CFBundleIdentifier</key>
    <string>fit.mole.friend</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mole Friend</string>
    <key>CFBundleDisplayName</key>
    <string>Mole Friend</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CSResourcesFileMapped</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

printf 'APPL????' > "$CONTENTS/PkgInfo"

# Compile Swift WebKit Host (Clean Architecture + SOLID modules)
MODULE_CACHE="/tmp/mole-swift-module-cache"
mkdir -p "$MODULE_CACHE"
SWIFT_SOURCES=(
    "$PROJECT_DIR/src/Domain/Models.swift"
    "$PROJECT_DIR/src/Domain/Protocols.swift"
    "$PROJECT_DIR/src/Infrastructure/SystemMetricsProvider.swift"
    "$PROJECT_DIR/src/Infrastructure/CommandAndConfigServices.swift"
    "$PROJECT_DIR/src/Application/BridgeActionHandlers.swift"
    "$PROJECT_DIR/src/Presentation/StatusBarController.swift"
    "$PROJECT_DIR/src/main.swift"
)
swiftc "${SWIFT_SOURCES[@]}" \
    -O \
    -target x86_64-apple-macosx12.0 \
    -module-cache-path "$MODULE_CACHE" \
    -framework Cocoa \
    -framework WebKit \
    -o "$MACOS/MoleFriend"

chmod +x "$MACOS/MoleFriend"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

BINARY_SIZE=$(du -sh "$MACOS/MoleFriend" | awk '{print $1}')
BUNDLE_SIZE=$(du -sh "$APP_BUNDLE" | awk '{print $1}')

echo "✅ Build complete!"
echo "   Binary size: $BINARY_SIZE"
echo "   App bundle:  $BUNDLE_SIZE ($APP_BUNDLE)"
