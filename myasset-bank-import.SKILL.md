---
name: myasset-bank-import
description: >
  MyAsset 앱에 은행 거래내역 XLS 파일을 가져올 때 사용하는 스킬.
  사용자가 .xls/.xlsx 파일을 주면서 "앱에 넣어줘", "업데이트해줘", "거래내역 반영해줘",
  "파일 줄게", "이번 달 내역 등록해줘" 같은 말을 할 때 반드시 이 스킬을 사용한다.
  파일 확장자가 xls/xlsx이고 은행·금융·거래내역과 관련된 요청이라면 무조건 이 스킬을 따른다.
  토스(Toss) 앱에서 내보낸 수입/지출 내역 형식에 최적화되어 있으며,
  SSG money 제외·카카오페이 중복 제거·군인공제회 저축 분류 등 개인화된 정제 규칙을 포함한다.
---

# MyAsset 은행 거래내역 가져오기

사용자가 XLS 파일을 주면, Cowork sandbox 는 user Mac 의 `~/Library/...` 에 직접 쓸 수 없으므로
**workspace 의 `incoming/` 폴더에 XLS 파일을 저장**한다. 그러면 user Mac 에서 돌고 있는
LaunchAgent(`com.myasset.importer`)가 이를 감지해 정제→`data.json` 병합까지 자동 처리한다.
앱은 FileSystemWatcher 로 변경을 감지하므로 재시작이 필요 없다.

## 중복/이체 정제 정책 (중요)

원본 XLS 의 거래를 그대로 넣지 않고, **실제 소비/수입만 목록에 등록**한다.
아래에 해당하는 행은 **목록에서 완전히 제외(삭제)** 한다 (합계·목록 모두 미포함):

- 완전 중복(동일 시각·금액·내용·출처 반복)
- 취소/환불 상쇄, 가승인 취소
- 카드승인+계좌출금 같은 한 거래의 다중 원장 기록(미러) → 1건만 유지
- 간편결제(카카오/토스) 충전·결제 체인의 충전/이체 다리 → 실제 결제만 유지
- 본인 계좌 간 이체(제목 = 계좌주 이름), 환전, 카드대금 정산, 송금/이체성 거래
- SSG money(제외 대상 결제수단)

각 거래에는 **결제수단(`paymentMethod`)** 필드도 함께 저장한다(현대카드X / 카카오페이 머니 / 계좌명).
앱의 '카드·결제수단' 화면이 이 값으로 거래를 묶어 보여준다.

판정 기준은 `(날짜, 시각HHMM, 금액)` 클러스터의 순합계와 제목/거래수단 신호를 사용한다.
원본 검증이 필요하면 `imported/` 폴더의 처리 완료 XLS 를 참고한다.
재가져오기 시 **해당 월(파일의 날짜 범위)을 통째로 새 정제본으로 교체**하므로
같은 파일을 다시 줘도 중복이 쌓이지 않는다(사용자가 직접 메모 단 거래·다른 달은 보존).

## 처리 흐름 (현재 아키텍처)

```
사용자가 XLS 첨부
  ↓
Claude: incoming/ 폴더에 XLS 저장      ← Claude 가 하는 일은 여기까지
  ↓
LaunchAgent: incoming/ 변경 즉시 감지 (+ 30초 백업 폴링)
  ↓
auto_import.sh → import_transactions.py 실행
  ↓
~/Library/Application Support/MyAsset/data.json 병합
  ↓
처리된 XLS → imported/ 이동 (실패 시 failed/ 이동 + 알림)
  ↓
앱 배너 "거래내역 N건 업데이트" 표시
```

## Claude 가 할 일

1. 첨부된 XLS 를 workspace 의 `incoming/` 폴더에 저장한다.
   - 경로: `/path/to/account_agent/incoming/<파일명>.xls`
2. (검증용) sandbox 에서 직접 파싱해 결과 건수를 미리 보고해도 좋다:
   ```bash
   SCRIPT="/path/to/account_agent/scripts/import_transactions.py"
   python3 "$SCRIPT" --file "<XLS 경로>" --data-json "<임시 data.json>"
   ```
   단, sandbox 의 임시 data.json 은 user Mac 에 반영되지 않는다. 실제 반영은 LaunchAgent 가 한다.
3. 사용자에게 "incoming/ 에 저장했고 곧 앱에 반영된다"고 알린다.

- 암호화된 XLS는 MyAsset 앱 데이터 폴더의 `import-password.txt` 또는 `MYASSET_IMPORT_PASSWORD`로 비밀번호를 설정한다.
- 파일명 `YYYYMMDDHHMMSS` → 파일 기준일 자동 추출.

## 입력 파일 형식 (토스 수입/지출내역 export)

- 상단에 `수입/지출내역` 제목과 `구분/지출/수입` 요약 블록이 있고, 그 아래 표 헤더가 온다.
  헤더는 첫 20행 내에서 `날짜`+`금액`이 모두 있는 행으로 자동 탐지한다.
- 표 칼럼: `날짜, 시간, 분류, 구분, 거래수단/출금처, 거래내역, 업종, 금액, 결제구분, 승인상태`
  - **분류**: 수입/지출
  - **구분**: 계좌/카드/페이 — 결제수단 종류 판정에 사용(있으면 우선, 없으면 거래수단 이름으로 추정)
  - **금액**: `+112원`, `-3,000원`처럼 부호·천단위콤마·원 표기 → 숫자로 정규화
  - **승인상태**: 정상/취소/할부 등 — `취소`는 취소/환불 처리

## 정제 규칙 (import_transactions.py 내장)

| 규칙 | 내용 |
|------|------|
| SSG money 제외 | 거래수단 "SSG" 또는 거래내역 "ssg.com" → 제외 |
| 카드 취소 제외 | 승인상태 "취소" → 제외 |
| 카카오페이 중복 | 동일 날짜+금액 미러 → 계좌 출금 1행만 유지 |
| 환전 처리 | 환전외화출금/원화입금 → 이체 분류 |
| 군인공제회 | 거래내역에 "군인공제회" → 카테고리 "저축" |
| 중복 방지 | data.json 기존 거래(날짜+금액+내용 키) → 건너뜀 |
| 날짜 정규화 | YYYY.MM.DD / YYYY/MM/DD → ISO 8601 저장 |

## 최초 1회 설치

`install_daemon.command` 더블클릭 → LaunchAgent 등록. 한 번만 하면 된다.

## 오류 대응

| 상황 | 조치 |
|------|------|
| data.json 없음 | MyAsset 앱을 한 번 실행해 파일 생성 |
| 처리 실패 | 파일이 `failed/` 로 이동 + macOS 알림. `/tmp/myasset_import.log` 확인 |
| 0건 추가 | 전부 중복 — 이미 최신 상태 |
