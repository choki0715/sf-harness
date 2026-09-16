---
description: 수집 → 분석 → 의사결정 을 순서대로 한 번에 돌린다 (최종 결정은 사람이)
argument-hint: [플랜트 경로] [--minutes N] (생략하면 현재 디렉터리, 5분)
allowed-tools: Bash, Read, Write, Grep, Glob
---

1단계 수집 결과:
!`for _c in "$CLAUDE_PLUGIN_ROOT/bin/sf-collect" "$(readlink -f "$HOME/.claude/skills/sf-harness" 2>/dev/null)/bin/sf-collect" "$(command -v sf-collect 2>/dev/null)"; do [ -x "$_c" ] && { "$_c" $ARGUMENTS 2>&1; exit 0; }; done; echo "ERROR: sf-collect 를 찾지 못했다 — 설치를 확인해라"`

---

세 스킬을 **이 순서로** 따라라. 각 단계의 봉투(`..._OK` 줄)를 확인하고 다음으로 넘어간다.

1. `collect` 스킬 — 위 수집 결과를 판단한다. `ERROR:` 면 여기서 멈춘다.
2. `analyze` 스킬 — `sf-signals <플랜트 경로>` 를 실행해 사실을 받고 소견을 `reports/analysis.md` 에 쓴다.
3. `decide` 스킬 — `sf-actuate --plant <플랜트 경로> list` 로 대기 중 제안을 확인한 뒤 조치를 제안한다.

마지막 보고는 `decide` 스킬의 형식으로 **한 번만** 한다. 단계마다 따로 보고하지 마라.
승인·기각·정지는 실행하지 마라. 운영자가 칠 명령을 적어 주는 것까지가 네 일이다.
