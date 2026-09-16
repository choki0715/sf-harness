#!/usr/bin/env python3
"""PreToolUse 훅 — 되돌릴 수 없는 설비 조치를 실행 전에 막는다.

수업 포인트: 훅은 '설득되지 않는' 안전장치다.

  스킬에 "승인은 사람이 한다"라고 써두면 대체로 지킨다.
  대체로. 진동이 CRIT 연속 12샘플이고 사용자가 "빨리 승인해서 세워"라고 재촉하면
  LLM 은 스스로를 설득할 수 있다. 훅은 프롬프트가 아니라 코드다. 협상 대상이 아니다.

  이 훅이 막는 것은 네 가지뿐이다. 전부 되돌리기 어렵거나 안전과 직결된다.
    1. 최종 결정 (sf-actuate approve / reject) — 제안까지가 에이전트의 일이다. 결정은 사람이 한다
    2. 설비 정지 (sf-actuate stop)             — 가공 중인 제품 폐기, 재가동에 수십 분
    3. 원본 센서 로그 삭제·덮어쓰기 (signals/) — 사고 조사의 증거가 사라진다
    4. 한계값 수정 (config/thresholds.csv)     — 경보를 없애는 가장 쉬운 방법은 기준을 올리는 것이다.
                                                  모델이 이 유혹에 빠지지 않게 아예 막는다

  규칙 1: 되돌릴 수 있는 일(제안 기록, 작업지시 발행, 속도 저감)은 스킬에 맡기고,
          되돌릴 수 없는 일만 훅으로 막는다. 훅이 많으면 에이전트가 아무 일도 못 한다.

  규칙 2: 가드레일에는 범위를 준다. 이 훅은 플러그인이 전역으로 걸기 때문에 모든 프로젝트에서 돈다.
          1·2 는 우리 명령(sf-actuate)이라 어디서든 막아도 남을 막을 일이 없다.
          3·4 는 `signals`, `thresholds.csv` 라는 흔한 이름이라, 그 파일이 `.sf-harness` 마커 아래에
          있을 때만 막는다. 경로는 명령에 적힌 것과 현재 디렉터리 둘 다 본다 —
          어느 디렉터리에서 Claude 를 띄웠든 `rm /tmp/sf-demo/signals/x.csv` 는 막혀야 한다.

한계를 분명히 알고 쓴다: 훅은 셸 파서가 아니라 정규식이다.
변수 확장(`$CMD approve`), python -c 로 파일 열기, 별칭으로 우회할 수 있다.
이건 샌드박스가 아니라 과속방지턱이다 — 실수를 막지, 공격을 막지 않는다.

표준 라이브러리만 쓴다.
"""

from __future__ import annotations

import json
import os
import re
import sys

MARKER = ".sf-harness"
ENV_SWITCH = "SF_HARNESS_GUARD"
DEFAULT_PLANT = "/tmp/sf-demo"

# 명령의 '시작 위치'만 본다. 이게 없으면 `echo "sf-actuate approve 예시"` 같은
# 따옴표 안 문자열까지 명령으로 오인한다.
CMD_START = r"(?:\A|[;&|]|\n)\s*(?:sudo\s+)?"

# ── 1·2: 우리 명령. 범위와 무관하게 막는다 ──────────────────────
# sf-actuate [--옵션 값 ...] <서브커맨드>   — 서브커맨드 자리만 본다. --reason "stop" 같은 인자는 잡지 않는다
ACTUATE_RULES = [
    (re.compile(CMD_START + r"(?:\S*/)?sf-actuate\s+(?:-\S+\s+\S+\s+)*(?:approve|reject)\b"),
     "제안의 승인·기각은 사람이 한다. 에이전트는 propose 까지다.\n"
     "대기 중 제안(DEC-xxxx)과 근거를 보고하고, 운영자가 터미널에서 approve / reject 를 친다."),
    (re.compile(CMD_START + r"(?:\S*/)?sf-actuate\s+(?:-\S+\s+\S+\s+)*(?:stop|emergency-stop)\b"),
     "설비 정지는 되돌릴 수 없다. 에이전트가 실행하지 않는다.\n"
     "sf-actuate propose <설비> stop --reason ... 으로 제안하고, 승인·실행은 운영자가 한다."),
]

