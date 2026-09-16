---
description: 1단계 수집 — 가상 센서에서 새 값을 받아 signals/ 에 추가한다
argument-hint: [플랜트 경로] [--minutes N] (생략하면 현재 디렉터리, 5분)
allowed-tools: Bash, Read, Grep, Glob
---

수집 결과:
!`for _c in "$CLAUDE_PLUGIN_ROOT/bin/sf-collect" "$(readlink -f "$HOME/.claude/skills/sf-harness" 2>/dev/null)/bin/sf-collect" "$(command -v sf-collect 2>/dev/null)"; do [ -x "$_c" ] && { "$_c" $ARGUMENTS 2>&1; exit 0; }; done; echo "ERROR: sf-collect 를 찾지 못했다 — 설치를 확인해라"`

---

`collect` 스킬을 따라라.

위 STATUS 라인이 **사실이다.** 샘플 수를 다시 세지 마라. 조용한 설비의 값을 지어내거나 signals/ 에 직접 쓰지 마라.
