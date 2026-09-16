#!/usr/bin/env bash
# sf-harness 테스트.
#
# 수업 포인트: 하네스도 코드다. 코드니까 테스트한다.
#
#   스킬(마크다운)은 테스트하기 어렵다 — 출력이 매번 다르니까.
#   하지만 스크립트와 훅은 결정적이다. 결정적인 것은 전부 테스트한다.
#   센서 통계를 스크립트로 뺐기 때문에 "CRIT 연속 12샘플"이 정확히 12인지 검증할 수 있고,
#   가상 플랜트를 (설비, 분) 시드로 고정했기 때문에 "5분씩 두 번 = 10분 한 번"도 검증할 수 있다.
#
# 사용법:  ./test/run-tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/sf-harness/bin"
GUARD="$ROOT/sf-harness/hooks/guard.py"
NOW="2026-09-16T14:00:00"     # 가상 시계의 시작을 고정해야 STALE·DAYS_SINCE_MAINT 가 흔들리지 않는다

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  \033[31m✗\033[0m %s\n     기대: %s\n     실제: %s\n" "$1" "$2" "$3"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PLANT="$TMP/plant"

OUT=""
field() { echo "$OUT" | grep -m1 "^$1:" | sed "s/^$1:[[:space:]]*//"; }
check() {  # check <설명> <키> <기대값>   (OUT 에서 찾는다)
  got="$(field "$2")"; [ "$got" = "$3" ] && ok "$1" || bad "$1" "$2=$3" "$2=$got"
}
contains() {  # contains <설명> <키> <부분문자열>
  got="$(field "$2")"; case "$got" in *"$3"*) ok "$1" ;; *) bad "$1" "$2 에 $3" "$2=$got" ;; esac
}
is_error() {  # is_error <설명> <출력>
  case "$2" in ERROR:*) ok "$1" ;; *) bad "$1" "ERROR: 로 시작" "$2" ;; esac
}

# ─── sf-demo-data ─────────────────────────────────────────────
echo "sf-demo-data"
OUT="$("$BIN/sf-demo-data" "$PLANT" --now "$NOW" 2>&1)"
for f in config/thresholds.csv signals/CNC-02.csv maintenance_log.csv work_orders.csv decisions.csv state.json .sf-harness; do
  [ -f "$PLANT/$f" ] && ok "$f 생성" || bad "$f" "있음" "없음"
done
[ -e "$PLANT/.claude" ] && bad "프로젝트 설정을 만들지 않는다" "없음" "있음" || ok "프로젝트 설정(.claude/)을 만들지 않는다 — 훅은 플러그인이 전역으로 건다"
[ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['clock'])" "$PLANT/state.json")" = "$NOW" ] \
  && ok "가상 시계가 --now 로 시작" || bad "clock" "$NOW" "다름"
[ "$(tail -n +2 "$PLANT/signals/CNC-01.csv" | wc -l)" = 360 ] && ok "이력 120분 × 3센서 = 360행" || bad "이력" "360" "$(tail -n +2 "$PLANT/signals/CNC-01.csv" | wc -l)"
OUT2="$("$BIN/sf-demo-data" "$PLANT" 2>&1)"
case "$OUT2" in 이미\ 있다*) ok "이미 있으면 덮어쓰지 않는다" ;; *) bad "덮어쓰기 방지" "이미 있다" "$OUT2" ;; esac
mkdir -p "$TMP/notplant"; O="$("$BIN/sf-demo-data" "$TMP/notplant" --fresh 2>&1)"
case "$O" in ERROR:*) ok "--fresh 는 마커 없는 디렉터리를 지우지 않는다" ;; *) bad "--fresh 안전장치" "ERROR:" "$O" ;; esac
"$BIN/sf-demo-data" "$PLANT" --now "$NOW" --fresh >/dev/null 2>&1 \
  && [ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['clock'])" "$PLANT/state.json")" = "$NOW" ] \
  && ok "--fresh 로 실습 플랜트를 지우고 다시 만든다" || bad "--fresh" "재생성" "실패"
