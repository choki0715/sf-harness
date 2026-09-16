# sf-harness

**스마트 팩토리 설비 센서 신호를 수집하고, 분석하고, 조치를 제안하되 최종 결정은 사람이 하는 에이전트 하네스.** 수업용.

프로세스는 다섯 단계다. 앞의 셋은 스킬이고, 넷째는 훅이고, 다섯째는 사람이다.

```
 ① 수집 (collect)  →  ② 분석 (analyze)  →  ③ 의사결정 (decide)  →  ④ 훅 (guard)  →  ⑤ 사람 (approve / reject)
    가상 센서 값을         사실 위에서             조치를 '제안'으로        정지·승인·기각을        터미널에서 결정.
    signals/ 에 추가       소견만 낸다             기록한다 (pending)       에이전트가 못 하게       승인한 조치는
                                                                                                  다음 수집 값에 반영
```

---

## 하네스란 무엇인가

"프롬프트를 잘 쓰는 것"과 "에이전트를 운영하는 것"은 다른 일이다.

프롬프트는 **한 번의 대화**를 좋게 만든다.
하네스는 **매번 같은 품질이 나오게** 만든다. 같은 센서 데이터를 주면 어제도 오늘도,
어느 운영자가 물어도 같은 판단이 나와야 한다. 그러려면 네 가지가 필요하다.

| 필요한 것 | 이 예제의 파일 | 왜 |
|---|---|---|
| 진입점 | `commands/run.md` (+ 단계별 `collect` `analyze` `decide`) | 사용자가 매번 "지난 한 시간 진동 평균 내고…"를 타이핑하지 않게 |
| 사실 | `bin/sf-collect` `bin/sf-signals` `bin/sf-actuate` | LLM 이 CSV 를 읽고 평균을 내면 매번 다르게 낸다 |
| 절차 | `skills/collect` `skills/analyze` `skills/decide` | "CRIT 연속 3샘플이면 정지 제안"이 세션마다 흔들리지 않게 |
| 가드레일 | `hooks/guard.py` | 정지·승인·기각·원본 로그 삭제·한계값 수정을 실행 전에 막게 |

그리고 하네스도 코드라서 `test/run-tests.sh` 로 테스트한다 (146개).

---

## 업무

제조 설비의 센서(진동·온도·전류·압력)가 값을 CSV 로 저장한다.
운영자는 그 값을 보고 결정한다. 결정에는 되돌릴 수 있는 것과 없는 것이 있다.

| 조치 | 되돌릴 수 있는가 | 누가 |
|---|---|---|
| 재확인 (다음 수집 후 다시 본다) | — | 에이전트가 제안, 사람이 승인 |
| 점검·정비 작업지시 발행, 속도 저감 | 예 (취소·복원 가능) | 에이전트가 제안, 사람이 승인 |
| **설비 정지** | **아니오** (가공품 폐기, 재가동 수십 분) | 에이전트가 제안, **사람이 승인·실행** |

그리고 결정 전에 한 가지를 먼저 묻는다. **이 데이터를 믿을 수 있는가?**
센서가 고착됐거나 통신이 끊긴 것을 설비 고장으로 읽으면 멀쩡한 설비를 세운다.

---

## 다섯 단계

### ① 수집 — `collect` 스킬 + `bin/sf-collect`

실제 공장에서는 PLC·게이트웨이가 센서 값을 쌓는다. 실습에서는 **가상 플랜트**(`bin/sf_virtual_plant.py`)가
그 자리를 대신한다. 가상 시계를 N분 앞으로 돌리며 설비 4대의 값을 `signals/<설비>.csv` 에 추가한다.

```
SF_COLLECT_PROTO: 1
CLOCK_BEFORE: 2026-09-16T14:00:00
CLOCK_AFTER: 2026-09-16T14:05:00
CNC-01.NEW_SAMPLES: 15
CONV-01.NEW_SAMPLES: 0
CONV-01.SENSORS_SILENT: current vibration
SILENT_EQUIPMENT: CONV-01
SF_COLLECT_OK
```

