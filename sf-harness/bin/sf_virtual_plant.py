"""sf_virtual_plant — 가상 플랜트. sf-demo-data 와 sf-collect 가 같이 쓴다.

실제 공장에서는 PLC·게이트웨이가 센서 값을 signals/ 에 쌓는다. 실습에서는 그 자리를
이 모듈이 대신한다. 설비 4대의 센서 값을 **가상 시각 t(분)** 의 함수로 정의해 두고,
sf-collect 가 시계를 앞으로 돌리며 값을 받아 signals/ 에 추가한다.

  t = 0    플랜트 생성 시점 (state.json 의 epoch). 이력은 t = -120 … -1 로 만든다
  t > 0    sf-collect 가 수집할 때마다 늘어난다

값은 (설비, t) 로 시드를 고정한 난수라서 **누가 언제 몇 분씩 수집해도 같은 값**이 나온다.
그래야 학생 전원이 같은 화면을 보고, 테스트가 가능하다.

조치는 이후 값에 반영된다 (단순화한 모델이다):
  stop       → 정지 상태 값 (진동·전류 ≈ 0, 온도는 식은 값)
  set-speed  → 진동·전류가 속도 비율만큼 준다

시나리오 (설비마다 판단 재료가 하나씩 심겨 있다):
  CNC-01   스핀들 온도가 시간당 +4°C 로 계속 오른다 (t≈+60 에 WARN 70 도달). 전류 스파이크 t=-35, +25
  CNC-02   진동이 t=-12 부터 CRIT, 계속 상승. 온도도 t=-40 부터 상승해 WARN (t≈+22 에 CRIT 85)
  PRESS-01 압력 센서가 t=-30 부터 같은 값에 고착 (FLATLINE). cycle_time 센서는 아예 없다 (MISSING)
  CONV-01  t=-44 … +29 동안 데이터가 없다 (STALE). t=+30 부터 다시 들어온다
"""

from __future__ import annotations

import json
import os
import random
from datetime import datetime, timedelta

TS_FMT = "%Y-%m-%dT%H:%M:%S"
HISTORY_MIN = 120          # 플랜트 생성 시 만들어 두는 이력(분)

# equipment, sensor, unit, lo_crit, lo_warn, hi_warn, hi_crit
THRESHOLDS = [
    ("CNC-01", "vibration", "mm/s", "", "", "4.5", "7.1"),
    ("CNC-01", "temperature", "C", "", "", "70", "85"),
    ("CNC-01", "current", "A", "", "", "38", "45"),
    ("CNC-02", "vibration", "mm/s", "", "", "4.5", "7.1"),
    ("CNC-02", "temperature", "C", "", "", "70", "85"),
    ("CNC-02", "current", "A", "", "", "38", "45"),
    ("PRESS-01", "pressure", "bar", "120", "140", "210", "230"),
    ("PRESS-01", "temperature", "C", "", "", "60", "70"),
    ("PRESS-01", "cycle_time", "s", "", "", "14", "18"),
    ("CONV-01", "current", "A", "", "", "22", "28"),
    ("CONV-01", "vibration", "mm/s", "", "", "3.0", "5.0"),
]
EQUIPMENT = list(dict.fromkeys(row[0] for row in THRESHOLDS))

# (설비, 며칠 전 정비, 종류, 메모)
MAINTENANCE = [
    ("CNC-01", 45, "preventive", "스핀들 윤활·벨트 장력 점검"),
    ("CNC-02", 10, "corrective", "공구 홀더 교체"),
    ("PRESS-01", 70, "preventive", "유압 오일 교체"),
    ("CONV-01", 27, "preventive", "롤러 베어링 점검"),
]


# ─── 상태 파일 ──────────────────────────────────────────────────
def state_path(plant: str) -> str:
    return os.path.join(plant, "state.json")


