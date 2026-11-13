#!/usr/bin/env python3
"""
MyAsset 은행 거래내역 가져오기 스크립트
토스(Toss) 앱 내보내기 XLS 형식에 최적화
"""

import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
import uuid
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path

# ──────────────────────────────────────────
# 날짜 형식: Swift JSONDecoder 기본값(.deferredToDate)은 Date를
# "2001-01-01 UTC 기준 초 단위 Double"로 인코딩/디코딩한다.
# ISO 문자열로 쓰면 앱이 디코딩에 실패하므로 반드시 Double로 저장한다.
# ──────────────────────────────────────────
KST = timezone(timedelta(hours=9))
REF_EPOCH = 978307200.0  # 2001-01-01 00:00:00 UTC 의 Unix timestamp

def ymd_hm_to_ref(date_str: str, time_str: str) -> float:
    """'YYYY-MM-DD' + 'HHMM'(KST) → timeIntervalSinceReferenceDate(Double)"""
    y, m, d = (int(x) for x in date_str[:10].split("-"))
    hh = int(time_str[:2]) if len(time_str) >= 2 and time_str[:2].isdigit() else 0
    mm = int(time_str[2:4]) if len(time_str) >= 4 and time_str[2:4].isdigit() else 0
    dt = datetime(y, m, d, hh, mm, 0, tzinfo=KST)
    return dt.timestamp() - REF_EPOCH

def any_date_to_ref(value) -> float | None:
    """기존 레코드의 date 값(Double 또는 ISO 문자열)을 Double로 정규화"""
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value)
        except ValueError:
            try:
                dt = datetime.fromisoformat(value[:10])
            except ValueError:
                return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=KST)
        return dt.timestamp() - REF_EPOCH
    return None

def ref_to_day_key(value) -> str:
    """date 값(Double 또는 문자열) → 중복 비교용 'YYYY-MM-DD' 문자열"""
    ref = any_date_to_ref(value)
    if ref is None:
        return str(value)[:10]
    return datetime.fromtimestamp(ref + REF_EPOCH, tz=KST).strftime("%Y-%m-%d")

def _hm_of(value) -> str:
    """date 값(Double 또는 문자열) → 중복 비교용 'HHMM' 문자열"""
    ref = any_date_to_ref(value)
    if ref is None:
        return "0000"
    return datetime.fromtimestamp(ref + REF_EPOCH, tz=KST).strftime("%H%M")

def ensure_package(pkg: str):
    """pip으로 패키지 자동 설치"""
    try:
        __import__(pkg)
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", pkg, "--break-system-packages", "-q"],
                       check=True)