# 결정성: 같은 --now 로 두 번 만들면 파일이 같다
"$BIN/sf-demo-data" "$TMP/plant2" --now "$NOW" >/dev/null 2>&1
diff -rq "$PLANT/signals" "$TMP/plant2/signals" >/dev/null && ok "같은 시작 시각이면 이력이 완전히 같다" || bad "결정성" "동일" "다름"

# ─── sf-signals (수집 전: t = 0) ──────────────────────────────
echo
echo "sf-signals  (수집 전, 가상 시계 $NOW)"
OUT="$("$BIN/sf-signals" "$PLANT" 2>&1)"
check   "봉투 시작"                       SF_SIGNALS_PROTO 1
echo "$OUT" | grep -q "^SF_SIGNALS_OK$" && ok "봉투 끝 (SF_SIGNALS_OK)" || bad "봉투 끝" "SF_SIGNALS_OK" "없음"
check   "기준 시각 = 가상 시계 (--now 없이)" NOW "$NOW"
check   "기준 시각 출처 표시"             NOW_SOURCE state.json
check   "설비 수"                         EQUIPMENT_COUNT 4
check   "파싱 오류 없음"                  PARSE_ERRORS 0
check   "설비 상태 표시"                  CNC-02.STATE "running speed=100"
check   "대기 중 제안 0"                  CNC-02.PENDING_DECISIONS 0
# CNC-02: 위험
check   "CNC-02 진동 마지막 샘플 CRIT"     CNC-02.vibration.STATUS CRIT
check   "CNC-02 진동 CRIT 연속 12"         CNC-02.vibration.CRIT_STREAK 12
check   "CNC-02 온도 WARN 진입"            CNC-02.temperature.STATUS WARN
check   "CNC-02 이미 넘었으면 MIN_TO_WARN 0" CNC-02.vibration.MIN_TO_WARN 0
# CNC-01: 추세와 일시 스파이크
check   "CNC-01 온도 아직 OK"              CNC-01.temperature.STATUS OK
case "$(field CNC-01.temperature.TREND_PER_HOUR)" in +*) ok "CNC-01 온도 추세 양수" ;; *) bad "추세 부호" "+" "$(field CNC-01.temperature.TREND_PER_HOUR)" ;; esac
m="$(field CNC-01.temperature.MIN_TO_WARN)"
[ "$m" != none ] && [ "$m" -gt 30 ] && [ "$m" -lt 120 ] && ok "CNC-01 온도 30~120분 뒤 WARN (외삽)" || bad "MIN_TO_WARN" "30~120" "$m"
check   "CNC-01 전류 스파이크 1회"         CNC-01.current.OVER_CRIT 1
check   "CNC-01 전류 연속 CRIT 는 0"       CNC-01.current.CRIT_STREAK 0
check   "CNC-01 정비 45일 경과"            CNC-01.DAYS_SINCE_MAINT 45
# PRESS-01: 센서 문제
check   "PRESS-01 압력 FLATLINE"           PRESS-01.pressure.FLATLINE 1
check   "PRESS-01 압력 STATUS 는 그대로 OK (판단은 스킬이)" PRESS-01.pressure.STATUS OK
check   "PRESS-01 cycle_time NO_DATA"      PRESS-01.cycle_time.STATUS NO_DATA
check   "PRESS-01 누락 센서 목록"          PRESS-01.MISSING_SENSORS cycle_time
check   "PRESS-01 열린 작업지시 1"         PRESS-01.OPEN_WORK_ORDERS 1
# CONV-01: 데이터 끊김
check   "CONV-01 45분째 데이터 없음"       CONV-01.STALE_MIN 45
check   "끊긴 설비는 MISSING 으로 중복 보고 안 함" CONV-01.MISSING_SENSORS none
# 요약
check    "ALERT_CRIT"                     ALERT_CRIT "CNC-02.vibration"
check    "ALERT_WARN"                     ALERT_WARN "CNC-02.temperature"
contains "SENSOR_SUSPECT 에 FLATLINE"     SENSOR_SUSPECT "PRESS-01.pressure(FLATLINE)"
contains "SENSOR_SUSPECT 에 MISSING"      SENSOR_SUSPECT "PRESS-01.cycle_time(MISSING)"
check    "STALE_EQUIPMENT"                STALE_EQUIPMENT "CONV-01"
# 플랜트 경로 자동 인식: 인자 → $SF_PLANT_DIR → 현재 → /tmp/sf-demo
O="$(cd "$TMP" && SF_PLANT_DIR="$PLANT" "$BIN/sf-signals" 2>&1 | grep -m1 '^PLANT_DIR:')"
[ "$O" = "PLANT_DIR: $PLANT" ] && ok "인자 없으면 \$SF_PLANT_DIR 의 플랜트를 쓴다 (어느 디렉터리에서든)" || bad "SF_PLANT_DIR" "$PLANT" "$O"
O="$(cd "$PLANT" && "$BIN/sf-signals" 2>&1 | grep -m1 '^PLANT_DIR:')"
[ "$O" = "PLANT_DIR: $PLANT" ] && ok "인자 없으면 현재 디렉터리가 플랜트면 그것을 쓴다" || bad "cwd plant" "$PLANT" "$O"
O="$(cd "$TMP" && SF_PLANT_DIR="$PLANT" "$BIN/sf-actuate" list 2>&1 | grep -m1 '^SF_ACTUATE_OK$')"
[ "$O" = "SF_ACTUATE_OK" ] && ok "sf-actuate 도 같은 규칙" || bad "actuate resolve" "OK" "$O"
is_error "인자로 준 경로가 플랜트가 아니면 ERROR (조용히 다른 곳으로 가지 않는다)" "$(SF_PLANT_DIR="$PLANT" "$BIN/sf-signals" "$TMP" 2>&1)"

