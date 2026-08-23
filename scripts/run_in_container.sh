#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${WORKDIR:-/work}"
OUT_DIR="${OUT_DIR:-/out}"
SCENARIOS="appsim,micro_json_parse,micro_json_generate,micro_sha256,micro_base64,micro_regex,micro_sort_int,micro_hash_churn,micro_marshal,micro_zlib"
PROFILES="light,heavy"
WARMUP="20s"
MEASURE="10m"
FORKS=5
MICRO_WARMUP="5s"
MICRO_MEASURE="10s"
MICRO_FORKS=5
THREADS=10
COOLDOWN=5
MICRO_COOLDOWN=2
SMOKE=false

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --scenario|--scenarios) SCENARIOS="$2"; shift 2 ;;
    --profiles) PROFILES="$2"; shift 2 ;;
    --warmup) WARMUP="$2"; shift 2 ;;
    --measure) MEASURE="$2"; shift 2 ;;
    --forks) FORKS="$2"; shift 2 ;;
    --micro-warmup) MICRO_WARMUP="$2"; shift 2 ;;
    --micro-measure) MICRO_MEASURE="$2"; shift 2 ;;
    --micro-forks) MICRO_FORKS="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --smoke) SMOKE=true; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "$SMOKE" == true ]]; then
  PROFILES=light
  WARMUP=0s
  MEASURE=250ms
  FORKS=1
  MICRO_WARMUP=0s
  MICRO_MEASURE=250ms
  MICRO_FORKS=1
  COOLDOWN=0
  MICRO_COOLDOWN=0
fi

mkdir -p "$OUT_DIR"
cd "$WORKDIR"
ruby --version > "$OUT_DIR/ruby_version.txt"
ruby -e 'puts RUBY_DESCRIPTION' > "$OUT_DIR/ruby_description.txt"
log "preflight: checking workloads"
ruby -Ilib bin/bench --self-test > "$OUT_DIR/self_test.txt"

IFS=',' read -r -a profiles <<< "$PROFILES"
IFS=',' read -r -a scenarios <<< "$SCENARIOS"
total=0
for profile in "${profiles[@]}"; do
  for scenario in "${scenarios[@]}"; do
    if [[ "$scenario" == micro_* ]]; then total=$((total + MICRO_FORKS)); else total=$((total + FORKS)); fi
  done
done

completed=0
log "suite: version=${BENCH_VERSION_INDEX:-?}/${BENCH_VERSION_TOTAL:-?} profiles=${#profiles[@]} scenarios=${#scenarios[@]} forks=$total"
for profile in "${profiles[@]}"; do
  for scenario in "${scenarios[@]}"; do
    repeats="$FORKS"
    warmup="$WARMUP"
    measure="$MEASURE"
    cooldown="$COOLDOWN"
    if [[ "$scenario" == micro_* ]]; then
      repeats="$MICRO_FORKS"
      warmup="$MICRO_WARMUP"
      measure="$MICRO_MEASURE"
      cooldown="$MICRO_COOLDOWN"
    fi
    for ((fork=1; fork<=repeats; fork++)); do
      directory="$OUT_DIR/profile-$profile/$scenario/fork$fork"
      mkdir -p "$directory"
      log "starting: profile=$profile scenario=$scenario fork=$fork/$repeats overall=$((completed + 1))/$total"
      echo 'ts_s,rss_kb,pcpu' > "$directory/ps.csv"
      ruby -Ilib bin/bench --scenario "$scenario" --profile "$profile" --threads "$THREADS" \
        --warmup "$warmup" --measure "$measure" --out "$directory/result.json" \
        > /dev/null 2> "$directory/stderr.txt" &
      pid=$!
      start="$(date +%s)"
      while kill -0 "$pid" 2>/dev/null; do
        row="$(ps -o rss= -o pcpu= -p "$pid" 2>/dev/null || true)"
        if [[ -n "$row" ]]; then
          read -r rss pcpu <<< "$row"
          echo "$(date +%s),$rss,$pcpu" >> "$directory/ps.csv"
        fi
        sleep 1
      done
      wait "$pid"
      completed=$((completed + 1))
      percent=$((completed * 100 / total))
      elapsed=$(($(date +%s) - start))
      log "completed: [$completed/$total ${percent}%] profile=$profile scenario=$scenario elapsed=${elapsed}s"
      sleep "$cooldown"
    done
  done
done
log "suite complete: $completed/$total forks"