# ──────────────────────────────────────────
# 카테고리 자동 분류
# ──────────────────────────────────────────
CATEGORY_RULES = [
    (["군인공제회"], "저축"),
    (["환전외화출금", "환전원화입금", "환전"], "이체"),
    (["이체", "송금", "계좌이체"], "이체"),

    # ── 부분일치 충돌 방지: 구체적 규칙을 일반 규칙보다 먼저 ──
    (["쿠팡이츠"], "식비"),                         # '쿠팡'(쇼핑)보다 먼저
    (["쿠팡플레이", "와우멤버십", "쿠팡 와우"], "구독"),  # '쿠팡'(쇼핑)보다 먼저

    (["급여", "월급", "상여", "성과급", "이자", "배당", "환급", "정기 예탁금", "입금"], "수입"),
    (["스타벅스", "투썸", "이디야", "메가커피", "컴포즈", "커피", "카페", "배스킨",
      "파리바게뜨", "뚜레쥬르", "베이커리", "도넛", "디저트", "빙수", "베이글"], "카페/간식"),
    (["넷플릭스", "유튜브", "멜론", "스포티파이", "디즈니", "왓챠", "티빙", "쿠팡플레이",
      "애플코리아", "Apple", "구독", "챗gpt", "chatgpt", "openai", "오픈ai", "프리미엄"], "구독"),
    (["쿠팡", "지마켓", "11번가", "옥션", "무신사", "올리브영", "다이소", "yes24", "예스이십사", "책",
      "크림", "kream", "코엑스", "신세계프라퍼티", "백화점", "아울렛", "마켓컬리", "국군복지단"], "쇼핑"),
    (["지하철", "버스", "택시", "카카오T", "코레일", "KTX", "SRT", "주유", "충전", "하이패스",
      "주차", "파킹", "parking", "도시관리공단", "Tesla", "테슬라", "tesla"], "교통"),
    (["GS25", "지에스25", "CU", "씨유", "세븐일레븐", "이마트24", "편의점", "이마트", "홈플러스", "롯데마트", "컬리",
      "배달의민족", "배민", "요기요", "맥도날드", "버거킹", "롯데리아", "써브웨이", "subway", "케밥", "kebab",
      "김밥", "식당", "국밥", "설농탕", "설렁탕", "한식", "중식", "일식", "양식", "피자", "치킨",
      "오봉집", "투다리", "생마차", "방울엄마", "닭갈비", "양꼬치", "꼬치", "곱창", "막창", "삼겹", "냉삼",
      "고깃집", "고기", "횟집", "회집", "포차", "술집", "선술집", "주점", "호프", "맥주",
      "칼국수", "분식", "떡볶이", "마라탕", "쌀국수", "국수", "초밥", "스시", "라멘", "우동",
      "베트남", "골뱅이", "닭발", "족발", "보쌈", "찜닭", "토스트",
      "생협", "생활협동조합", "셰프스위트", "회장님댁", "민들레뜨락", "무이한티", "찹찹", "명가원"], "식비"),
    (["통신", "SKT", "KT", "LGU", "관리비", "월세", "전세", "전기", "가스", "수도", "인터넷", "PAY 결제"], "주거/통신"),
    (["병원", "약국", "의원", "치과", "한의원", "검진", "이비인후과", "내과", "외과", "피부과", "안과", "정형외과"], "의료/건강"),
    (["CGV", "메가박스", "롯데시네마", "영화", "스팀", "PC방", "아이센스", "노래방", "콘서트", "공연",
      "미용실", "헤어", "포토이즘", "인생네컷", "포토매틱", "볼링", "당구", "스크린골프", "방탈출"], "여가/문화"),
    (["학원", "인강", "교재", "수강", "강의"], "교육"),
    (["축의", "조의", "부조", "선물"], "경조사/선물"),
]

# 양수(입금)인데 이 카테고리로 분류되면 '환불 추정'으로 본다(쇼핑/구독 환불이 흔함).
# 식당·카페 등의 +금액은 더치페이 정산(수입)일 가능성이 커서 제외 대상에서 뺀다.
REFUND_CATS = {"쇼핑", "구독"}

def categorize(title: str, amount: int) -> str:
    for keywords, category in CATEGORY_RULES:
        if any(kw.lower() in title.lower() for kw in keywords):
            return category
    return "수입" if amount > 0 else "기타"


# ──────────────────────────────────────────
# 파일명에서 날짜 추출
# 예: 홍길동_20260623012503.xls → 2026-06-23
# ──────────────────────────────────────────
def extract_date_from_filename(filepath: str) -> str | None:
    stem = Path(filepath).stem
    match = re.search(r"(\d{4})(\d{2})(\d{2})\d{6}", stem)
    if match:
        return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"
    match = re.search(r"(\d{4})-(\d{2})-(\d{2})", stem)
    if match:
        return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"
    return None


# ──────────────────────────────────────────
# XLS → CSV 변환
# ──────────────────────────────────────────
def _xlrd_to_csv(xls_bytes: bytes) -> str:
    """xlrd로 XLS 바이트를 CSV 텍스트로 변환"""
    ensure_package("xlrd")
    import xlrd
    buf = io.StringIO()
    writer = csv.writer(buf)
    wb = xlrd.open_workbook(file_contents=xls_bytes)
    ws = wb.sheet_by_index(0)
    for row_idx in range(ws.nrows):
        row = []
        for cell in ws.row(row_idx):
            if cell.ctype == xlrd.XL_CELL_NUMBER:
                v = int(cell.value) if cell.value == int(cell.value) else cell.value
                row.append(str(v))
            elif cell.ctype == xlrd.XL_CELL_DATE:
                dt = xlrd.xldate_as_datetime(cell.value, wb.datemode)
                row.append(dt.strftime("%Y.%m.%d"))
            else:
                row.append(str(cell.value).strip())
        writer.writerow(row)
    return buf.getvalue()

