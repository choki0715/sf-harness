# sf-harness

**스마트 팩토리 설비 센서 신호를 분석해 의사결정하는 에이전트 하네스.** 수업용.

파일 몇 개로 하네스의 해부학 전부를 보여준다 — 진입점 · 사실 · 절차 · 가드레일, 그리고 테스트.
판단하는 것은 **"이 설비를 세워야 하는가, 점검을 예약해야 하는가, 아니면 센서가 고장난 것인가"** 다.

---

## 하네스란 무엇인가

"프롬프트를 잘 쓰는 것"과 "에이전트를 운영하는 것"은 다른 일이다.

프롬프트는 **한 번의 대화**를 좋게 만든다.
하네스는 **매번 같은 품질이 나오게** 만든다. 같은 센서 데이터를 주면 어제도 오늘도,
어느 운영자가 물어도 같은 판단이 나와야 한다. 그러려면 네 가지가 필요하다 (아래 "하네스의 네 가지").

---

## 업무

제조 설비의 센서(진동·온도·전류·압력)가 값을 CSV 로 저장한다.
운영자는 그 값을 보고 세 가지 중 하나를 결정한다.

| 결정 | 되돌릴 수 있는가 | 누가 실행하는가 |
|---|---|---|
| 계속 가동 / 재확인 | — | — |
| 점검·정비 작업지시 발행, 속도 저감 | 예 (취소·복원 가능) | 사용자 승인 후 에이전트 |
| **설비 정지** | **아니오** (가공품 폐기, 재가동 수십 분) | **사람만** |

그리고 결정 전에 한 가지를 먼저 묻는다. **이 데이터를 믿을 수 있는가?**
센서가 고착됐거나 통신이 끊긴 것을 설비 고장으로 읽으면 멀쩡한 설비를 세운다.

---

## 하네스의 네 가지

| 필요한 것 | 이 예제의 파일 | 왜 |
|---|---|---|
| 진입점 | `commands/diagnose.md` | 사용자가 매번 "지난 한 시간 진동 평균 내고…"를 타이핑하지 않게 |
| 사실 | `bin/sf-signals` | LLM 이 CSV 를 읽고 평균을 내면 매번 다르게 낸다 |
| 절차 | `skills/diagnose/SKILL.md` | "CRIT 연속 3샘플이면 정지 권고"가 세션마다 흔들리지 않게 |
| 가드레일 | `hooks/guard.py` | 설비 정지·원본 로그 삭제·한계값 수정을 실행 전에 막게 |

그리고 하네스도 코드라서 `test/run-tests.sh` 로 테스트한다 (90개).

---

## 흐름

```
 센서 → signals/<설비>.csv 에 저장 (하네스 밖. PLC·게이트웨이의 일)
    │
 사용자: /sf-harness:diagnose /tmp/sf-demo
    │
    ▼
 ① commands/diagnose.md          ← 진입점
    │   frontmatter 의 !`...` 가 스크립트를 먼저 실행해 결과를 프롬프트에 붙인다.
    ▼
 ② bin/sf-signals                ← 사실 수집 (LLM 관여 없음)
    │   SF_SIGNALS_PROTO: 1
    │   CNC-02.vibration.STATUS: CRIT
    │   CNC-02.vibration.CRIT_STREAK: 12
    │   CNC-01.temperature.TREND_PER_HOUR: +4.05
    │   CNC-01.temperature.MIN_TO_WARN: 61
    │   PRESS-01.pressure.FLATLINE: 1
    │   CONV-01.STALE_MIN: 45
    │   SF_SIGNALS_OK
    ▼
 ③ skills/diagnose/SKILL.md      ← 절차·판단
    │   "STALE 이면 판단을 보류한다 — '정상'이라고도 하지 마라"
    │   "CRIT_STREAK ≥ 3 이면 정지 권고. 1~2 면 5분 뒤 재확인"
    │   "OPEN_WORK_ORDERS ≥ 1 이면 새로 발행하지 않는다"
    │   숫자는 다시 세지 않는다. 판단만 한다.
    ▼
 ④ 보고: 즉시 조치 / 예약 조치 / 재확인 / 데이터 문제 / 정상
    │
    ├─ 작업지시 발행 (사용자 승인 후)   bin/sf-actuate schedule-maintenance …   ← 되돌릴 수 있다
    │
    └─ 설비 정지                        bin/sf-actuate stop …
         ▼
 ⑤ hooks/guard.py               ← 가드레일 (실행 직전)
        sf-actuate stop            → 차단. 명령을 보고서에 적고 운영자가 친다
        rm / mv / > signals/       → 차단. 원본 로그는 증거다
        sed -i thresholds.csv      → 차단. 경보를 없애려고 기준을 올리지 않는다
```

