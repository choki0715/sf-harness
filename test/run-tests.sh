#!/usr/bin/env bash
# sf-harness 테스트.
#
# 수업 포인트: 하네스도 코드다. 코드니까 테스트한다.
#
#   스킬(마크다운)은 테스트하기 어렵다 — 출력이 매번 다르니까.
#   하지만 스크립트와 훅은 결정적이다. 결정적인 것은 전부 테스트한다.
#   센서 통계를 스크립트로 뺐기 때문에 "CRIT 연속 12샘플"이 정확히 12인지 검증할 수 있다.
#   LLM 에게 세게 했다면 이 테스트는 쓸 수 없었다.
#
# 사용법:  ./test/run-tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/sf-harness/bin"
GUARD="$ROOT/sf-harness/hooks/guard.py"
NOW="2026-09-16T14:00:00"     # 기준 시각을 고정해야 STALE·DAYS_SINCE_MAINT 가 흔들리지 않는다

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  \033[31m✗\033[0m %s\n     기대: %s\n     실제: %s\n" "$1" "$2" "$3"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PLANT="$TMP/plant"

# ─── sf-demo-data ─────────────────────────────────────────────
echo "sf-demo-data"
OUT="$("$BIN/sf-demo-data" "$PLANT" --now "$NOW" 2>&1)"
[ -f "$PLANT/config/thresholds.csv" ] && ok "thresholds.csv 생성" || bad "thresholds.csv" "있음" "없음"
[ -f "$PLANT/signals/CNC-02.csv" ]    && ok "signals/*.csv 생성"  || bad "signals" "있음" "없음"
[ -f "$PLANT/.sf-harness" ]           && ok "훅 범위 마커 생성"   || bad "마커" "있음" "없음"
[ -f "$PLANT/.claude/settings.json" ] && ok "프로젝트 훅 등록"    || bad "settings.json" "있음" "없음"
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PLANT/.claude/settings.json" 2>/dev/null \
  && ok "settings.json 이 유효한 JSON" || bad "settings.json" "유효" "깨짐"
OUT2="$("$BIN/sf-demo-data" "$PLANT" 2>&1)"
case "$OUT2" in 이미\ 있다*) ok "이미 있으면 덮어쓰지 않는다" ;; *) bad "덮어쓰기 방지" "이미 있다" "$OUT2" ;; esac

# ─── sf-signals ───────────────────────────────────────────────
echo
echo "sf-signals"
OUT="$("$BIN/sf-signals" "$PLANT" --now "$NOW" 2>&1)"
field() { echo "$OUT" | grep -m1 "^$1:" | sed "s/^$1:[[:space:]]*//"; }
check() {  # check <설명> <키> <기대값>
  got="$(field "$2")"; [ "$got" = "$3" ] && ok "$1" || bad "$1" "$2=$3" "$2=$got"
}
checkge() {  # checkge <설명> <키> <최소>
  got="$(field "$2")"; [ -n "$got" ] && [ "$got" != none ] && [ "$got" -ge "$3" ] 2>/dev/null \
    && ok "$1" || bad "$1" "$2>=$3" "$2=$got"
}
contains() {  # contains <설명> <키> <부분문자열>
  got="$(field "$2")"; case " $got " in *" $3 "*|*"$3"*) ok "$1" ;; *) bad "$1" "$2 에 $3" "$2=$got" ;; esac
}