def load_state(plant: str) -> dict | None:
    p = state_path(plant)
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def save_state(plant: str, state: dict) -> None:
    with open(state_path(plant), "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
        f.write("\n")


def new_state(epoch: datetime) -> dict:
    return {
        "epoch": epoch.strftime(TS_FMT),
        "clock": epoch.strftime(TS_FMT),
        "equipment": {eq: {"status": "running", "speed": 100} for eq in EQUIPMENT},
    }


def t_of(state: dict, ts: datetime) -> int:
    """타임스탬프 → 가상 시각 t(분)"""
    epoch = datetime.strptime(state["epoch"], TS_FMT)
    return int((ts - epoch).total_seconds() // 60)


def ts_of(state: dict, t: int) -> datetime:
    return datetime.strptime(state["epoch"], TS_FMT) + timedelta(minutes=t)


# ─── 센서 값 ────────────────────────────────────────────────────
def readings(eq: str, t: int, eq_state: dict | None = None) -> list[tuple[str, float]]:
    """설비 eq 의 가상 시각 t 에서의 (센서, 값) 목록. 빈 목록이면 그 분에 데이터가 없는 것이다."""
    st = eq_state or {}
    stopped = st.get("status") == "stopped"
    speed = max(0, min(100, int(st.get("speed", 100)))) / 100

    r = random.Random(f"{eq}:{t}")       # (설비, 분) 마다 고정된 난수 → 언제 수집해도 같은 값
    n = r.gauss

    if eq == "CNC-01":
        if stopped:
            return [("vibration", 0.1 + n(0, 0.02)), ("temperature", 35 + n(0, 0.3)), ("current", 0.2 + n(0, 0.05))]
        temp = min(95, 58 + (t + HISTORY_MIN) * (8 / HISTORY_MIN) + n(0, 0.4))   # 시간당 +4°C
        cur = 46.2 if t in (-35, 25) else 30 + n(0, 1.0)                              # 1샘플 스파이크 두 번
        return [("vibration", (2.2 + n(0, 0.15)) * speed), ("temperature", temp), ("current", cur * speed)]

    if eq == "CNC-02":
        if stopped:
            return [("vibration", 0.1 + n(0, 0.02)), ("temperature", 35 + n(0, 0.3)), ("current", 0.2 + n(0, 0.05))]
        if t <= -30:
            vib = 2.5 + n(0, 0.15)
        elif t <= -13:
            vib = 2.5 + (t + 30) * (4.4 / 17) + n(0, 0.1)          # -30 … -13: 2.5 → 6.9 램프
        else:
            vib = min(12.0, 7.3 + (t + 12) * 0.1 + n(0, 0.05))     # -12 부터 ≥ 7.1 (CRIT 연속 12), 계속 상승
        temp = 60 + n(0, 0.4) if t <= -40 else min(92.0, 60 + (t + 40) * (16 / 39) + n(0, 0.4))
        return [("vibration", vib * speed), ("temperature", temp), ("current", (31 + n(0, 1.0)) * speed)]

    if eq == "PRESS-01":
        if stopped:
            return [("pressure", 0.0), ("temperature", 30 + n(0, 0.3))]
        pressure = 176.3 if t >= -30 else 175 + n(0, 2.0)          # -30 부터 같은 값에 고착
        return [("pressure", pressure), ("temperature", 48 + n(0, 0.5))]   # cycle_time 은 일부러 없다

    if eq == "CONV-01":
        if -44 <= t < 30:
            return []                                              # 통신 끊김
        if stopped:
            return [("current", 0.1 + n(0, 0.02)), ("vibration", 0.05 + n(0, 0.01))]
        return [("current", (18 + n(0, 0.6)) * speed), ("vibration", (1.8 + n(0, 0.1)) * speed)]

    return []


def append_rows(plant: str, eq: str, rows: list[tuple[str, str, float]]) -> None:
    """signals/<eq>.csv 에 (timestamp, sensor, value) 를 추가한다. 없으면 헤더부터 만든다."""
    path = os.path.join(plant, "signals", f"{eq}.csv")
    new = not os.path.exists(path)
    with open(path, "a", encoding="utf-8") as f:
        if new:
            f.write("timestamp,sensor,value\n")
        for ts, sensor, value in rows:
            f.write(f"{ts},{sensor},{value:.2f}\n")