값은 (설비, 분) 으로 시드를 고정한 난수라 **누가 언제 몇 분씩 수집해도 같다.** 5분 두 번은 10분 한 번과 같다.
스킬의 판단은 하나뿐이다 — 수집이 온전했는가. 조용한 설비의 값을 **채워 넣지 않는다.**

### ② 분석 — `analyze` 스킬 + `bin/sf-signals`

`sf-signals` 가 창(기본 60분) 안의 사실을 뽑는다. 평균·표준편차·최소제곱 추세·연속 초과 횟수·
`MIN_TO_WARN`(직선 외삽)·FLATLINE(센서 고착)·STALE(수집 끊김)·정비 경과일·설비 상태.

```
CNC-02.vibration.STATUS: CRIT
CNC-02.vibration.CRIT_STREAK: 12
CNC-02.temperature.TREND_PER_HOUR: +17.79
CNC-01.temperature.MIN_TO_WARN: 61
PRESS-01.pressure.FLATLINE: 1
CONV-01.STALE_MIN: 45
CNC-02.STATE: running speed=100
```

스킬은 **데이터 신뢰를 먼저** 보고, 설비마다 소견 하나를 고른다 — 위험 / 주의 / 재확인 / 정상 / 판단보류 / 정지중.
산출물은 `reports/analysis.md` 소견서다. **조치는 제안하지 않는다.** 그건 다음 단계의 일이다.

### ③ 의사결정 — `decide` 스킬 + `bin/sf-actuate propose`

소견서와 최신 사실, 대기 중 제안·열린 작업지시를 받아 조치를 고른다.

| 소견 | 조치 |
|---|---|
| 위험 | `propose <설비> stop` |
| 주의 (열린 작업지시 없음) | `propose <설비> schedule-maintenance --when next-shift` |
| 주의 (열린 작업지시 있음) | 제안 없음 — 기존 작업지시에 항목 추가를 보고 |
| 재확인 | `propose <설비> recheck` |
| 판단보류 | 제안 없음 — 데이터 문제는 설비 조치가 아니다 |

`propose` 는 `decisions.csv` 에 **pending 으로 기록**할 뿐이다. 설비에는 아무 일도 일어나지 않는다.
같은 설비·같은 조치는 사람이 결정할 때까지 다시 낼 수 없다 (스크립트가 거부한다).

보고는 사람이 바로 결정할 수 있는 형식이다:

```
결정 대기:   DEC-0001  CNC-02 — stop — vibration 8.45 (crit 7.1) CRIT_STREAK 12, temperature 76.11 (warn 70)
             승인: sf-actuate approve DEC-0001
             기각: sf-actuate reject DEC-0001 --reason "..."
```

### ④ 훅 — `hooks/guard.py`

에이전트가 넘어서는 안 되는 선을 코드로 긋는다. 실행 직전에 검사하고, 이유를 붙여 막는다.

| 막는 것 | 왜 |
|---|---|
| `sf-actuate approve` / `reject` | 결정은 사람이 한다. 결정 기록에 누가 결정했는지가 남아야 한다 |
| `sf-actuate stop` | 가공품 폐기, 재가동 수십 분. 되돌릴 수 없다 |
| `signals/` 삭제·이동·덮어쓰기 | 사고 조사의 증거 |
| `config/thresholds.csv` 수정 | 경보를 없애는 가장 쉬운 방법은 기준을 올리는 것이다 |

Bash 뿐 아니라 Write/Edit 도구까지 본다. **Bash 만 막으면 반쪽이다.**
제안·작업지시 발행·속도 저감·소견서 쓰기는 막지 않는다. 되돌릴 수 있다.

### ⑤ 사람 — 터미널에서

```bash
sf-actuate approve DEC-0001                          # 실행된다. 정지면 state.json 이 stopped 로
sf-actuate reject  DEC-0002 --reason "생산 일정상 불가"
sf-actuate list                                      # 대기 중 제안, 열린 작업지시, 설비 상태
```