# --now 를 주면 가상 시계보다 우선한다
O="$("$BIN/sf-signals" "$PLANT" --now 2026-09-16T13:30:00 2>&1 | grep -m1 '^NOW_SOURCE:')"
[ "$O" = "NOW_SOURCE: --now" ] && ok "--now 가 가상 시계보다 우선" || bad "--now 우선" "--now" "$O"
# 오류 경로 — 파이프에 넣지 말고 먼저 받아둔다 (exit 1 이 pipefail 을 건드린다)
is_error "없는 경로면 ERROR"          "$("$BIN/sf-signals" "$TMP/없는경로" 2>&1)"
mkdir -p "$TMP/empty"
is_error "thresholds.csv 없으면 ERROR" "$("$BIN/sf-signals" "$TMP/empty" 2>&1)"
is_error "--now 형식 오류면 ERROR"    "$("$BIN/sf-signals" "$PLANT" --now "16/09/2026" 2>&1)"

# ─── sf-collect (1단계: 수집) ─────────────────────────────────
echo
echo "sf-collect"
OUT="$("$BIN/sf-collect" "$PLANT" --minutes 5 2>&1)"
check "봉투 시작"                  SF_COLLECT_PROTO 1
echo "$OUT" | grep -q "^SF_COLLECT_OK$" && ok "봉투 끝 (SF_COLLECT_OK)" || bad "봉투 끝" "SF_COLLECT_OK" "없음"
check "수집 전 시계"               CLOCK_BEFORE "$NOW"
check "수집 후 시계 +5분"          CLOCK_AFTER "2026-09-16T14:05:00"
check "CNC-01 5분 × 3센서 = 15"     CNC-01.NEW_SAMPLES 15
check "PRESS-01 cycle_time 은 조용" PRESS-01.SENSORS_SILENT cycle_time
check "CONV-01 은 아직 끊김"        CONV-01.NEW_SAMPLES 0
check "조용한 설비 목록"           SILENT_EQUIPMENT CONV-01
check "총 샘플 (15+15+10+0)"        TOTAL_NEW_SAMPLES 40
[ "$(tail -n +2 "$PLANT/signals/CNC-01.csv" | wc -l)" = 375 ] && ok "signals/ 에 추가됐다 (360 → 375)" || bad "append" "375" "$(tail -n +2 "$PLANT/signals/CNC-01.csv" | wc -l)"
head -1 "$PLANT/signals/CNC-01.csv" | grep -q "^timestamp,sensor,value$" && ok "헤더는 한 번만" || bad "헤더" "1" "다름"

