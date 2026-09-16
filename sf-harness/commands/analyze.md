---
description: 2단계 분석 — 저장된 센서 신호에서 사실을 뽑고 설비별 소견을 낸다
argument-hint: [플랜트 경로] [--window 분] (생략하면 /tmp/sf-demo, 60분)
allowed-tools: Bash, Read, Write, Grep, Glob
---

센서 신호 사실:
!`_b="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v sf-signals 2>/dev/null || echo /nonexistent/bin/x)")")}/bin"; [ -x "$_b/sf-signals" ] && "$_b/sf-signals" $ARGUMENTS 2>&1 || echo "ERROR: sf-signals 를 찾지 못했다 — 플러그인 설치를 확인해라 (/reload-plugins)"`

---

`analyze` 스킬을 따라라.

위 STATUS 라인이 **사실이다.** 평균·추세·연속 횟수를 다시 계산하지 마라. signals/ 의 CSV 를 다시 읽지 마라.
이 단계의 산출물은 **소견**이다. 조치를 제안하거나 실행하지 마라 — 그것은 `decide` 단계의 일이다.
소견서는 위 출력의 `PLANT_DIR` 아래 `reports/analysis.md` 에 쓴다.