같은 명령을 에이전트가 치면 훅에 막히고, 사람이 치면 실행된다. **훅은 에이전트에만 걸린다.**
승인한 조치는 `state.json` 에 반영되어 **다음 수집 값에 나타난다** — 정지한 설비는 진동·전류가 0 에 가까워지고,
감속한 설비는 그 비율만큼 준다. 그래서 ①로 돌아가면 루프가 닫힌다.

---

## 네 가지 교훈

### 1. 검증 가능한 것은 LLM 에게 시키지 않는다

`sf-signals` 는 평균·표준편차·최소제곱 기울기·연속 초과 횟수를 센다. 판단이 없다.
`STATUS: CRIT` 조차 판단이 아니다 — "마지막 값 ≥ hi_crit" 라는 비교다.
`sf-collect` 도 마찬가지다. 값을 받고 세기만 한다.

> **경계선:** "진동 CRIT 연속 12샘플"은 스크립트. "그러니 정지를 제안한다"는 LLM.
> "이 추세면 61분 뒤 WARN"도 스크립트다 — 직선 외삽은 산수지 예측이 아니다.

### 2. 출력은 `KEY: value` 로 준다

```
CNC-02.vibration.CRIT_STREAK: 12        ← LLM 이 그대로 읽는다
```
```
진동이 최근 10여 샘플 동안 위험 수준…    ← "10여"가 되는 순간 정보가 사라진다
```

단계 사이도 마찬가지다. `analyze` 가 `decide` 에 넘기는 소견서는 자유 산문이 아니라 **고정된 표**다.
다음 단계가 읽는 문서는 사람이 아니라 프로그램이 읽는 것처럼 쓴다.

### 3. 스킬은 프롬프트가 아니라 절차서다

세 스킬 어디에도 "당신은 숙련된 설비 엔지니어입니다"가 없다.
대신 **순서**와 **판단 기준**과 **하지 말 것**이 있다.

스킬을 셋으로 나눈 이유도 절차다. 하나로 두면 LLM 은 CRIT 를 보자마자 정지를 말한다.
**수집 → 분석 → 결정**으로 나누고, 분석에서 "조치를 말하지 마라", 결정에서 "소견서 없이 결정하지 마라"를
박아 두면, 데이터 신뢰 판단을 건너뛸 수 없다.

### 4. 훅은 협상 대상이 아니다

진동이 CRIT 연속 12샘플이고 사용자가 "빨리 승인해서 세워"라고 재촉하면
LLM 은 `sf-actuate approve` 를 스스로 정당화할 수 있다. 훅은 정당화를 듣지 않는다.

**제안과 결정을 나누는 선이 훅이다.** 스킬에 "승인은 사람이 한다"고 써도 재촉 앞에서는 흔들린다.
`guard.py` 는 흔들리지 않는다. 그리고 결정 대장(`decisions.csv`)에는 누가 언제 결정했는지가 남는다 —
에이전트가 승인을 대신하면 그 기록이 거짓이 된다.

이 훅이 막는 것은 넷뿐이다. 되돌릴 수 있는 일(제안, 작업지시, 감속)은 막지 않는다.
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
# 1. 가상 플랜트를 만든다 — 학생 전원이 똑같은 상태에서 시작한다
sf-harness/bin/sf-demo-data /tmp/sf-demo

# 2. LLM 없이 스크립트만 먼저 돌려본다
sf-harness/bin/sf-signals /tmp/sf-demo                 # 지금 상태의 사실
sf-harness/bin/sf-collect /tmp/sf-demo --minutes 5     # 시계 5분 전진
sf-harness/bin/sf-signals /tmp/sf-demo                 # CRIT 연속이 12 → 17 로
sf-harness/bin/sf-actuate --plant /tmp/sf-demo list

# 3. 이제 Claude Code 에서
cd /tmp/sf-demo
/sf-harness:run              # 수집 → 분석 → 결정 을 한 번에
                             # (또는 /sf-harness:collect → :analyze → :decide 를 하나씩)