check   "봉투 시작"                       SF_SIGNALS_PROTO 1
echo "$OUT" | grep -q "^SF_SIGNALS_OK$" && ok "봉투 끝 (SF_SIGNALS_OK)" || bad "봉투 끝" "SF_SIGNALS_OK" "없음"
check   "설비 수"                         EQUIPMENT_COUNT 4
check   "기준 시각 고정"                  NOW "$NOW"
check   "파싱 오류 없음"                  PARSE_ERRORS 0
# CNC-02: 지금 세워야 하는 설비
check   "CNC-02 진동 마지막 샘플 CRIT"     CNC-02.vibration.STATUS CRIT
check   "CNC-02 진동 CRIT 연속 12"         CNC-02.vibration.CRIT_STREAK 12
check   "CNC-02 진동 CRIT 개수 12"         CNC-02.vibration.OVER_CRIT 12
check   "CNC-02 온도 WARN 진입"            CNC-02.temperature.STATUS WARN
checkge "CNC-02 온도 WARN 연속 ≥ 3"        CNC-02.temperature.WARN_STREAK 3
check   "CNC-02 이미 넘었으면 MIN_TO_WARN 0" CNC-02.vibration.MIN_TO_WARN 0
# CNC-01: 추세와 일시 스파이크
check   "CNC-01 온도 아직 OK"              CNC-01.temperature.STATUS OK
case "$(field CNC-01.temperature.TREND_PER_HOUR)" in +*) ok "CNC-01 온도 추세 양수" ;; *) bad "추세 부호" "+" "$(field CNC-01.temperature.TREND_PER_HOUR)" ;; esac
m="$(field CNC-01.temperature.MIN_TO_WARN)"
[ "$m" != none ] && [ "$m" -gt 30 ] && [ "$m" -lt 120 ] && ok "CNC-01 온도 30~120분 뒤 WARN (외삽)" || bad "MIN_TO_WARN" "30~120" "$m"
check   "CNC-01 전류 스파이크 1회"         CNC-01.current.OVER_CRIT 1
check   "CNC-01 전류 연속 CRIT 는 0"       CNC-01.current.CRIT_STREAK 0
check   "CNC-01 전류 마지막 샘플은 OK"     CNC-01.current.STATUS OK
check   "CNC-01 정비 45일 경과"            CNC-01.DAYS_SINCE_MAINT 45
# PRESS-01: 센서 문제
check   "PRESS-01 압력 FLATLINE"           PRESS-01.pressure.FLATLINE 1
check   "PRESS-01 압력 STATUS 는 그대로 OK (판단은 스킬이)" PRESS-01.pressure.STATUS OK
check   "PRESS-01 cycle_time NO_DATA"      PRESS-01.cycle_time.STATUS NO_DATA
check   "PRESS-01 누락 센서 목록"          PRESS-01.MISSING_SENSORS cycle_time
check   "PRESS-01 열린 작업지시 1"         PRESS-01.OPEN_WORK_ORDERS 1
check   "PRESS-01 정비 70일 경과"          PRESS-01.DAYS_SINCE_MAINT 70
# CONV-01: 데이터 끊김
check   "CONV-01 45분째 데이터 없음"       CONV-01.STALE_MIN 45
check   "CONV-01 끊긴 설비는 MISSING 으로 중복 보고 안 함" CONV-01.MISSING_SENSORS none
# 요약
check    "ALERT_CRIT"                     ALERT_CRIT "CNC-02.vibration"
check    "ALERT_WARN"                     ALERT_WARN "CNC-02.temperature"
contains "SENSOR_SUSPECT 에 FLATLINE"     SENSOR_SUSPECT "PRESS-01.pressure(FLATLINE)"
contains "SENSOR_SUSPECT 에 MISSING"      SENSOR_SUSPECT "PRESS-01.cycle_time(MISSING)"
check    "STALE_EQUIPMENT"                STALE_EQUIPMENT "CONV-01"

# 창 크기를 바꾸면 샘플 수가 바뀐다
OUT30="$("$BIN/sf-signals" "$PLANT" --now "$NOW" --window 30 2>&1)"
n60="$(field SAMPLE_COUNT)"; n30="$(echo "$OUT30" | grep -m1 '^SAMPLE_COUNT:' | sed 's/.*: //')"
[ "$n30" -lt "$n60" ] && ok "--window 30 이면 샘플이 준다 ($n60 → $n30)" || bad "window" "$n30 < $n60" "$n30"

# 오류 경로 — 파이프에 넣지 말고 먼저 받아둔다 (exit 1 이 pipefail 을 건드린다)
E="$("$BIN/sf-signals" "$TMP/없는경로" 2>&1)"; case "$E" in ERROR:*) ok "없는 경로면 ERROR" ;; *) bad "없는 경로" "ERROR:" "$E" ;; esac
mkdir -p "$TMP/empty"
E="$("$BIN/sf-signals" "$TMP/empty" 2>&1)";   case "$E" in ERROR:*) ok "thresholds.csv 없으면 ERROR" ;; *) bad "빈 디렉터리" "ERROR:" "$E" ;; esac
E="$("$BIN/sf-signals" "$PLANT" --now "16/09/2026" 2>&1)"; case "$E" in ERROR:*) ok "--now 형식 오류면 ERROR" ;; *) bad "now 형식" "ERROR:" "$E" ;; esac

# ─── sf-actuate ───────────────────────────────────────────────
echo
echo "sf-actuate"
A="$("$BIN/sf-actuate" --plant "$PLANT" list 2>&1)"
echo "$A" | grep -q "^OPEN_WORK_ORDERS: 1$" && ok "list: 열린 작업지시 1" || bad "list" "OPEN_WORK_ORDERS: 1" "$A"