---

## 판단 기준 (스킬이 하는 일)

| 사실 | 판단 |
|---|---|
| `STALE_MIN ≥ 10` | 판단 보류. 수집 계통 점검 요청. "정상" 아님 — 모르는 것 |
| `FLATLINE: 1` | 그 센서로 판단하지 않음. 센서·배선 점검 요청 |
| `CRIT_STREAK ≥ 3` | 즉시 정지 권고. 다른 센서도 WARN 이면 확신 상향 |
| `CRIT_STREAK 1~2` | 현장 확인 + 5분 뒤 재실행 |
| `OVER_CRIT ≥ 1`, `CRIT_STREAK 0` | 일시 스파이크. 재확인 항목 |
| `WARN_STREAK ≥ 3` 또는 `MIN_TO_WARN ≤ 240` | 점검 예약 |
| `DAYS_SINCE_MAINT ≥ 30` + 위 조건 | 예방 정비 우선 |
| `OPEN_WORK_ORDERS ≥ 1` | 중복 발행 금지. 기존 것을 언급 |

기준의 숫자(3샘플, 240분, 30일)는 **이 예제의 가정**이다. 실제 현장에서는 설비 담당자가 정한다.
그것이 스킬을 팀이 고쳐 쓰는 이유다.

---

## 네 가지 교훈

### 1. 검증 가능한 것은 LLM 에게 시키지 않는다

`sf-signals` 는 평균·표준편차·최소제곱 기울기·연속 초과 횟수를 센다. 판단이 없다.
`STATUS: CRIT` 조차 판단이 아니다 — "마지막 값 ≥ hi_crit" 라는 비교다.

> **경계선:** "진동 CRIT 연속 12샘플"은 스크립트. "그러니 지금 세워야 한다"는 LLM.
> "이 추세면 61분 뒤 WARN"도 스크립트다 — 직선 외삽은 산수지 예측이 아니다.

### 2. 출력은 `KEY: value` 로 준다

```
CNC-02.vibration.CRIT_STREAK: 12        ← LLM 이 그대로 읽는다
```
```
진동이 최근 10여 샘플 동안 위험 수준…    ← "10여"가 되는 순간 정보가 사라진다
```

### 3. 스킬은 프롬프트가 아니라 절차서다

`SKILL.md` 에 "당신은 숙련된 설비 엔지니어입니다"가 없다.
대신 **순서**(데이터 신뢰 → 정지 → 예약 → 원인 추정 → 보고)와 **판단 기준**과 **하지 말 것**이 있다.
특히 "데이터를 믿을 수 있는가"를 **첫 번째**에 둔 것이 이 스킬의 핵심이다.
순서를 바꾸면 LLM 은 CRIT 를 보자마자 정지를 권고하고 센서 고착을 놓친다.

### 4. 훅은 협상 대상이 아니다

진동이 CRIT 연속 12샘플이고 사용자가 "빨리 어떻게 좀 해봐"라고 재촉하면
LLM 은 `sf-actuate stop` 을 스스로 정당화할 수 있다. 훅은 정당화를 듣지 않는다.

이 훅이 막는 것은 셋뿐이다. 전부 되돌리기 어렵거나 안전과 직결된다.

| 막는 것 | 왜 |
|---|---|
| `sf-actuate stop` | 가공품 폐기, 재가동 수십 분. 사람이 실행한다 |
| `signals/` 삭제·이동·덮어쓰기 | 사고 조사의 증거 |
| `config/thresholds.csv` 수정 | 경보를 없애는 가장 쉬운 방법은 기준을 올리는 것이다 |

세 번째가 가장 미묘하다. **모델은 문제를 '해결'하려 한다.**
"WARN 이 계속 뜬다"는 문제의 가장 짧은 해결책은 WARN 기준을 올리는 것이고,
스킬에 "하지 마라"고 써도 언젠가 시도한다. 그래서 Bash 뿐 아니라 Write/Edit 도구까지 막는다.
**Bash 만 막으면 반쪽이다. 파일 편집 도구로 우회하는 길도 같이 막는다.**