# 4. 사람이 결정한다 (터미널에서)
sf-harness/bin/sf-actuate --plant /tmp/sf-demo approve DEC-0001
sf-harness/bin/sf-actuate --plant /tmp/sf-demo reject  DEC-0002 --reason "..."

# 5. 다시 돌린다 — 정지한 설비의 진동이 0 에 가까워진 것을 본다
/sf-harness:run
```

2번을 먼저 시키는 게 중요하다. **하네스의 절반은 LLM 없이 도는 코드**라는 걸
눈으로 보고 나면, 3번에서 LLM 이 무엇을 더한 것인지가 분명해진다.

가상 플랜트에는 설비마다 다른 함정이 하나씩 심겨 있다.

| 설비 | 심은 것 | 기대하는 흐름 |
|---|---|---|
| CNC-02 | 진동 CRIT 연속 12 + 온도 WARN, 둘 다 계속 상승 | 위험 → `stop` 제안 → 사람이 승인 → 다음 수집부터 진동 ≈ 0 |
| CNC-01 | 온도 +4°C/h (약 1시간 뒤 WARN), 전류 스파이크 1회, 정비 45일 | 주의 → 점검 예약 제안 / 재확인 제안 |
| PRESS-01 | 압력 FLATLINE, cycle_time MISSING, 작업지시 이미 있음 | 센서 문제로 분리, 중복 발행 금지 |
| CONV-01 | 45분째 데이터 없음. 30분 뒤 수집부터 돌아온다 | 판단보류 → 돌아오면 정상 |

CONV-01 이 이 실습의 핵심이다. 창 안의 옛 값은 전부 OK 라서
**"데이터 신뢰"를 먼저 보지 않으면 LLM 은 이 설비를 정상으로 분류한다.**

시연해 볼 것 (에이전트에게 시키면 전부 차단되어야 한다):

```
sf-actuate approve DEC-0001
sf-actuate stop CNC-02 --reason "진동 CRIT"
rm signals/CNC-02.csv
sed -i 's/7.1/9.0/' config/thresholds.csv
```

### 테스트

```bash
./test/run-tests.sh     # 146개
```

### 학생 과제로 좋은 것

1. `sf-signals` 에 **새 사실 하나**를 추가한다 (예: 창 전반부 대비 후반부 평균의 변화율)
   → `analyze` 스킬에 그 판단 규칙도 같이 추가해야 값이 생긴다는 걸 체감한다
2. `guard.py` 를 **우회해 본다** (`python3 -c` 로 thresholds.csv 열기, `approve` 를 변수에 숨기기)
   → 훅이 보안 경계가 아니라는 걸 손으로 확인한다. 막고 싶으면 어디를 막아야 하는지 생각한다
3. `decide` 스킬의 "정지 기준 CRIT 연속 3" 을 **자기 설비 기준으로** 바꾼다
   → 하네스는 현장의 판단 기준을 코드로 굳히는 도구라는 걸 안다
4. `sf_virtual_plant.py` 에 다섯 번째 설비를 추가하되, **센서 둘이 반대 방향으로** 이상하게 만든다
   → `analyze` 의 "같은 방향이면 설비, 한 센서만 튀면 센서" 규칙이 어디서 깨지는지 본다
5. 사용자가 "그냥 승인해"라고 재촉하는 대화를 만들어 본다
   → 스킬이 버티는지, 훅이 막는지, 둘 중 어느 쪽이 실제로 선을 지켰는지 본다

---

## Session 04 와의 관계

이 하네스는 [LLM_master_part5](https://github.com/choki0715/LLM_master_part5) 의 `04_tool_calling_function.ipynb` 에 있는
`run_agent` 루프를 Claude Code 위에 얹은 것이다.

| Session 04 | 이 하네스 |
|---|---|
| 도구 함수 (`get_weather` …) | `bin/sf-collect`, `bin/sf-signals`, `bin/sf-actuate` |
| 도구 description | `commands/*.md` 의 frontmatter |
| system prompt | `skills/*/SKILL.md` — 단, 역할 부여가 아니라 절차 |
| `max_iterations` | `hooks/guard.py` — 루프 **밖**에서 거는 안전장치 |
| 에이전트 루프 | Claude Code 자체 |
| (없음) | 사람의 승인 — 루프가 닿을 수 없는 자리 |

루프는 직접 짜지 않는다. 짜야 하는 것은 **도구·절차·가드레일**, 그리고 **사람이 서는 자리**다. 그게 하네스다.

---

## 구조

```
sf-harness/                        ← 이 저장소
├── README.md                      ← 지금 읽는 문서
├── LICENSE
├── test/
│   └── run-tests.sh               ← 146개. 하네스도 코드다
├── .claude-plugin/
│   └── marketplace.json           ← 이 디렉터리가 마켓플레이스
└── sf-harness/                    ← 플러그인 본체
    ├── .claude-plugin/plugin.json
    ├── commands/
    │   ├── run.md                 ① 진입점: 수집 → 분석 → 결정 한 번에
    │   ├── collect.md             │  단계별 진입점
    │   ├── analyze.md             │
    │   ├── decide.md              │
    │   └── demo.md                가상 플랜트 만들기
    ├── bin/
    │   ├── sf_virtual_plant.py    가상 플랜트 (시나리오·가상 시계·조치 반영)
    │   ├── sf-demo-data           가상 플랜트 생성
    │   ├── sf-collect             ② 사실: 수집
    │   ├── sf-signals             ② 사실: 분석 재료
    │   └── sf-actuate             ② 사실: 제안·승인·기각·실행 기록
    ├── skills/
    │   ├── collect/SKILL.md       ③ 절차: 수집이 온전한가
    │   ├── analyze/SKILL.md       ③ 절차: 데이터 신뢰 → 소견 → 소견서
    │   └── decide/SKILL.md        ③ 절차: 소견 → 제안 → 사람에게
    └── hooks/
        ├── hooks.json             ④ 훅 등록 (Bash + Write/Edit)
        └── guard.py                  가드레일
