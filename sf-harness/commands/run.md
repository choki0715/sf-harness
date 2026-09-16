---
description: 수집 → 분석 → 의사결정 을 순서대로 한 번에 돌린다 (최종 결정은 사람이)
argument-hint: [플랜트 경로] [--minutes N] (생략하면 /tmp/sf-demo, 5분)
allowed-tools: Bash, Read, Write, Grep, Glob
---

플러그인 스크립트 위치: `${CLAUDE_PLUGIN_ROOT}/bin` — 아래 단계에서 이 경로로 부른다.

1단계 수집 결과:
!`_b="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v sf-signals 2>/dev/null || echo /nonexistent/bin/x)")")}/bin"; [ -x "$_b/sf-collect" ] && "$_b/sf-collect" $ARGUMENTS 2>&1 || echo "ERROR: sf-collect 를 찾지 못했다 — 플러그인 설치를 확인해라 (/reload-plugins)"`

---

세 스킬을 **이 순서로** 따라라. 각 단계의 봉투(`..._OK` 줄)를 확인하고 다음으로 넘어간다.
플랜트 경로는 위 출력의 `PLANT_DIR` 이다.

1. `collect` 스킬 — 위 수집 결과를 판단한다. `ERROR:` 면 여기서 멈춘다.
2. `analyze` 스킬 — `${CLAUDE_PLUGIN_ROOT}/bin/sf-signals <PLANT_DIR>` 를 실행해 사실을 받고 소견을 `<PLANT_DIR>/reports/analysis.md` 에 쓴다.
3. `decide` 스킬 — `${CLAUDE_PLUGIN_ROOT}/bin/sf-actuate --plant <PLANT_DIR> list` 로 대기 중 제안을 확인한 뒤 조치를 제안한다.

마지막 보고는 `decide` 스킬의 형식으로 **한 번만** 한다. 단계마다 따로 보고하지 마라.
승인·기각·정지는 실행하지 마라. 운영자가 칠 명령을 적어 주는 것까지가 네 일이다.