# 수집 후 분석: 시계가 움직였고, CRIT 연속이 늘었다
OUT="$("$BIN/sf-signals" "$PLANT" 2>&1)"
check "sf-signals 기준 시각도 5분 전진"   NOW "2026-09-16T14:05:00"
check "CNC-02 CRIT 연속 12 → 17"          CNC-02.vibration.CRIT_STREAK 17
check "CONV-01 STALE 45 → 50"             CONV-01.STALE_MIN 50

# 결정성: 5분 + 5분 == 10분 한 번
"$BIN/sf-collect" "$PLANT" --minutes 5 >/dev/null
"$BIN/sf-collect" "$TMP/plant2" --minutes 10 >/dev/null
diff -q "$PLANT/signals/CNC-02.csv" "$TMP/plant2/signals/CNC-02.csv" >/dev/null && ok "5분 두 번 = 10분 한 번 (누가 언제 수집해도 같은 값)" || bad "결정성" "동일" "다름"

# 30분 지나면 CONV-01 이 돌아온다 (t = +30 부터)
"$BIN/sf-collect" "$PLANT" --minutes 25 >/dev/null     # 시계 14:35 → t = 35
OUT="$("$BIN/sf-signals" "$PLANT" 2>&1)"
check "CONV-01 데이터 복귀 → STALE 해소"   CONV-01.STALE_MIN 1
check "STALE_EQUIPMENT 비었다"             STALE_EQUIPMENT none
# CNC-01 두 번째 스파이크 (t = 25) 가 창 안에 들어왔다
check "CNC-01 전류 스파이크 반복 (창 안 1회 — 첫 스파이크는 창 밖)" CNC-01.current.OVER_CRIT 1
# 오류 경로
is_error "가상 플랜트가 아니면 ERROR"   "$("$BIN/sf-collect" "$TMP/empty" 2>&1)"
is_error "--minutes 0 은 ERROR"        "$("$BIN/sf-collect" "$PLANT" --minutes 0 2>&1)"

# ─── sf-actuate (3단계: 제안 → 사람의 결정) ───────────────────
echo
echo "sf-actuate"
CLK="2026-09-16T14:35:00"
A="$("$BIN/sf-actuate" --plant "$PLANT" list 2>&1)"
echo "$A" | grep -q "^PENDING_DECISIONS: 0$" && ok "list: 대기 중 제안 0" || bad "list" "PENDING 0" "$A"
echo "$A" | grep -q "^OPEN_WORK_ORDERS: 1$" && ok "list: 열린 작업지시 1" || bad "list" "WO 1" "$A"
echo "$A" | grep -q "^CLOCK: $CLK$" && ok "list: 가상 시계 표시" || bad "list clock" "$CLK" "$A"

is_error "근거(--reason) 없으면 기록하지 않는다" "$("$BIN/sf-actuate" --plant "$PLANT" propose CNC-02 stop --reason "" 2>&1)"
is_error "모르는 설비면 ERROR"                  "$("$BIN/sf-actuate" --plant "$PLANT" propose CNC-99 stop --reason x 2>&1)"
is_error "예약 제안에 --when 없으면 ERROR"      "$("$BIN/sf-actuate" --plant "$PLANT" propose CNC-01 schedule-maintenance --reason x 2>&1)"
is_error "감속 제안 50% 미만은 ERROR"           "$("$BIN/sf-actuate" --plant "$PLANT" propose CNC-01 set-speed --percent 20 --reason x 2>&1)"

OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" propose CNC-02 stop --reason "vibration CRIT_STREAK 12, temperature WARN 동반" 2>&1)"
check "정지 제안 → DEC-0001"        DECISION DEC-0001
check "제안은 pending"              STATUS pending
contains "승인 명령을 알려준다"      HUMAN_APPROVE "approve DEC-0001"
echo "$OUT" | grep -q "^SF_ACTUATE_OK$" && ok "봉투 끝" || bad "봉투" "OK" "$OUT"
grep -q "^DEC-0001,.*,CNC-02,stop,,.*,pending,,$" "$PLANT/decisions.csv" && ok "decisions.csv 에 기록" || bad "csv" "DEC-0001 pending" "$(cat "$PLANT/decisions.csv")"
[ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['equipment']['CNC-02']['status'])" "$PLANT/state.json")" = running ] \
  && ok "제안만으로는 설비가 서지 않는다" || bad "propose 부작용" "running" "stopped"