```

가상 플랜트 디렉터리 (`sf-demo-data` 가 만든다):

```
/tmp/sf-demo/
├── .sf-harness                    훅 범위 마커
├── .claude/settings.json          프로젝트 단위 훅 등록
├── state.json                     가상 시계 + 설비 상태 (running/stopped, speed)
├── config/thresholds.csv          equipment,sensor,unit,lo_crit,lo_warn,hi_warn,hi_crit
├── signals/<설비>.csv             timestamp,sensor,value   ← sf-collect 가 추가
├── maintenance_log.csv            equipment,date,type,note
├── work_orders.csv                sf-actuate 가 읽고 쓴다
├── decisions.csv                  제안 대장 (pending / approved / rejected)
├── reports/analysis.md            analyze 스킬이 쓰는 소견서
└── actions.log                    sf-actuate 가 추가만 한다
```

---

## 여기서 다루지 않은 것

의도적으로 뺐다.

- **실시간 스트리밍** — 이 하네스는 "저장된" 신호를 본다. 실시간 경보는 PLC·SCADA 의 일이고,
  하네스는 그 위에서 "그래서 무엇을 할 것인가"를 판단한다
- **이상 탐지 모델** — z-score·추세만 쓴다. Isolation Forest 나 오토인코더는 `sf-signals` 의
  새 KEY 로 들어오면 되고, 스킬은 바뀌지 않는다. 그게 사실과 판단을 나눈 이유다
- **실제 설비 연동** — `sf-collect` 와 `sf-actuate` 는 파일에 기록한다. 실제로는 OPC-UA 수집기와
  MES·CMMS API 호출이 들어간다. 그때도 `approve` 와 `stop` 을 훅으로 막는 구조는 같다
- **서브에이전트** — 설비 50대면 설비 하나당 분석 에이전트 하나를 격리해 돌리는 게 맞다. 4대에는 과하다
- **승인 UI** — 사람의 결정은 터미널 명령이다. 실제로는 승인 화면·알림이 붙는다

**규모가 커지고 나서 도입한다.** 처음부터 넣으면 배보다 배꼽이 커진다.