def xls_to_csv(xls_path: str, password: str | None) -> str:
    """XLS → CSV 텍스트. LibreOffice 없이 xlrd로 직접 변환."""
    with open(xls_path, "rb") as f:
        raw = f.read()

    # 1) 암호화 없이 직접 시도
    try:
        return _xlrd_to_csv(raw)
    except Exception as direct_err:
        if not password:
            raise RuntimeError("XLS를 읽지 못했습니다. 암호화된 파일이라면 가져오기 비밀번호를 설정해 주세요.") from direct_err

    # 2) msoffcrypto로 복호화 후 재시도
    try:
        ensure_package("msoffcrypto-tool")
        import msoffcrypto
        of = msoffcrypto.OfficeFile(io.BytesIO(raw))
        of.load_key(password=password)
        buf = io.BytesIO()
        of.decrypt(buf)
        return _xlrd_to_csv(buf.getvalue())
    except Exception as e:
        raise RuntimeError(f"XLS 변환 실패: {e}")


# ──────────────────────────────────────────
# CSV 파싱
# ──────────────────────────────────────────
def parse_amount(raw: str) -> int | None:
    cleaned = re.sub(r"[,원\s]", "", raw).strip()
    if not cleaned:
        return None
    try:
        val = int(cleaned)
        return val if val != 0 else None
    except ValueError:
        return None

def find_header(lines: list[str]) -> tuple[int, list[str]]:
    # 상단에 수입/지출 요약 블록이 있을 수 있으므로 넉넉히 20행까지 탐색
    for i, line in enumerate(lines[:20]):
        fields = next(csv.reader([line]))
        fields = [f.strip() for f in fields]
        if "날짜" in fields and "금액" in fields:
            return i, fields
    raise ValueError("헤더를 찾지 못했습니다. 처음 20행:\n" + "\n".join(lines[:20]))

def parse_csv(text: str) -> list[dict]:
    lines = [l for l in text.splitlines() if l.strip()]
    header_idx, header = find_header(lines)

    def col(names):
        for n in names:
            for i, h in enumerate(header):
                if n in h:
                    return i
        return None

    date_col    = col(["날짜"])
    time_col    = col(["시간"])
    type_col    = col(["분류"])
    channel_col = col(["구분"])          # 계좌 / 카드 / 페이 (있으면 분류 신뢰도↑)
    method_col  = col(["거래수단", "출금처"])
    title_col   = col(["거래내역"])
    amount_col  = col(["금액"])
    status_col  = col(["승인상태"])

    rows = []
    reader = csv.reader(lines[header_idx + 1:])
    for fields in reader:
        fields = [f.strip() for f in fields]
        if len(fields) <= (date_col or 0):
            continue

        date_raw = fields[date_col] if date_col is not None else ""
        time_raw = fields[time_col].replace(":", "") if time_col is not None and len(fields) > time_col else "0000"
        tx_type  = fields[type_col]   if type_col   is not None and len(fields) > type_col   else ""
        channel  = fields[channel_col] if channel_col is not None and len(fields) > channel_col else ""
        method   = fields[method_col] if method_col is not None and len(fields) > method_col else ""
        title    = fields[title_col]  if title_col  is not None and len(fields) > title_col  else ""
        amt_raw  = fields[amount_col] if amount_col is not None and len(fields) > amount_col else ""
        status   = fields[status_col] if status_col is not None and len(fields) > status_col else ""

        # 날짜 정규화: YYYY.MM.DD, YYYY/MM/DD → YYYY-MM-DD
        date_clean = re.sub(r"[./]", "-", date_raw.strip())
        if not re.match(r"\d{4}-\d{2}-\d{2}", date_clean):
            continue

        amount = parse_amount(amt_raw)
        if amount is None:
            continue

        rows.append({
            "date":    date_clean[:10],
            "time":    time_raw[:4].zfill(4),
            "type":    tx_type,
            "channel": channel,          # 계좌/카드/페이 (없으면 "")
            "method":  method,
            "title":   title,
            "amount":  amount,
            "status":  status,
        })
    return rows