is_error "같은 제안 중복은 ERROR" "$("$BIN/sf-actuate" --plant "$PLANT" propose CNC-02 stop --reason x 2>&1)"
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" propose CNC-01 schedule-maintenance --when next-shift --reason "temperature +4/h, 정비 45일" 2>&1)"
check "예약 제안 → DEC-0002"        DECISION DEC-0002
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" propose CNC-01 recheck --reason "current 스파이크 1회" 2>&1)"
check "재확인 제안 → DEC-0003"      DECISION DEC-0003
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" propose CNC-01 set-speed --percent 80 --reason "온도 상승" 2>&1)"
check "감속 제안 → DEC-0004"        DECISION DEC-0004
S="$("$BIN/sf-signals" "$PLANT" 2>&1 | grep -m1 '^CNC-01.PENDING_DECISIONS:')"
[ "$S" = "CNC-01.PENDING_DECISIONS: 3" ] && ok "sf-signals 가 대기 중 제안을 센다" || bad "연동" "3" "$S"

# 사람의 결정
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" approve DEC-0001 2>&1)"
check "승인 → 실행"                 EXECUTED stop
check "승인 상태"                   STATUS approved
[ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['equipment']['CNC-02']['status'])" "$PLANT/state.json")" = stopped ] \
  && ok "승인하면 설비 상태가 stopped" || bad "state" "stopped" "running"
grep -q "	stop	CNC-02	via=DEC-0001	" "$PLANT/actions.log" && ok "actions.log 에 어느 제안으로 실행됐는지 남는다" || bad "log" "via=DEC-0001" "$(cat "$PLANT/actions.log")"
is_error "이미 결정된 제안은 다시 못 한다" "$("$BIN/sf-actuate" --plant "$PLANT" approve DEC-0001 2>&1)"
is_error "없는 제안은 ERROR"              "$("$BIN/sf-actuate" --plant "$PLANT" approve DEC-9999 2>&1)"
is_error "기각에는 --reason 필수"          "$("$BIN/sf-actuate" --plant "$PLANT" reject DEC-0002 2>&1 | head -1 | sed 's/^usage.*/ERROR: usage/')"
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" reject DEC-0004 --reason "생산 일정상 감속 불가" 2>&1)"
check "기각"                        STATUS rejected
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" approve DEC-0002 2>&1)"
contains "예약 승인 → 작업지시 발행"  EXECUTED "schedule-maintenance WO-0002"
grep -q "^WO-0002,.*,CNC-01,schedule-maintenance,next-shift,.*open$" "$PLANT/work_orders.csv" && ok "work_orders.csv 에 WO-0002" || bad "WO" "WO-0002" "$(cat "$PLANT/work_orders.csv")"
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" approve DEC-0003 2>&1)"
contains "재확인 승인은 설비에 아무것도 안 한다" EXECUTED recheck
A="$("$BIN/sf-actuate" --plant "$PLANT" list 2>&1)"
echo "$A" | grep -q "^PENDING_DECISIONS: 0$" && ok "전부 결정되면 대기 0" || bad "list" "0" "$A"
echo "$A" | grep -q "^CNC-02.STATE: stopped" && ok "list 에 정지 상태" || bad "list state" "stopped" "$A"

# 승인한 조치가 다음 수집에 반영된다 (루프가 닫힌다)
"$BIN/sf-collect" "$PLANT" --minutes 20 >/dev/null
OUT="$("$BIN/sf-signals" "$PLANT" 2>&1)"
check "정지한 설비는 사실에도 stopped"     CNC-02.STATE "stopped speed=100"
check "정지 후 진동 값이 OK 로 내려온다"   CNC-02.vibration.STATUS OK
check "정지 후 CRIT 연속 0"                CNC-02.vibration.CRIT_STREAK 0
S="$(field CNC-02.vibration.LAST)"; python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < 0.5 else 1)" "$S" && ok "정지 후 진동 ≈ 0 ($S)" || bad "idle" "<0.5" "$S"