E="$("$BIN/sf-actuate" --plant "$PLANT" --now "$NOW" schedule-maintenance CNC-01 --when next-shift --reason "" 2>&1)"
case "$E" in ERROR:*) ok "근거(--reason) 없으면 기록하지 않는다" ;; *) bad "reason 필수" "ERROR:" "$E" ;; esac
E="$("$BIN/sf-actuate" --plant "$PLANT" --now "$NOW" schedule-maintenance CNC-99 --when next-shift --reason x 2>&1)"
case "$E" in ERROR:*) ok "모르는 설비면 ERROR" ;; *) bad "모르는 설비" "ERROR:" "$E" ;; esac
E="$("$BIN/sf-actuate" --plant "$PLANT" --now "$NOW" schedule-maintenance CNC-01 --when 내일 --reason x 2>&1)"
case "$E" in ERROR:*) ok "--when 형식 오류면 ERROR" ;; *) bad "when 형식" "ERROR:" "$E" ;; esac

A="$("$BIN/sf-actuate" --plant "$PLANT" --now "$NOW" schedule-maintenance CNC-01 --when next-shift --reason "온도 +4.05 C/h, 61분 뒤 warn" 2>&1)"
echo "$A" | grep -q "^WORK_ORDER: WO-0002$" && ok "작업지시 발행 → WO-0002 (기존 다음 번호)" || bad "발행" "WO-0002" "$A"
echo "$A" | grep -q "^SF_ACTUATE_OK$" && ok "봉투 끝 (SF_ACTUATE_OK)" || bad "봉투" "OK" "$A"
# 사유에 쉼표가 있으면 CSV 가 따옴표로 감싼다 — 그래서 끝의 ,open 만 본다
grep -q "^WO-0002,.*,CNC-01,schedule-maintenance,next-shift,.*open$" "$PLANT/work_orders.csv" \
  && ok "work_orders.csv 에 기록" || bad "csv 기록" "WO-0002 open" "$(cat "$PLANT/work_orders.csv")"
grep -q "schedule-maintenance	CNC-01" "$PLANT/actions.log" && ok "actions.log 에 남는다" || bad "actions.log" "기록" "없음"

S="$("$BIN/sf-signals" "$PLANT" --now "$NOW" 2>&1 | grep -m1 '^CNC-01.OPEN_WORK_ORDERS:')"
[ "$S" = "CNC-01.OPEN_WORK_ORDERS: 1" ] && ok "sf-signals 가 새 작업지시를 센다" || bad "연동" "1" "$S"

A="$("$BIN/sf-actuate" --plant "$PLANT" --now "$NOW" cancel WO-0002 --reason "오탐" 2>&1)"
echo "$A" | grep -q "^STATUS: cancelled$" && ok "작업지시는 되돌릴 수 있다 (cancel)" || bad "cancel" "cancelled" "$A"
E="$("$BIN/sf-actuate" --plant "$PLANT" cancel WO-0002 --reason x 2>&1)"
case "$E" in ERROR:*) ok "이미 취소된 것은 다시 취소 못 한다" ;; *) bad "중복 취소" "ERROR:" "$E" ;; esac

E="$("$BIN/sf-actuate" --plant "$PLANT" set-speed CNC-01 20 --reason x 2>&1)"
case "$E" in ERROR:*) ok "set-speed 50% 미만은 거부 (정지와 같다)" ;; *) bad "speed 범위" "ERROR:" "$E" ;; esac
A="$("$BIN/sf-actuate" --plant "$PLANT" --now "$NOW" set-speed CNC-01 80 --reason "온도 상승" 2>&1)"
echo "$A" | grep -q "^PERCENT: 80$" && ok "set-speed 80% 기록" || bad "set-speed" "80" "$A"

A="$("$BIN/sf-actuate" --plant "$PLANT" --now "$NOW" stop CNC-02 --reason "진동 CRIT 연속 12" 2>&1)"
echo "$A" | grep -q "^REVERSIBLE: no" && ok "stop 은 사람이 실행하면 기록된다 (훅은 에이전트에만)" || bad "stop" "REVERSIBLE: no" "$A"
[ "$(grep -c '	stop	' "$PLANT/actions.log")" = 1 ] && ok "actions.log 는 추가만 한다" || bad "append" "1" "$(cat "$PLANT/actions.log")"

# ─── guard.py ─────────────────────────────────────────────────
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