# ──────────────────────────────────────────
# 중복/이체 판정용 상수·헬퍼
# ──────────────────────────────────────────
PAY_METHOD_KW   = ["카카오페이", "토스", "네이버페이", "페이", "머니", "포인트"]
BANK_MOVE_TITLES = {"출금", "입금", "이체", "송금", "대체", "자동이체"}
CANCEL_KW       = ["취소", "환불", "반환", "정정", "결제취소"]
CARD_BILL_KW    = ["카드대금", "결제대금", "청구대금"]
CARD_NAMES      = ["현대카드", "삼성카드", "신한카드", "국민카드", "KB국민카드",
                   "우리카드", "롯데카드", "하나카드", "BC카드", "비씨카드",
                   "농협카드", "NH카드", "씨티카드"]
SPEND_CATS      = {"카페/간식", "구독", "쇼핑", "교통", "식비", "주거/통신",
                   "의료/건강", "여가/문화", "교육", "경조사/선물"}
GENERIC_TITLES  = {"출금", "입금", "카카오페이", "토스", "토스페이", "네이버페이",
                   "이체", "송금", "대체", "PAY 결제", "pay 결제", "결제", ""}

# 앱이 합계에서 제외하는 버킷(category == "이체")으로 보내되 원본은 보존
EXCLUDE_CATEGORY = "이체"

def is_pay_method(r: dict) -> bool:
    """간편결제(카카오/토스/네이버 등). '구분' 칼럼 우선, 없으면 거래수단 키워드."""
    ch = (r.get("channel") or "").strip()
    if ch:
        return ch == "페이"
    return any(k in r["method"] for k in PAY_METHOD_KW)

def is_card_method(r: dict) -> bool:
    """카드(신용/체크). '구분' 칼럼 우선, 없으면 거래수단 키워드."""
    ch = (r.get("channel") or "").strip()
    if ch:
        return ch == "카드"
    return "카드" in r["method"]

def is_bank_account(r: dict) -> bool:
    """은행 계좌. '구분' 칼럼 우선."""
    ch = (r.get("channel") or "").strip()
    if ch:
        return ch == "계좌"
    return not is_pay_method(r) and not is_card_method(r)

def is_bank_move(r: dict) -> bool:
    """은행 계좌의 단순 이동(출금/입금/이체) 행"""
    return (not is_pay_method(r)) and (r["title"].strip() in BANK_MOVE_TITLES)

def is_generic_title(t: str) -> bool:
    return t.strip() in GENERIC_TITLES

def _norm_title(t: str) -> str:
    t = re.sub(r"\(주\)|주식회사|㈜|유한회사|_가승인|가승인", "", t)
    t = re.sub(r"\s+", " ", t).strip().lower()
    return t


