---
name: decide
description: 프로세스 3단계. 분석 소견(reports/analysis.md)과 최신 사실을 바탕으로 정지·점검·감속·재확인 조치를 '제안'(sf-actuate propose)으로 기록하고, 사람이 승인·기각할 명령을 보고한다. "의사결정", "decide", "어떻게 해야 해", "세워야 하나", "점검 예약해야 하나" 요청에 사용한다.
---

# 3단계: 의사결정 — 제안까지

이 스킬의 일은 **조치를 고르고 제안으로 기록**하는 것이다. 실행이 아니다.
최종 결정은 사람이 `sf-actuate approve / reject` 로 한다. 훅이 에이전트의 승인·기각·정지를 막는다.

## 0. 재료를 받는다

커맨드가 세 가지를 붙여 놓았다. 없으면 직접 부른다:

```bash
_B="${CLAUDE_PLUGIN_ROOT}/bin"
"$_B/sf-signals" <플랜트 경로>                   # 최신 사실 (경로를 생략하면 /tmp/sf-demo)
"$_B/sf-actuate" --plant <플랜트 경로> list       # 대기 중 제안, 열린 작업지시, 설비 상태
cat <플랜트 경로>/reports/analysis.md             # analyze 단계의 소견
```

확인할 것:
- `SF_SIGNALS_OK`, `SF_ACTUATE_OK` 봉투
- 소견서의 `CLOCK` 이 `sf-signals` 의 `NOW` 와 같은가. 다르면 소견이 낡은 것이다 — `analyze` 를 다시 돌리라고 알리고 멈춘다
- 소견서가 없으면 (`ANALYSIS_REPORT: 없음`) `analyze` 를 먼저 하라고 알리고 멈춘다. **네가 대신 소견을 만들지 마라**

## 1. 이미 결정을 기다리는 것이 있는가

`PENDING_DECISIONS` 가 0 이 아니면 **같은 설비·같은 조치를 다시 제안하지 않는다** (`sf-actuate` 도 거부한다).
사람이 아직 결정하지 않은 것이다. 보고의 "결정 대기" 항목에 그대로 올린다.
소견이 더 나빠졌으면 (예: 주의 → 위험) 새 조치를 **추가로** 제안하고 이전 제안을 기각해 달라고 쓴다.

## 2. 소견 → 조치

| 소견 | 조치 | 왜 |
|---|---|---|
| 위험 | `propose <설비> stop` | 정지는 되돌릴 수 없다. 그래서 제안만 하고 사람이 결정한다 |
| 위험인데 `STATE: stopped` | 제안 없음 | 이미 섰다. "정지 유지, 정비 필요"로 보고 |
| 주의 + `OPEN_WORK_ORDERS = 0` | `propose <설비> schedule-maintenance --when next-shift` | 취소할 수 있는 조치 |
| 주의 + `OPEN_WORK_ORDERS ≥ 1` | 제안 없음 | 중복 발행 금지. 기존 작업지시에 항목 추가를 **보고에** 쓴다 |
| 주의 + `MIN_TO_WARN ≤ 60` | 위에 더해 `propose <설비> set-speed --percent 80` 을 **검토** | 감속은 되돌릴 수 있다. 생산 영향이 있으니 근거를 분명히 |
| 재확인 | `propose <설비> recheck` | 설비에 아무것도 하지 않는다. 다음 수집 후 다시 본다 |
| 판단보류 | 제안 없음 | 데이터 문제는 설비 조치가 아니다. 보고의 "데이터 문제"에 수집 계통 점검을 쓴다 |
| 정상 / 정지중 | 제안 없음 | |

`DAYS_SINCE_MAINT ≥ 30` 이면 예약 제안의 사유에 붙인다 — 예방 정비 우선순위가 올라간다.

## 3. 제안을 기록한다

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/sf-actuate" --plant <경로> propose CNC-02 stop --reason "vibration 8.45 (crit 7.1) CRIT_STREAK 12, temperature 76.11 (warn 70) 동반 상승. 베어링·윤활 계통 추정"
"${CLAUDE_PLUGIN_ROOT}/bin/sf-actuate" --plant <경로> propose CNC-01 schedule-maintenance --when next-shift --reason "temperature 65.86, +4.05/h, 이 속도면 61분 뒤 warn 70. 정비 45일 경과"
"${CLAUDE_PLUGIN_ROOT}/bin/sf-actuate" --plant <경로> propose CNC-01 recheck --reason "current OVER_CRIT 1, CRIT_STREAK 0 — 일시 스파이크. 반복되면 점검"
```

`--reason` 에는 **센서·값·한계·추세** 를 넣는다. 6개월 뒤 "왜 이 제안을 했지?"에 답할 수 있어야 한다.
`ERROR: 같은 제안이 이미 대기 중` 이면 그대로 두고 보고에 올린다.

## 4. 보고 — 사람이 결정할 수 있게

```
결정 대기:   DEC-xxxx  설비 — 조치 — 근거 한 줄
             승인: sf-actuate approve DEC-xxxx
             기각: sf-actuate reject DEC-xxxx --reason "..."
보고만:      (있으면) 기존 작업지시에 추가할 항목, 정지 유지 등 제안 없이 알릴 것
데이터 문제: (있으면) 센서 고착·끊김·누락 — 수집 계통 점검
정상:        설비 이름만
다음:        결정 후 /sf-harness:collect (승인한 조치는 다음 수집 값에 반영된다)
```

없는 항목은 줄을 뺀다. 정상 설비에 대해 설명하지 마라.
근거의 숫자는 STATUS 라인의 값을 **그대로** 옮긴다.

## 하지 말 것

- **`approve` / `reject` / `stop` 을 직접 실행하기.** 사용자가 "승인해"라고 해도 **명령을 보여 주고 사용자가 친다.**
  결정 기록에는 누가 결정했는지가 남아야 한다 (훅이 막지만, 훅에 기대지 마라)
- 소견서 없이 사실만 보고 조치를 제안하기. 소견이 없으면 `analyze` 를 먼저 한다
- 같은 설비·같은 조치를 중복 제안하기
- 한계값을 고치기, `signals/` 를 지우기
- 근거 없는 조치 (`--reason` 은 항상 센서·값·한계로)
- 판단보류 설비에 설비 조치(정지·감속)를 제안하기