# 직접 실행 명령 (사람용) 과 되돌리기
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" set-speed CNC-01 80 --reason "온도 상승" 2>&1)"
check "감속 직접 실행"              PERCENT 80
"$BIN/sf-collect" "$PLANT" --minutes 5 >/dev/null
OUT="$("$BIN/sf-signals" "$PLANT" 2>&1)"
check "감속이 상태에 반영"          CNC-01.STATE "running speed=80"
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" cancel WO-0002 --reason "오탐" 2>&1)"
check "작업지시는 되돌릴 수 있다 (cancel)" STATUS cancelled
is_error "이미 취소된 것은 다시 취소 못 한다" "$("$BIN/sf-actuate" --plant "$PLANT" cancel WO-0002 --reason x 2>&1)"
is_error "set-speed 50% 미만은 거부"          "$("$BIN/sf-actuate" --plant "$PLANT" set-speed CNC-01 20 --reason x 2>&1)"
OUT="$("$BIN/sf-actuate" --plant "$PLANT" --now "$CLK" stop PRESS-01 --reason "긴급" 2>&1)"
check "stop 직접 실행 (사람이 치면 된다 — 훅은 에이전트에만)" REVERSIBLE "no  (재가동은 현장 승인 후 별도 절차)"

# ─── guard.py (4단계: 훅) ─────────────────────────────────────
echo
echo "guard.py  (플랜트 디렉터리 안 = 훅 대상)"
cd "$PLANT"
g() {  # g <설명> <DENY|PASS> <Bash 명령>
  out="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$3" | python3 "$GUARD")"
  got=$([ -n "$out" ] && echo DENY || echo PASS)
  [ "$got" = "$2" ] && ok "$1" || bad "$1" "$2" "$got"
}
gf() {  # gf <설명> <DENY|PASS> <도구> <file_path>
  out="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2],"content":"x"}}))' "$3" "$4" | python3 "$GUARD")"
  got=$([ -n "$out" ] && echo DENY || echo PASS)
  [ "$got" = "$2" ] && ok "$1" || bad "$1" "$2" "$got"
}

g "승인은 사람만"                     DENY "sf-actuate approve DEC-0001"
g "기각도 사람만"                     DENY "sf-actuate reject DEC-0001 --reason x"
g "옵션 뒤의 approve 도 잡는다"       DENY "sf-actuate --plant /tmp/x approve DEC-0001"
g "설비 정지"                         DENY "sf-actuate stop CNC-02 --reason '진동 CRIT'"
g "절대 경로 sf-actuate"              DENY "$BIN/sf-actuate stop CNC-02 --reason x"
g "&& 뒤의 stop 도 잡는다"            DENY "cd /tmp && sf-actuate stop CNC-02 --reason x"
g "emergency-stop"                    DENY "sf-actuate emergency-stop CNC-02 --reason x"
g "제안은 통과 (에이전트의 산출물)"   PASS "sf-actuate propose CNC-02 stop --reason '진동 CRIT 연속 12'"
g "reason 에 approve/stop 이 있어도 통과" PASS "sf-actuate propose CNC-01 recheck --reason 'approve 전에 stop 여부 재확인'"
g "작업지시 직접 발행은 통과 (되돌릴 수 있다)" PASS "sf-actuate schedule-maintenance CNC-01 --when next-shift --reason x"
g "속도 저감은 통과"                  PASS "sf-actuate set-speed CNC-01 80 --reason x"
g "list 는 통과"                      PASS "sf-actuate list"
g "수집은 통과"                       PASS "sf-collect . --minutes 5"
g "따옴표 안 문자열은 통과"           PASS "echo 'sf-actuate approve 예시'"
g "원본 로그 삭제"                    DENY "rm signals/CNC-02.csv"
g "원본 로그 디렉터리 삭제"           DENY "rm -rf $PLANT/signals"
g "원본 로그 이동"                    DENY "mv signals/CNC-02.csv /tmp/"
g "원본 로그 덮어쓰기 (>)"            DENY "python3 clean.py > signals/CNC-02.csv"
g "원본 로그 이어쓰기 (>>)"           DENY "echo x >> signals/CNC-02.csv"
g "원본 로그 읽기는 통과"             PASS "head signals/CNC-02.csv"
g "소견서 쓰기는 통과"                PASS "cat > reports/analysis.md"
g "비슷한 이름은 통과 (my_signals)"   PASS "rm my_signals.txt"
g "한계값 sed -i 수정"                DENY "sed -i 's/7.1/9.0/' config/thresholds.csv"
g "한계값 덮어쓰기"                   DENY "cat new.csv > config/thresholds.csv"
g "한계값 삭제"                       DENY "rm config/thresholds.csv"
g "한계값 읽기는 통과"                PASS "cat config/thresholds.csv"
g "stderr 리다이렉트는 통과 (2>)"     PASS "sf-signals . 2> signals_err.log"
gf "Write 로 한계값 편집"             DENY Write "$PLANT/config/thresholds.csv"
gf "Edit 로 원본 로그 편집"           DENY Edit  "$PLANT/signals/CNC-01.csv"
gf "Write 로 소견서 작성은 통과"      PASS Write "$PLANT/reports/analysis.md"
gf "Read 도구는 검사 안 함"           PASS Read  "$PLANT/config/thresholds.csv"