# ──────────────────────────────────────────
# 정제 규칙 (명세서 기반 dedup 파이프라인)
#   원본은 삭제하지 않고, KEEP 이 아닌 행은 category="이체" + memo 사유로 보존.
#   (앱은 category=="이체" 를 수입/지출 합계에서 제외하므로 부풀림이 사라짐)
#   예외: SSG(제외 대상 결제수단)와 완전중복 복사본만 실제 삭제.
# ──────────────────────────────────────────
def clean(rows: list[dict], holder: str | None = None,
          manual_excludes: list[dict] | None = None) -> dict:
    stats = {
        "ssg_excluded": 0,          # 완전 삭제
        "manual_excluded": 0,       # 완전 삭제(사용자 지정)
        "exact_dup_removed": 0,     # 완전 삭제(동일 행 반복)
        "cancel_refund_pairs": 0,   # 이체 보존
        "card_account_mirror": 0,   # 이체 보존(카드승인+계좌출금 동시기록)
        "self_transfer": 0,         # 이체 보존(본인 계좌 간 이동)
        "forex_reclassified": 0,    # 이체 보존
        "card_bill_excluded": 0,    # 이체 보존
        "chain_transfer_excluded": 0,  # 이체 보존(간편결제 체인/내부이체)
        "savings_classified": 0,
        "kept": 0,
    }
    holder = (holder or "").strip()

    # 작업용 필드 초기화
    for r in rows:
        r["_exclude_reason"] = None   # None이면 KEEP, 문자열이면 이체 보존
        r["_drop"] = False            # True면 완전 삭제

    # ── 0) 사용자 수동 제외 목록 → 완전 삭제 ──────────────
    #   manual_excludes.json 의 {date, amount, title} 와 일치하는 행을 영구 삭제.
    #   (amount/title 은 선택; title 은 부분일치. 재가져오기해도 다시 살아나지 않음)
    for ex in (manual_excludes or []):
        ed, ea, et = ex.get("date"), ex.get("amount"), ex.get("title")
        for r in rows:
            if r["_drop"]:
                continue
            if ed and r["date"] != ed:
                continue
            if ea is not None and r["amount"] != ea:
                continue
            if et and et not in r["title"]:
                continue
            r["_drop"] = True
            stats["manual_excluded"] += 1

    # ── 1) SSG(제외 대상 결제수단) 완전 삭제 ──────────────────────
    for r in rows:
        if r["_drop"]:
            continue
        if "ssg" in r["method"].lower() or "ssg.com" in r["title"].lower():
            r["_drop"] = True
            stats["ssg_excluded"] += 1

    alive = [r for r in rows if not r["_drop"]]

    # ── 2) 완전 중복(동일 날짜/시간/금액/내용/출처 반복) 복사본 삭제 ──
    seen = set()
    for r in alive:
        key = (r["date"], r["time"], r["amount"], _norm_title(r["title"]), r["method"])
        if key in seen:
            r["_drop"] = True
            stats["exact_dup_removed"] += 1
        else:
            seen.add(key)

    alive = [r for r in rows if not r["_drop"]]

    # ── 3) 취소/환불 상쇄 판정 ───────────────────────────
    #   status=="취소" 또는 취소/환불 키워드가 있는 행을, 같은 날·같은 금액의
    #   반대 방향 정상거래와 쌍으로 묶어 둘 다 '이체'로 제외. 짝이 없으면 단독 제외.
    used = set()
    for r in alive:
        is_cancel = r["status"] == "취소" or any(k in r["title"] for k in CANCEL_KW)
        if not is_cancel or r["_exclude_reason"] or id(r) in used:
            continue
        partner = None
        for o in alive:
            if id(o) in used or o is r or o["_exclude_reason"]:
                continue
            if (o["date"] == r["date"] and abs(o["amount"]) == abs(r["amount"])
                    and (o["amount"] > 0) != (r["amount"] > 0)
                    and _norm_title(o["title"]) == _norm_title(r["title"])):
                partner = o
                break
        r["_exclude_reason"] = "취소/환불 상쇄"
        used.add(id(r))
        if partner:
            partner["_exclude_reason"] = "취소/환불 상쇄(원거래)"
            used.add(id(partner))
            stats["cancel_refund_pairs"] += 1
        else:
            stats["cancel_refund_pairs"] += 1  # 단독 취소(가승인 등)

    # ── 4) 환전 쌍 → 이체 보존 ───────────────────────────
    for r in alive:
        if r["_exclude_reason"]:
            continue
        if "환전" in r["title"]:
            r["_exclude_reason"] = "환전(통화 교환)"
            stats["forex_reclassified"] += 1

    # ── 4.5) 본인 계좌 간 이체 → 이체 보존 ───────────────
    #   제목이 계좌주 본인 이름과 정확히 일치하면 자기 계좌 사이 자금 이동.
    #   (예: 파일명 '홍길동_...' → 제목 '홍길동' 행. '기관명_홍길동' 형태는 제외)
    if holder:
        for r in alive:
            if r["_exclude_reason"]:
                continue
            if r["title"].strip() == holder:
                r["_exclude_reason"] = "본인 계좌 간 이체"
                stats["self_transfer"] += 1

    # ── 5) 카드대금/청구 출금 → 이체 보존 (개별 카드승인이 이미 있음) ──
    #   '카드대금/청구' 키워드 또는 카드사명이 제목인 계좌 출금(개별 승인은 별도 존재).
    for r in alive:
        if r["_exclude_reason"]:
            continue
        title = r["title"]
        is_card_bill = any(k in title for k in CARD_BILL_KW) or (
            any(n in title for n in CARD_NAMES) and not is_pay_method(r)
            and not is_card_method(r)  # 카드 자체 승인내역이 아닌 '계좌'에서의 출금
        )
        if is_card_bill:
            r["_exclude_reason"] = "카드대금 정산(개별 승인내역 유지)"
            stats["card_bill_excluded"] += 1

    # ── 5.5) 환불 추정: 양수인데 소비 가맹점으로 분류되는 행 → 이체 보존 ──
    #   (예: 쿠팡 +30,000 은 수입이 아니라 환불) 수입 부풀림 방지.
    for r in alive:
        if r["_exclude_reason"]:
            continue
        if r["amount"] > 0 and categorize(r["title"], r["amount"]) in REFUND_CATS:
            r["_exclude_reason"] = "환불 추정(분류 확인 필요)"
            stats["cancel_refund_pairs"] += 1

    # ── 6) 같은 분(分)·같은 금액 클러스터 통합 정리 ─────────
    #   key = (날짜, 시각HHMM, 금액절댓값). 같은 분에 같은 금액이 여러 줄이면
    #   한 번의 경제 행위가 카드/계좌/간편결제 여러 원장에 동시 기록된 것.
    #     · 같은 방향만 여럿(±부호 일치)  → '미러 중복' → 대표 1건만 KEEP
    #     · 지출과 수입이 섞임            → '이체/충전 체인' → 순합계만큼만 KEEP
    def exp_rank(r):
        if not is_generic_title(r["title"]):
            return (0, 0 if is_card_method(r) else 1)  # 실제 가맹점(카드 우선)
        if is_pay_method(r):
            return (1, 0)   # 간편결제 결제(가맹점명 없음)
        return (2, 0)       # 은행 단순 출금
    def inc_rank(r):
        if not is_generic_title(r["title"]):
            return (0, 0)   # 실제 입금(이름/급여/이자 등)
        if not is_pay_method(r):
            return (1, 0)   # 은행 단순 입금
        return (2, 0)       # 간편결제 충전(+)

    clusters: dict[tuple, list] = defaultdict(list)
    for r in alive:
        if r["_exclude_reason"]:
            continue
        clusters[(r["date"], r["time"][:4], abs(r["amount"]))].append(r)

    for (date, hm, absamt), group in clusters.items():
        if len(group) < 2 or absamt == 0:
            continue
        for r in group:
            r["_chain_seen"] = True

        exps = [r for r in group if r["amount"] < 0]
        incs = [r for r in group if r["amount"] > 0]
        keep_ids = set()

        if exps and incs:
            # 이체/충전 체인: 순합계가 실현하는 실제 건수(|k|)만큼은 반드시 KEEP.
            #   (좋은 대표를 우선하되, 모자라면 차선으로 채워 '순수입/순지출'이 사라지지 않게 함)
            net = sum(r["amount"] for r in group)
            k = round(net / absamt)
            if k < 0:
                for r in sorted(exps, key=exp_rank)[:abs(k)]:
                    keep_ids.add(id(r))
            elif k > 0:
                for r in sorted(incs, key=inc_rank)[:k]:
                    keep_ids.add(id(r))
            # k==0 → 순이동 0 (충전/이체가 서로 상쇄) → 전부 제외
            reason = "간편결제/이체 자동정리(합계 보존)"
        else:
            # 미러 중복: 같은 방향·동일 금액·동일 시각 → 한 거래의 다중 기록 → 대표 1건만 KEEP
            side = exps if exps else incs
            rank = exp_rank if exps else inc_rank
            rep = sorted(side, key=rank)[0]
            keep_ids.add(id(rep))
            reason = "카드-계좌/간편결제 동시기록 정리"

        for r in group:
            if id(r) not in keep_ids:
                r["_exclude_reason"] = reason
                if reason.startswith("카드-계좌"):
                    stats["card_account_mirror"] += 1
                else:
                    stats["chain_transfer_excluded"] += 1

    # ── 6.5) 체인에 묶이지 않은 단독 '출금/입금/이체' → 이체 보존 ──
    #   짝이 없는 맨 입출금은 계좌 이동일 가능성이 높아 합계에서 빼고 보존(검토용).
    for r in alive:
        if r["_exclude_reason"] or r.get("_chain_seen"):
            continue
        if is_bank_move(r):
            r["_exclude_reason"] = "계좌 입출금(분류 확인 필요)"
            stats["chain_transfer_excluded"] += 1

    # ── 7) 카테고리 확정 ─────────────────────────────────
    #   사용자 정책: [분석제외](취소/환불·미러·이체·환전·카드대금·본인이체 등)는
    #   목록에서 완전히 제외. 실제 소비/수입(KEEP)만 남긴다.
    out = []
    for r in rows:
        if r["_drop"] or r["_exclude_reason"]:
            continue
        cat = categorize(r["title"], r["amount"])
        if cat == EXCLUDE_CATEGORY:   # 제목상 이체/송금성 → 내부이동 → 목록 제외
            stats["chain_transfer_excluded"] += 1
            continue
        # 양수(입금)인데 소비성 카테고리로 잡히면 수입으로 표기(가게명 더치페이 정산 등)
        if r["amount"] > 0 and cat in SPEND_CATS:
            cat = "수입"
        r["category"] = cat
        r["memo"] = ""
        stats["kept"] += 1
        if r["category"] == "저축":
            stats["savings_classified"] += 1
        out.append(r)

    return {"rows": out, "stats": stats}