작업지시 발행과 속도 저감은 막지 않는다. 취소하고 되돌리면 된다.
**훅을 남발하면 에이전트가 아무 일도 못 한다.**

그리고 훅은 **샌드박스가 아니다.** 정규식이지 셸 파서가 아니라서
`python3 -c "open('config/thresholds.csv','w')…"` 같은 길로 우회된다.
과속방지턱이지 보안 경계가 아니다. (학생이 직접 뚫어보게 해도 좋다.)

---

## 설치

### 플러그인으로 (권장)

VS Code 통합 터미널(`` Ctrl+` ``)에서 두 줄:

```bash
claude plugin marketplace add choki0715/sf-harness
claude plugin install sf-harness@sf-harness
```

`/plugin` 은 VS Code 확장의 채팅 패널에서는 열리지 않는다. 통합 터미널에서 위 셸 명령을 쓴다.
`claude` 명령이 없으면 [CLI 를 따로 설치](https://code.claude.com/docs/en/setup)한다.

### 이 세션에서만 (clone 해서)

```bash
git clone https://github.com/choki0715/sf-harness
claude --plugin-dir sf-harness/sf-harness
```

채팅창에서:

```
/sf-harness:demo                  ← /tmp/sf-demo 에 실습 플랜트 생성
/sf-harness:diagnose /tmp/sf-demo
```

### 훅은 실습 플랜트에서만 돈다

훅은 설치하면 **모든 프로젝트**에서 돈다. 이 훅은 `rm … signals` 를 막으므로
범위가 없으면 아무 저장소의 `rm signals.txt` 까지 막는다.

그래서 `guard.py` 는 **스스로 대상인지 확인하고 아니면 조용히 비켜선다.**

```
현재 디렉터리(또는 편집 대상 파일)의 상위에 .sf-harness 마커가 있다  → 가드레일 동작
환경변수 SF_HARNESS_GUARD=1                                         → 가드레일 동작
둘 다 아니다                                                         → 아무것도 하지 않는다
```

`sf-demo-data` 가 실습 플랜트에 마커를 만들고, `.claude/settings.json` 에도 훅을 등록한다 (두 겹).
git 저장소가 아니어도 된다 — 플랜트 데이터 디렉터리는 보통 git 이 아니다.

---

## 직접 해보기

```bash
# 1. 실습 플랜트를 만든다 — 학생 전원이 똑같은 상태에서 시작한다
sf-harness/bin/sf-demo-data /tmp/sf-demo

# 2. LLM 없이 스크립트만 먼저 돌려본다
sf-harness/bin/sf-signals /tmp/sf-demo
sf-harness/bin/sf-actuate --plant /tmp/sf-demo list

# 3. 이제 Claude Code 에서
cd /tmp/sf-demo
/sf-harness:diagnose
```

2번을 먼저 시키는 게 중요하다. **하네스의 절반은 LLM 없이 도는 코드**라는 걸
눈으로 보고 나면, 3번에서 LLM 이 무엇을 더한 것인지가 분명해진다.

실습 플랜트에는 설비마다 다른 함정이 하나씩 심겨 있다.

| 설비 | 심은 것 | 기대하는 판단 |
|---|---|---|
| CNC-02 | 진동 CRIT 연속 12 + 온도 WARN | 즉시 정지 권고, 명령은 사람이 |
| CNC-01 | 온도 상승 추세(61분 뒤 WARN), 전류 스파이크 1회, 정비 45일 | 점검 예약 / 스파이크는 재확인 |
| PRESS-01 | 압력 FLATLINE, cycle_time MISSING, 작업지시 이미 있음 | 센서 문제로 분리, 중복 발행 금지 |
| CONV-01 | 45분째 데이터 없음 | 판단 보류. "정상" 아님 |

CONV-01 이 이 실습의 핵심이다. 창 안의 옛 값은 전부 OK 라서
**"데이터 신뢰"를 먼저 보지 않으면 LLM 은 이 설비를 정상으로 분류한다.**

시연해 볼 것 (전부 차단되어야 한다):

```
sf-actuate stop CNC-02 --reason "진동 CRIT"
rm signals/CNC-02.csv
sed -i 's/7.1/9.0/' config/thresholds.csv
```

### 테스트

```bash
./test/run-tests.sh     # 90개
```

### 학생 과제로 좋은 것

1. `sf-signals` 에 **새 사실 하나**를 추가한다 (예: 창 전반부 대비 후반부 평균의 변화율)
   → 스킬에 그 판단 규칙도 같이 추가해야 값이 생긴다는 걸 체감한다
2. `guard.py` 를 **우회해 본다** (`python3 -c` 로 thresholds.csv 열기)
   → 훅이 보안 경계가 아니라는 걸 손으로 확인한다. 막고 싶으면 어디를 막아야 하는지 생각한다
3. 스킬의 "정지 기준 CRIT 연속 3" 을 **자기 설비 기준으로** 바꾼다
   → 하네스는 현장의 판단 기준을 코드로 굳히는 도구라는 걸 안다
4. `sf-demo-data` 에 다섯 번째 설비를 추가하되, **센서 둘이 반대 방향으로** 이상하게 만든다
   → 스킬의 "같은 방향이면 설비, 한 센서만 튀면 센서" 규칙이 어디서 깨지는지 본다

---

## Session 04 와의 관계

이 하네스는 [LLM_master_part5](https://github.com/choki0715/LLM_master_part5) 의 `04_tool_calling_function.ipynb` 에 있는 `run_agent` 루프를 Claude Code 위에 얹은 것이다.

| Session 04 | 이 하네스 |
|---|---|
| 도구 함수 (`get_weather` …) | `bin/sf-signals`, `bin/sf-actuate` |
| 도구 description | `commands/diagnose.md` 의 frontmatter |
| system prompt | `skills/diagnose/SKILL.md` — 단, 역할 부여가 아니라 절차 |
| `max_iterations` | `hooks/guard.py` — 루프 **밖**에서 거는 안전장치 |
| 에이전트 루프 | Claude Code 자체 |

루프는 직접 짜지 않는다. 짜야 하는 것은 **도구·절차·가드레일**이고, 그게 하네스다.

---

## 구조

```
sf-harness/                        ← 이 저장소
├── README.md                      ← 지금 읽는 문서
├── LICENSE
├── test/
│   └── run-tests.sh               ← 90개. 하네스도 코드다
├── .claude-plugin/
│   └── marketplace.json           ← 이 디렉터리가 마켓플레이스
└── sf-harness/                    ← 플러그인 본체
    ├── .claude-plugin/plugin.json
    ├── commands/
    │   ├── diagnose.md            ① 진입점
    │   └── demo.md                실습 플랜트 만들기
    ├── bin/
    │   ├── sf-signals             ② 사실 수집 (표준 라이브러리만)
    │   ├── sf-actuate             조치 기록·실행 (작업지시·속도·정지)
    │   └── sf-demo-data           실습 플랜트 생성
    ├── skills/diagnose/SKILL.md   ③ 절차·판단
    └── hooks/
        ├── hooks.json             ④ 훅 등록 (Bash + Write/Edit)
        └── guard.py                  가드레일
```

플랜트 데이터 디렉터리 (`sf-demo-data` 가 만든다):

```
/tmp/sf-demo/
├── .sf-harness                    훅 범위 마커
├── .claude/settings.json          프로젝트 단위 훅 등록
├── config/thresholds.csv          equipment,sensor,unit,lo_crit,lo_warn,hi_warn,hi_crit
├── signals/<설비>.csv             timestamp,sensor,value
├── maintenance_log.csv            equipment,date,type,note
├── work_orders.csv                sf-actuate 가 읽고 쓴다
└── actions.log                    sf-actuate 가 추가만 한다
```

---

## 여기서 다루지 않은 것

의도적으로 뺐다.

- **실시간 스트리밍** — 이 하네스는 "저장된" 신호를 본다. 실시간 경보는 PLC·SCADA 의 일이고,
  하네스는 그 위에서 "그래서 무엇을 할 것인가"를 판단한다
- **이상 탐지 모델** — z-score·추세만 쓴다. Isolation Forest 나 오토인코더는 `sf-signals` 의
  새 KEY 로 들어오면 되고, 스킬은 바뀌지 않는다. 그게 사실과 판단을 나눈 이유다
- **실제 설비 연동** — `sf-actuate` 는 파일에 기록한다. 실제로는 MES·CMMS API 호출이 들어간다.
  그때도 `stop` 을 훅으로 막는 구조는 같다
- **서브에이전트** — 설비 50대면 설비 하나당 에이전트 하나를 격리해 돌리는 게 맞다.
  4대에는 과하다

**규모가 커지고 나서 도입한다.** 처음부터 넣으면 배보다 배꼽이 커진다.
