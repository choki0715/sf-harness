---
description: 1단계 수집 — 가상 센서에서 새 값을 받아 signals/ 에 추가한다
argument-hint: [플랜트 경로] [--minutes N] (생략하면 /tmp/sf-demo, 5분)
allowed-tools: Bash, Read, Grep, Glob
---

수집 결과:
!`_b="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v sf-signals 2>/dev/null || echo /nonexistent/bin/x)")")}/bin"; [ -x "$_b/sf-collect" ] && "$_b/sf-collect" $ARGUMENTS 2>&1 || echo "ERROR: sf-collect 를 찾지 못했다 — 플러그인 설치를 확인해라 (/reload-plugins)"`

---

`collect` 스킬을 따라라.

위 STATUS 라인이 **사실이다.** 샘플 수를 다시 세지 마라. 조용한 설비의 값을 지어내거나 signals/ 에 직접 쓰지 마라.
플랜트 경로는 위 출력의 `PLANT_DIR` 이다. 이후 스크립트를 부를 때 그 경로를 쓴다.