# ──────────────────────────────────────────
# data.json 병합
# ──────────────────────────────────────────
def merge(rows: list[dict], data_json_path: str) -> dict:
    path = Path(data_json_path).expanduser()
    if not path.exists():
        raise FileNotFoundError(
            f"data.json을 찾을 수 없습니다: {path}\n"
            "MyAsset 앱을 한 번 실행해서 파일을 생성하세요."
        )

    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    existing = data.get("transactions", [])

    # 기존 레코드의 date 를 모두 Double 로 정규화(이전 버전이 남긴 ISO 문자열 마이그레이션)
    migrated = 0
    for tx in existing:
        if isinstance(tx.get("date"), str):
            ref = any_date_to_ref(tx["date"])
            if ref is not None:
                tx["date"] = ref
                migrated += 1

    # ── 기간 교체 방식 ──────────────────────────────────
    #   가져온 파일이 다루는 날짜 범위(min~max)는 이 파일이 '정본'이므로,
    #   그 기간의 기존 자동가져오기 거래는 제거하고 새 정제 결과로 교체한다.
    #   (이전 버그 버전 잔재·고아 레코드·이중계상 방지, 매월 재가져오기에 안전)
    #   기간 밖 거래와, 사용자가 직접 단 메모가 있는 거래는 보존한다.
    days = sorted(r["date"] for r in rows)
    dmin, dmax = days[0], days[-1]

    def in_period(tx) -> bool:
        return dmin <= ref_to_day_key(tx.get("date")) <= dmax

    def user_edited(tx) -> bool:
        memo = tx.get("memo") or ""
        return bool(memo) and not memo.startswith("[분석 제외]")

    kept_existing, replaced = [], 0
    for tx in existing:
        if in_period(tx) and not user_edited(tx):
            replaced += 1            # 교체 대상 → 제거
        else:
            kept_existing.append(tx)  # 기간 밖 또는 사용자 편집 → 보존

    new_txs = [{
        "id":            str(uuid.uuid4()),
        "date":          ymd_hm_to_ref(r["date"], r["time"]),  # Double (앱 호환)
        "title":         r["title"],
        "amount":        r["amount"],
        "category":      r["category"],
        "accountID":     None,
        "memo":          r.get("memo", ""),
        "paymentMethod": r.get("method", ""),   # 거래수단(현대카드X / 카카오페이 머니 / 계좌명)
    } for r in rows]

    data["transactions"] = sorted(
        kept_existing + new_txs,
        key=lambda x: any_date_to_ref(x.get("date")) or 0.0,
        reverse=True
    )

    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)

    return {"added": len(new_txs), "replaced": replaced, "migrated": migrated}