g "설비 정지"                         DENY "sf-actuate stop CNC-02 --reason '진동 CRIT'"
g "옵션 뒤의 stop 도 잡는다"          DENY "sf-actuate --plant /tmp/x stop CNC-02 --reason x"
g "절대 경로 sf-actuate"              DENY "$BIN/sf-actuate stop CNC-02 --reason x"
g "&& 뒤의 stop 도 잡는다"            DENY "cd /tmp && sf-actuate stop CNC-02 --reason x"
g "emergency-stop"                    DENY "sf-actuate emergency-stop CNC-02 --reason x"
g "작업지시 발행은 통과 (되돌릴 수 있다)" PASS "sf-actuate schedule-maintenance CNC-01 --when next-shift --reason '온도 상승'"
g "reason 에 stop 이 있어도 통과"      PASS "sf-actuate schedule-maintenance CNC-01 --when next-shift --reason 'stop 전에 점검'"
g "속도 저감은 통과"                  PASS "sf-actuate set-speed CNC-01 80 --reason x"
g "list 는 통과"                      PASS "sf-actuate list"
g "따옴표 안 문자열은 통과"           PASS "echo 'sf-actuate stop 예시'"
g "원본 로그 삭제"                    DENY "rm signals/CNC-02.csv"
g "원본 로그 디렉터리 삭제"           DENY "rm -rf $PLANT/signals"
g "원본 로그 이동"                    DENY "mv signals/CNC-02.csv /tmp/"
g "원본 로그 덮어쓰기 (>)"            DENY "python3 clean.py > signals/CNC-02.csv"
g "원본 로그 이어쓰기 (>>)"           DENY "echo x >> signals/CNC-02.csv"
g "원본 로그 읽기는 통과"             PASS "head signals/CNC-02.csv"
g "다른 파일 삭제는 통과"             PASS "rm output/report.md"
g "비슷한 이름은 통과 (my_signals)"   PASS "rm my_signals.txt"
g "한계값 sed -i 수정"                DENY "sed -i 's/7.1/9.0/' config/thresholds.csv"
g "한계값 덮어쓰기"                   DENY "cat new.csv > config/thresholds.csv"
g "한계값 삭제"                       DENY "rm config/thresholds.csv"
g "한계값 읽기는 통과"                PASS "cat config/thresholds.csv"
g "stderr 리다이렉트는 통과 (2>)"     PASS "sf-signals . 2> signals_err.log"
gf "Write 로 한계값 편집"             DENY Write "$PLANT/config/thresholds.csv"
gf "Edit 로 원본 로그 편집"           DENY Edit  "$PLANT/signals/CNC-01.csv"
gf "Write 로 보고서 작성은 통과"      PASS Write "$PLANT/report.md"
gf "Read 도구는 검사 안 함"           PASS Read  "$PLANT/config/thresholds.csv"

out="$(echo 'not json' | python3 "$GUARD")"
[ -z "$out" ] && ok "깨진 입력은 통과 (fail-open)" || bad "깨진 입력" "PASS" "DENY"

# 막을 때 이유를 준다 — 이유 없이 막으면 LLM 은 같은 명령을 조금 바꿔 다시 시도한다
out="$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"sf-actuate stop CNC-02 --reason x"}}))' | python3 "$GUARD")"
echo "$out" | grep -q "운영자" && ok "차단 사유에 '누가 실행하는지'가 있다" || bad "사유" "운영자 언급" "$out"

# 범위 밖에서는 아무것도 하지 않는다 (실무 저장소를 막지 않기 위해)
cd "$TMP"
g "마커 없으면 stop 도 통과"          PASS "sf-actuate stop CNC-02 --reason x"
g "마커 없으면 rm signals 도 통과"    PASS "rm -rf signals"
SF_HARNESS_GUARD=1 g "환경변수로 켜면 다시 막힌다" DENY "sf-actuate stop CNC-02 --reason x"
# cwd 는 밖이지만 편집 대상 파일이 플랜트 안이면 막는다
gf "cwd 밖이어도 플랜트 파일 편집은 막는다" DENY Write "$PLANT/config/thresholds.csv"
# hook 입력의 cwd 필드도 본다 (Claude Code 가 넘겨준다)
out="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"rm signals/x.csv"}}))' "$PLANT" | python3 "$GUARD")"
[ -n "$out" ] && ok "입력 JSON 의 cwd 로 범위를 판단한다" || bad "cwd 필드" "DENY" "PASS"

# ─── 결과 ─────────────────────────────────────────────────────
echo
if [ "$FAIL" -eq 0 ]; then
  printf "\033[32m%d개 통과, 실패 없음\033[0m\n" "$PASS"; exit 0
else
  printf "\033[31m%d개 통과, %d개 실패\033[0m\n" "$PASS" "$FAIL"; exit 1
fi
