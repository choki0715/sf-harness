---
description: 실습용 가상 플랜트를 만든다 (수업 준비)
argument-hint: [경로] [--fresh] (생략하면 /tmp/sf-demo. --fresh 는 지우고 다시 만든다)
allowed-tools: Bash
---

!`_b="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v sf-signals 2>/dev/null || echo /nonexistent/bin/x)")")}/bin"; [ -x "$_b/sf-demo-data" ] && "$_b/sf-demo-data" $ARGUMENTS 2>&1 || echo "ERROR: sf-demo-data 를 찾지 못했다 — 플러그인 설치를 확인해라 (/reload-plugins)"`

---

위 출력을 사용자에게 그대로 전하고, 다음에 무엇을 하면 되는지 한 줄로 알려줘라 (`/sf-harness:run`).

`ERROR:` 로 시작하면 설치가 깨진 것이다. 데이터를 직접 만들려고 하지 마라.
"이미 있다" 면 그대로 써도 되고, 처음부터 다시 하려면 `/sf-harness:demo --fresh` 라고 안내한다. 네가 rm 을 실행하지 마라.