# ── 3·4: 흔한 파일 이름. 마커 범위 안에서만 막는다 ───────────────
FILE_RULES = [
    (re.compile(CMD_START + r"(?:rm|shred|truncate|unlink|mv)\s[^;&|\n]*(?<![\w.-])signals\b"),
     "원본 센서 로그(signals/)는 사고 조사의 증거다. 지우거나 옮기지 않는다."),
    (re.compile(r"(?<!\d)>{1,2}\s*[^;&|\n\s]*(?<![\w.-])signals/"),
     "원본 센서 로그(signals/)에 덮어쓰지 않는다. 가공 결과는 다른 파일에 쓴다."),
    (re.compile(CMD_START + r"(?:sed\s+-i|tee|cp|mv|rm|truncate)\b[^;&|\n]*thresholds\.csv"),
     "한계값(config/thresholds.csv)은 안전 기준이다. 경보를 없애려고 기준을 바꾸지 않는다.\n"
     "기준이 잘못됐다고 판단되면 근거를 보고하고, 변경은 설비 담당자가 한다."),
    (re.compile(r"(?<!\d)>{1,2}\s*\S*thresholds\.csv"),
     "한계값(config/thresholds.csv)에 덮어쓰지 않는다. 변경은 설비 담당자가 한다."),
]

# 파일 편집 도구(Write/Edit)로 우회하는 것도 막는다. Bash 만 막으면 반쪽이다.
PROTECTED_FILE = re.compile(r"(?:^|/)(?:config/thresholds\.csv|signals/[^/]+\.csv)$")

# 명령 안에서 경로처럼 보이는 토큰: signals 나 thresholds.csv 를 담은 것만 본다
PATH_TOKEN = re.compile(r"[\"']?([^\s\"';&|<>]*(?:signals|thresholds\.csv)[^\s\"';&|<>]*)")


def deny(reason: str) -> None:
    """실행을 막고, LLM 에게 '왜' 막혔는지 알려준다.

    이유를 붙이는 게 중요하다. 이유 없이 막으면 LLM 은 같은 명령을
    조금 바꿔서 다시 시도한다. 이유를 주면 다른 방법을 찾는다.
    """
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))
    raise SystemExit(0)


def has_marker_above(path: str) -> bool:
    """path 에서 위로 올라가며 마커를 찾는다. git 저장소가 아니어도 된다."""
    cur = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(cur, MARKER)):
            return True
        parent = os.path.dirname(cur)
        if parent == cur:
            return False
        cur = parent


def file_in_scope(data: dict, command: str) -> bool:
    """signals/·thresholds.csv 규칙을 적용할 것인가 — 그 파일이 마커 아래에 있는가."""
    if os.environ.get(ENV_SWITCH) == "1":
        return True
    cwd = data.get("cwd") or os.getcwd()
    if has_marker_above(cwd):
        return True
    # 명령에 적힌 경로 (절대 경로, 또는 cwd 기준 상대 경로). ~ 도 푼다
    for token in PATH_TOKEN.findall(command):
        p = os.path.expanduser(token)
        if not os.path.isabs(p):
            p = os.path.join(cwd, p)
        if has_marker_above(os.path.dirname(p) if not os.path.isdir(p) else p):
            return True
    return False


def main() -> int:
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0    # 입력이 깨졌으면 통과시킨다. 훅 버그로 작업을 막지 않는다

    tool = data.get("tool_name")
    if tool not in ("Bash", "Write", "Edit", "MultiEdit"):
        return 0

    tool_input = data.get("tool_input") or {}

    if tool == "Bash":
        command = tool_input.get("command", "")
        for pattern, reason in ACTUATE_RULES:            # 우리 명령: 어디서든
            if pattern.search(command):
                deny(f"{reason}\n실행하려던 명령: {command}")
        if file_in_scope(data, command):                  # 흔한 이름: 마커 범위 안에서만
            for pattern, reason in FILE_RULES:
                if pattern.search(command):
                    deny(f"{reason}\n실행하려던 명령: {command}")
        return 0

    file_path = tool_input.get("file_path", "")
    if file_path and PROTECTED_FILE.search(file_path.replace(os.sep, "/")) \
            and (os.environ.get(ENV_SWITCH) == "1" or has_marker_above(os.path.dirname(os.path.abspath(file_path)))):
        deny("원본 센서 로그(signals/)와 한계값(config/thresholds.csv)은 편집하지 않는다.\n"
             "분석 결과는 다른 파일에 쓰고, 기준 변경은 설비 담당자가 한다.\n"
             f"편집하려던 파일: {file_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
