---
description: 3단계 의사결정 — 분석 소견을 바탕으로 조치를 제안한다 (실행은 사람이 승인해야)
argument-hint: [플랜트 경로] (생략하면 현재 디렉터리)
allowed-tools: Bash, Read, Grep, Glob
---

센서 신호 사실 (최신):
!`for _c in "$CLAUDE_PLUGIN_ROOT/bin/sf-signals" "$(readlink -f "$HOME/.claude/skills/sf-harness" 2>/dev/null)/bin/sf-signals" "$(command -v sf-signals 2>/dev/null)"; do [ -x "$_c" ] && { "$_c" $ARGUMENTS 2>&1; exit 0; }; done; echo "ERROR: sf-signals 를 찾지 못했다 — 설치를 확인해라"`

대기 중 제안·작업지시·설비 상태:
!`_p="$(for a in $ARGUMENTS; do case "$a" in -*) ;; *) echo "$a"; break;; esac; done)"; for _c in "$CLAUDE_PLUGIN_ROOT/bin/sf-actuate" "$(readlink -f "$HOME/.claude/skills/sf-harness" 2>/dev/null)/bin/sf-actuate" "$(command -v sf-actuate 2>/dev/null)"; do [ -x "$_c" ] && { "$_c" --plant "${_p:-.}" list 2>&1; exit 0; }; done; echo "ERROR: sf-actuate 를 찾지 못했다 — 설치를 확인해라"`

분석 소견 (analyze 단계가 쓴 것):
!`_p="$(for a in $ARGUMENTS; do case "$a" in -*) ;; *) echo "$a"; break;; esac; done)"; cat "${_p:-.}/reports/analysis.md" 2>/dev/null || echo "ANALYSIS_REPORT: 없음 — analyze 단계를 먼저 실행한다"`

---

`decide` 스킬을 따라라.

제안은 `sf-actuate propose` 로 **기록만** 한다. 승인(`approve`)·기각(`reject`)·정지(`stop`)는 사람이 한다. 실행하지 마라.
