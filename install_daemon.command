#!/bin/bash
# MyAsset 자동 가져오기 데몬 설치 / 재설치
# 이 파일을 더블클릭하면 설치(또는 갱신)됩니다. 한 번만 하면 됩니다.

set -e
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SRC="$PROJECT_DIR/com.myasset.importer.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.myasset.importer.plist"
LABEL="com.myasset.importer"
UID_NUM="$(id -u)"

echo "🔧 MyAsset 자동 가져오기 데몬 설치 중..."
echo ""

mkdir -p "$HOME/Library/LaunchAgents"

# 기존 데몬 내리기 (구·신 방식 모두 시도)
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl unload "$PLIST_DST" 2>/dev/null || true

# plist 복사
cp "$PLIST_SRC" "$PLIST_DST"
mkdir -p "$PROJECT_DIR/incoming"
/usr/bin/plutil -replace ProgramArguments.1 -string "$PROJECT_DIR/scripts/auto_import.sh" "$PLIST_DST"
/usr/bin/plutil -replace WatchPaths.0 -string "$PROJECT_DIR/incoming" "$PLIST_DST"
echo "   plist 복사 완료: $PLIST_DST"

# 등록 (modern bootstrap, 실패 시 legacy load)
if launchctl bootstrap "gui/$UID_NUM" "$PLIST_DST" 2>/dev/null; then
    echo "   bootstrap 등록 완료"
else
    launchctl load "$PLIST_DST"
    echo "   load 등록 완료"
fi
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/$UID_NUM/$LABEL" 2>/dev/null || true

echo ""
if launchctl list "$LABEL" >/dev/null 2>&1; then
    echo "✅ 설치 완료!"
    echo ""
    echo "이제 Claude(Cowork)에게 XLS 파일을 주면 incoming/ 폴더에 저장되고,"
    echo "데몬이 자동으로 MyAsset 앱에 반영합니다. (incoming/ 변경 시 즉시 + 30초마다 확인)"
    echo ""
    echo "로그 확인: tail -f /tmp/myasset_import.log"
else
    echo "⚠️  설치 확인 실패. /tmp/myasset_import.log 를 확인하세요."
fi

echo ""
read -p "Enter 키를 눌러 종료..." _
