#!/usr/bin/env python3
"""
설정한 지역의 날씨 자동 업데이트 스크립트
- 매일 오전 7시: 무조건 업데이트
- 그 외 시간: 마지막 업데이트 후 4시간 이상 경과 시 업데이트
- 데이터 출처: wttr.in (API 키 불필요)
"""

import json
import urllib.request
from urllib.parse import quote
import os
import sys
from datetime import datetime, timezone, timedelta

# ── 설정 ─────────────────────────────────────────────────────────────
WEATHER_PATH = os.path.expanduser("~/Library/Application Support/MyAsset/weather.json")
LOCATION = os.environ.get("MYASSET_WEATHER_LOCATION", "Seoul")
KST = timezone(timedelta(hours=9))
UPDATE_HOUR = 7          # 무조건 업데이트할 시각 (24h)
STALE_HOURS = 4          # 이 시간 이상 지나면 강제 갱신


# ── 업데이트 필요 여부 판단 ────────────────────────────────────────────
def should_update() -> bool:
    now = datetime.now(KST)

    # 매일 7시 → 무조건 갱신
    if now.hour == UPDATE_HOUR:
        return True

    # weather.json 없으면 갱신
    if not os.path.exists(WEATHER_PATH):
        return True

    # 마지막 업데이트 4시간 이상 경과 → 갱신
    try:
        with open(WEATHER_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        updated_at = datetime.fromisoformat(data["updatedAt"])
        age_hours = (now - updated_at).total_seconds() / 3600
        if age_hours >= STALE_HOURS:
            return True
        print(f"[스킵] 마지막 업데이트 {age_hours:.1f}시간 전 — 갱신 불필요")
        return False
    except Exception as e:
        print(f"[경고] weather.json 읽기 실패: {e} → 갱신 진행")
        return True


# ── wttr.in 데이터 수신 ───────────────────────────────────────────────
def fetch_weather() -> dict:
    url = f"https://wttr.in/{quote(LOCATION, safe='')}?format=j1"
    req = urllib.request.Request(url, headers={"User-Agent": "MyAssetApp/1.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


# ── 날씨 설명 → 한국어 condition 변환 ──────────────────────────────────
def to_korean_condition(desc: str) -> str:
    d = desc.lower()
    if any(k in d for k in ["thunder", "lightning"]):  return "천둥번개"
    if "snow" in d:                                      return "눈"
    if any(k in d for k in ["fog", "mist"]):             return "안개"
    if any(k in d for k in ["shower", "drizzle"]):       return "소나기"
    if "rain" in d:                                      return "비"
    if "overcast" in d:                                  return "흐림"
    if "cloudy" in d:
        return "구름조금" if any(k in d for k in ["partly", "partial"]) else "흐림"
    if any(k in d for k in ["sunny", "clear", "bright"]): return "맑음"
    if "cloud" in d:                                     return "구름조금"
    return "구름조금"


# ── 날짜 인덱스 → 요일 라벨 ──────────────────────────────────────────
def day_label(idx: int) -> str:
    if idx == 0: return "오늘"
    if idx == 1: return "내일"
    weekdays = ["월", "화", "수", "목", "금", "토", "일"]
    return weekdays[(datetime.now(KST) + timedelta(days=idx)).weekday()]


# ── raw JSON → WeatherData 변환 ──────────────────────────────────────
def build_weather_data(raw: dict) -> dict:
    now = datetime.now(KST)
    cur = raw["current_condition"][0]

    temp_c    = int(cur["temp_C"])
    humidity  = int(cur["humidity"])
    wind_ms   = round(float(cur["windspeedKmph"]) / 3.6, 1)
    uv        = int(cur.get("uvIndex", 0))
    desc_en   = cur["weatherDesc"][0]["value"]
    condition = to_korean_condition(desc_en)

    today_day = raw["weather"][0]
    high_c    = int(today_day["maxtempC"])
    low_c     = int(today_day["mintempC"])

    description = (
        f"{condition}. 최고 {high_c}°C / 최저 {low_c}°C. "
        f"습도 {humidity}%, 바람 {wind_ms}m/s."
    )

    weekly = []
    for i, day in enumerate(raw["weather"][:7]):
        noon_desc = day["hourly"][4]["weatherDesc"][0]["value"]
        weekly.append({
            "date":      day["date"],
            "dayLabel":  day_label(i),
            "condition": to_korean_condition(noon_desc),
            "tempHigh":  int(day["maxtempC"]),
            "tempLow":   int(day["mintempC"]),
        })

    return {
        "updatedAt": now.isoformat(timespec="seconds"),
        "location":  LOCATION,
        "today": {
            "date":        now.strftime("%Y-%m-%d"),
            "condition":   condition,
            "tempCurrent": temp_c,
            "tempHigh":    high_c,
            "tempLow":     low_c,
            "humidity":    humidity,
            "windSpeed":   wind_ms,
            "uvIndex":     uv,
            "description": description,
        },
        "weekly": weekly,
    }


# ── 메인 ──────────────────────────────────────────────────────────────
def main():
    if not should_update():
        sys.exit(0)

    print("🌤  날씨 데이터 수신 중 (wttr.in)...")
    try:
        raw = fetch_weather()
    except Exception as e:
        print(f"[오류] wttr.in 요청 실패: {e}")
        sys.exit(1)

    weather = build_weather_data(raw)

    os.makedirs(os.path.dirname(WEATHER_PATH), exist_ok=True)
    with open(WEATHER_PATH, "w", encoding="utf-8") as f:
        json.dump(weather, f, ensure_ascii=False, indent=2)

    t = weather["today"]
    print(
        f"✅ 업데이트 완료 [{weather['updatedAt']}] "
        f"{t['condition']} {t['tempCurrent']}°C "
        f"(최고 {t['tempHigh']}° / 최저 {t['tempLow']}°)"
    )


if __name__ == "__main__":
    main()
