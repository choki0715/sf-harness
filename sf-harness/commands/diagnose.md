---
description: 저장된 설비 센서 신호를 분석해 조치를 권고한다
argument-hint: [플랜트 데이터 경로] [--window 분] (생략하면 현재 디렉터리, 60분)
allowed-tools: Bash, Read, Grep, Glob
---

센서 신호 사실:
!`for _c in "$CLAUDE_PLUGIN_ROOT/bin/sf-signals" "$(readlink -f "$HOME/.claude/skills/sf-harness" 2>/dev/null)/bin/sf-signals" "$(dirname "$(readlink -f "$HOME/.claude/skills/diagnose" 2>/dev/null)")/../bin/sf-signals" "$(command -v sf-signals 2>/dev/null)"; do [ -x "$_c" ] && { "$_c" $ARGUMENTS 2>&1; exit 0; }; done; echo "ERROR: sf-signals 를 찾지 못했다 — 설치를 확인해라"`

열린 작업지시:
!`_p="$(for a in $ARGUMENTS; do case "$a" in -*) ;; *) echo "$a"; break;; esac; done)"; for _c in "$CLAUDE_PLUGIN_ROOT/bin/sf-actuate" "$(readlink -f "$HOME/.claude/skills/sf-harness" 2>/dev/null)/bin/sf-actuate" "$(command -v sf-actuate 2>/dev/null)"; do [ -x "$_c" ] && { "$_c" --plant "${_p:-.}" list 2>&1; exit 0; }; done; echo "ERROR: sf-actuate 를 찾지 못했다"`

---

`diagnose` 스킬을 따라라.

위 STATUS 라인이 **사실이다.** 평균·추세·연속 횟수를 다시 계산하지 마라. signals/ 의 CSV 를 다시 읽지 마라.
설비 정지(`sf-actuate stop`)는 실행하지 마라 — 권고와 근거를 보고하고, 실행은 운영자가 한다.
