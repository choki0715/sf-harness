---
description: 2단계 분석 — 저장된 센서 신호에서 사실을 뽑고 설비별 소견을 낸다
argument-hint: [플랜트 경로] [--window 분] (생략하면 현재 디렉터리, 60분)
allowed-tools: Bash, Read, Write, Grep, Glob
---

센서 신호 사실:
!`for _c in "$CLAUDE_PLUGIN_ROOT/bin/sf-signals" "$(readlink -f "$HOME/.claude/skills/sf-harness" 2>/dev/null)/bin/sf-signals" "$(command -v sf-signals 2>/dev/null)"; do [ -x "$_c" ] && { "$_c" $ARGUMENTS 2>&1; exit 0; }; done; echo "ERROR: sf-signals 를 찾지 못했다 — 설치를 확인해라"`

---

`analyze` 스킬을 따라라.

위 STATUS 라인이 **사실이다.** 평균·추세·연속 횟수를 다시 계산하지 마라. signals/ 의 CSV 를 다시 읽지 마라.
이 단계의 산출물은 **소견**이다. 조치를 제안하거나 실행하지 마라 — 그것은 `decide` 단계의 일이다.
