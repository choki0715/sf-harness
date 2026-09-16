---
description: 3단계 의사결정 — 분석 소견을 바탕으로 조치를 제안한다 (실행은 사람이 승인해야)
argument-hint: [플랜트 경로] (생략하면 /tmp/sf-demo)
allowed-tools: Bash, Read, Grep, Glob
---

센서 신호 사실 (최신):
!`_b="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v sf-signals 2>/dev/null || echo /nonexistent/bin/x)")")}/bin"; [ -x "$_b/sf-signals" ] && "$_b/sf-signals" $ARGUMENTS 2>&1 || echo "ERROR: sf-signals 를 찾지 못했다 — 플러그인 설치를 확인해라 (/reload-plugins)"`

대기 중 제안·작업지시·설비 상태:
!`_p="$(for a in $ARGUMENTS; do case "$a" in -*) ;; *) echo "$a"; break;; esac; done)"; _p="${_p:-${SF_PLANT_DIR:-$([ -f config/thresholds.csv ] && echo . || echo /tmp/sf-demo)}}"; _b="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v sf-signals 2>/dev/null || echo /nonexistent/bin/x)")")}/bin"; [ -x "$_b/sf-actuate" ] && "$_b/sf-actuate" --plant "$_p" list 2>&1 || echo "ERROR: sf-actuate 를 찾지 못했다 — 플러그인 설치를 확인해라 (/reload-plugins)"`

분석 소견 (analyze 단계가 쓴 것):
!`_p="$(for a in $ARGUMENTS; do case "$a" in -*) ;; *) echo "$a"; break;; esac; done)"; _p="${_p:-${SF_PLANT_DIR:-$([ -f config/thresholds.csv ] && echo . || echo /tmp/sf-demo)}}"; cat "$_p/reports/analysis.md" 2>/dev/null || echo "ANALYSIS_REPORT: 없음 — analyze 단계를 먼저 실행한다"`

---

`decide` 스킬을 따라라.

제안은 `sf-actuate --plant <PLANT_DIR> propose` 로 **기록만** 한다. 승인(`approve`)·기각(`reject`)·정지(`stop`)는 사람이 한다. 실행하지 마라.
