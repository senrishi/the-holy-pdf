#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="TheHolyPdf"
APP_BUNDLE="$DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "==> Cleaning old bundle..."
rm -rf "$APP_BUNDLE"

echo "==> Building $APP_NAME..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy AppIcon.icns if available
if [ -f "$DIR/AppIcon.icns" ]; then
    echo "==> Embedding AppIcon.icns..."
    cp "$DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

swiftc -O -framework Cocoa -framework PDFKit -framework CoreImage -framework QuartzCore -framework Vision \
  "$DIR"/Sources/TheHolyPdf/*.swift \
  -o "$MACOS_DIR/$APP_NAME"

echo "==> Writing Info.plist with native PDF document associations..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TheHolyPdf</string>
    <key>CFBundleIdentifier</key>
    <string>com.theholypdf.app</string>
    <key>CFBundleName</key>
    <string>TheHolyPdf</string>
    <key>CFBundleDisplayName</key>
    <string>TheHolyPdf</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>pdf</string>
                <string>PDF</string>
            </array>
            <key>CFBundleTypeMIMETypes</key>
            <array>
                <string>application/pdf</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.adobe.pdf</string>
            <key>UTTypeDescription</key>
            <string>PDF Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.composite-content</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>pdf</string>
                    <string>PDF</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/pdf</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Moving $APP_NAME.app to /Applications and cleaning from DEV folder..."
rm -rf "/Applications/$APP_NAME.app"
mv "$APP_BUNDLE" "/Applications/$APP_NAME.app"

echo "==> Registering with macOS Launch Services for right-click 'Open With'..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -f "$LSREGISTER" ]; then
    "$LSREGISTER" -f -R -trusted "/Applications/$APP_NAME.app"
fi

echo "==> Successfully installed to /Applications/$APP_NAME.app (DEV folder cleaned)!"