# ──────────────────────────────────────────
# 메인
# ──────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="MyAsset 은행 거래내역 가져오기")
    parser.add_argument("--file",      required=True,            help="XLS 파일 경로")
    parser.add_argument("--password", help="XLS 비밀번호 (로컬 설정을 덮어씀)")
    parser.add_argument("--data-json", required=True,            help="data.json 경로")
    args = parser.parse_args()

    file_date = extract_date_from_filename(args.file)
    if file_date:
        y, m, _ = file_date.split("-")
        print(f"📅 파일 기준일: {y}년 {int(m)}월")

    print(f"📂 파일 변환 중: {Path(args.file).name}")
    password = args.password or os.environ.get("MYASSET_IMPORT_PASSWORD")
    if not password:
        password_file = Path.home() / "Library/Application Support/MyAsset/import-password.txt"
        if password_file.is_file():
            password = password_file.read_text(encoding="utf-8").rstrip("\r\n")
    csv_text = xls_to_csv(args.file, password)

    print("🔍 파싱 중...")
    rows = parse_csv(csv_text)
    print(f"   원본 행 수: {len(rows)}건")

    # 계좌주 본인 이름(파일명 맨 앞 토큰) → 본인 계좌 간 이체 판정에 사용
    holder = re.split(r"[_\d]", Path(args.file).stem, 1)[0].strip()

    # 사용자 수동 제외 목록(스크립트와 같은 폴더의 manual_excludes.json)
    manual_excludes = []
    mx_path = Path(__file__).resolve().parent / "manual_excludes.json"
    if mx_path.exists():
        try:
            manual_excludes = json.loads(mx_path.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"⚠️  manual_excludes.json 읽기 실패: {e}")

    print("🧹 정제 중...")
    cleaned = clean(rows, holder=holder, manual_excludes=manual_excludes)
    stats   = cleaned["stats"]
    clean_rows = cleaned["rows"]
    print(f"   정제 후: {len(clean_rows)}건")

    if not clean_rows:
        print("⚠️  정제 후 유효한 거래가 없습니다.")
        sys.exit(0)

    dates  = sorted(r["date"] for r in clean_rows)
    period = f"{dates[0]} ~ {dates[-1]}"

    print("💾 data.json 병합 중...")
    result = merge(clean_rows, args.data_json)

    excluded_total = (stats["chain_transfer_excluded"] + stats["forex_reclassified"]
                      + stats["card_bill_excluded"] + stats["cancel_refund_pairs"]
                      + stats["card_account_mirror"] + stats["self_transfer"])

    print(f"""
✅ 거래내역 업데이트 완료
• 파일 기준일: {file_date if file_date else "알 수 없음"}
• 거래 기간:  {period}
• 목록 등록(실제 소비/수입): {result['added']}건
• 정제로 제외(목록에서 삭제): {excluded_total + stats['ssg_excluded'] + stats['exact_dup_removed']}건
   - 간편결제/내부이체 정리: {stats['chain_transfer_excluded']}건
   - 카드-계좌 동시기록: {stats['card_account_mirror']}건
   - 본인 계좌 간 이체: {stats['self_transfer']}건
   - 환전: {stats['forex_reclassified']}건
   - 취소/환불: {stats['cancel_refund_pairs']}건
   - 카드대금 정산: {stats['card_bill_excluded']}건
   - SSG(타인): {stats['ssg_excluded']}건 / 완전중복: {stats['exact_dup_removed']}건
   - 수동 제외(사용자 지정): {stats['manual_excluded']}건
• 같은 기간 기존 거래 교체: {result['replaced']}건
• 저축 분류: {stats['savings_classified']}건 (군인공제회 등)
• 원본 검증이 필요하면 imported/ 의 XLS 파일을 참고하세요
""")

if __name__ == "__main__":
    main()
