#!/bin/bash
# MyAsset 거래내역 자동 가져오기
# LaunchAgent가 incoming/ 폴더를 감시하다가 XLS 파일이 생기면 자동 실행.
#
# launchd 는 최소 PATH(/usr/bin:/bin:/usr/sbin:/sbin)로 실행되므로
# Anaconda python3 / pip3 를 찾지 못한다 → 아래에서 PATH를 직접 보강하고
# 동작하는 python 인터프리터를 명시적으로 탐색한다.

export PATH="/opt/anaconda3/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export LANG="ko_KR.UTF-8"

WATCH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INCOMING_DIR="$WATCH_DIR/incoming"
SCRIPT="$WATCH_DIR/scripts/import_transactions.py"
DATA_JSON="$HOME/Library/Application Support/MyAsset/data.json"
IMPORTED_DIR="$WATCH_DIR/imported"
FAILED_DIR="$WATCH_DIR/failed"
LOG="/tmp/myasset_import.log"

mkdir -p "$INCOMING_DIR" "$IMPORTED_DIR" "$FAILED_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
    # $1 = 제목, $2 = 본문
    /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
}

# ── 동작하는 python3 탐색 (xlrd 사용 가능 우선) ────────────────
find_python() {
    for cand in /opt/anaconda3/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 2>/dev/null)" /usr/bin/python3; do
        [ -n "$cand" ] && [ -x "$cand" ] || continue
        echo "$cand"
        return 0
    done
    return 1
}

PYTHON="$(find_python)"
if [ -z "$PYTHON" ]; then
    log "❌ python3 를 찾을 수 없습니다."
    notify "MyAsset 가져오기 오류" "python3 를 찾을 수 없습니다."
    exit 1
fi

# ── incoming/ 의 XLS 파일이 있는지 먼저 확인 ──────────────────
shopt -s nullglob
files=("$INCOMING_DIR"/*.xls "$INCOMING_DIR"/*.xlsx)
shopt -u nullglob
[ ${#files[@]} -eq 0 ] && exit 0   # 처리할 파일 없음 → 조용히 종료

# ── data.json 존재 확인 ───────────────────────────────────────
if [ ! -f "$DATA_JSON" ]; then
    log "❌ data.json 없음: $DATA_JSON — MyAsset 앱을 한 번 실행하세요."
    notify "MyAsset 가져오기 오류" "data.json 이 없습니다. 앱을 한 번 실행하세요."
    exit 1
fi

# ── xlrd 설치 보장 (선택한 python 기준) ───────────────────────
"$PYTHON" -c "import xlrd" 2>/dev/null || \
    "$PYTHON" -m pip install xlrd --break-system-packages -q 2>>"$LOG" || \
    "$PYTHON" -m pip install xlrd -q 2>>"$LOG" || true

# ── 파일별 처리 ───────────────────────────────────────────────
for xls in "${files[@]}"; do
    [ -f "$xls" ] || continue
    base="$(basename "$xls")"
    log "새 파일 감지: $base  (python=$PYTHON)"

    out="$("$PYTHON" "$SCRIPT" --file "$xls" --data-json "$DATA_JSON" 2>&1)"
    STATUS=$?
    echo "$out"

    if [ $STATUS -eq 0 ]; then
        mv -f "$xls" "$IMPORTED_DIR/$base"
        log "완료 → imported/ 로 이동: $base"
        added="$(echo "$out" | sed -n 's/.*신규 추가: *\([0-9]*\)건.*/\1/p' | head -1)"
        notify "MyAsset 거래내역 업데이트" "${added:-새} 건이 반영되었습니다."
    else
        mv -f "$xls" "$FAILED_DIR/$base"
        log "오류 발생 (종료코드: $STATUS) → failed/ 로 이동: $base"
        notify "MyAsset 가져오기 오류" "$base 처리 실패. /tmp/myasset_import.log 확인."
    fi
done
