#!/bin/bash
# MyLife.app 번들 생성 스크립트
# 사용법: bash Scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Release 빌드 중..."
swift build -c release --scratch-path /tmp/myasset-release 2>&1 | tail -1

APP_DIR="MyLife.app"
rm -rf "$APP_DIR" "MyAsset.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp /tmp/myasset-release/release/MyAsset "$APP_DIR/Contents/MacOS/MyAsset"

# SwiftPM 리소스 번들(로고 등)을 Contents/Resources 에 복사 → Bundle.module 이 런타임에 찾음
# (Bundle.main.resourceURL == Contents/Resources 가 탐색 경로에 포함됨)
RES_BUNDLE="MyAsset_MyAsset.bundle"
if [ -d "/tmp/myasset-release/release/$RES_BUNDLE" ]; then
    cp -R "/tmp/myasset-release/release/$RES_BUNDLE" "$APP_DIR/Contents/Resources/"
    # flat 번들에 최소 Info.plist 를 넣어 codesign --deep 이 정상 인식하도록 함
    cat > "$APP_DIR/Contents/Resources/$RES_BUNDLE/Info.plist" <<'BPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.junsang.mylife.resources</string>
    <key>CFBundleName</key>
    <string>MyAsset_MyAsset</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
</dict>
</plist>
BPLIST
fi

echo "▸ 아이콘 생성 중..."
ICONSET=/tmp/MyLife.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift Scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/MyLife.icns"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MyAsset</string>
    <key>CFBundleIdentifier</key>
    <string>com.junsang.mylife</string>
    <key>CFBundleName</key>
    <string>MyLife</string>
    <key>CFBundleDisplayName</key>
    <string>MyLife</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>CFBundleIconFile</key>
    <string>MyLife</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.lifestyle</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Junsang Lee</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>현재 위치 기반 날씨를 표시하기 위해 위치 정보가 필요합니다.</string>
    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>현재 위치 기반 날씨를 표시하기 위해 위치 정보가 필요합니다.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP_DIR" 2>/dev/null

echo "✓ $(pwd)/$APP_DIR 생성 완료"
echo "  Applications 폴더로 옮기려면: mv MyLife.app /Applications/"
