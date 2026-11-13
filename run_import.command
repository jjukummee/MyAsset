#!/bin/bash
# MyAsset 거래내역 수동 가져오기 (데몬 없이 즉시 1회 실행)
# incoming/ 폴더의 모든 XLS 를 지금 바로 처리합니다.

echo "🚀 MyAsset 거래내역 수동 처리 시작..."
echo ""

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
/bin/bash "$PROJECT_DIR/scripts/auto_import.sh"
echo "$(cat /tmp/myasset_import.log 2>/dev/null | tail -n 30)"

echo ""
echo "완료되면 이 창을 닫으세요."
read -p "Enter 키를 눌러 종료..." _