out="$(echo 'not json' | python3 "$GUARD")"
[ -z "$out" ] && ok "깨진 입력은 통과 (fail-open)" || bad "깨진 입력" "PASS" "DENY"
out="$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"sf-actuate approve DEC-0001"}}))' | python3 "$GUARD")"
echo "$out" | grep -q "운영자" && ok "차단 사유에 '누가 결정하는지'가 있다" || bad "사유" "운영자 언급" "$out"

# 플랜트 밖에서 Claude 를 띄웠을 때 — 어느 디렉터리에서든 실습이 되어야 한다
cd "$TMP"
echo
echo "guard.py  (플랜트 밖 디렉터리 = 실무 저장소일 수도 있다)"
g "우리 명령(approve)은 어디서든 막는다"   DENY "sf-actuate approve DEC-0001"
g "우리 명령(stop)은 어디서든 막는다"      DENY "sf-actuate --plant $PLANT stop CNC-02 --reason x"
g "명령에 적힌 절대 경로로 범위를 안다"     DENY "rm $PLANT/signals/CNC-02.csv"
g "플랜트 디렉터리 통째로도 안다"          DENY "rm -rf $PLANT/signals"
g "절대 경로 thresholds.csv 수정"          DENY "sed -i 's/7.1/9/' $PLANT/config/thresholds.csv"
g "절대 경로 덮어쓰기"                     DENY "cat x > $PLANT/config/thresholds.csv"
g "마커 없는 곳의 signals 는 남의 파일 — 통과" PASS "rm -rf signals"
g "마커 없는 곳의 thresholds.csv 도 통과"  PASS "sed -i 's/a/b/' config/thresholds.csv"
g "마커 없는 절대 경로도 통과"             PASS "rm $TMP/empty/signals.csv"
SF_HARNESS_GUARD=1 g "환경변수로 켜면 어디서든 막힌다" DENY "rm -rf signals"
gf "cwd 밖이어도 플랜트 파일 편집은 막는다" DENY Write "$PLANT/config/thresholds.csv"
mkdir -p "$TMP/other/config"; touch "$TMP/other/config/thresholds.csv"
gf "마커 없는 곳의 thresholds.csv 편집은 통과" PASS Write "$TMP/other/config/thresholds.csv"
out="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"rm signals/x.csv"}}))' "$PLANT" | python3 "$GUARD")"
[ -n "$out" ] && ok "입력 JSON 의 cwd 로 범위를 판단한다" || bad "cwd 필드" "DENY" "PASS"

# ─── 결과 ─────────────────────────────────────────────────────
echo
if [ "$FAIL" -eq 0 ]; then
  printf "\033[32m%d개 통과, 실패 없음\033[0m\n" "$PASS"; exit 0
else
  printf "\033[31m%d개 통과, %d개 실패\033[0m\n" "$PASS" "$FAIL"; exit 1
fi
