#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINES="4.0,3.4,3.3,3.2,3.1,3.0,2.7"
KINDS="latest"
RESULTS_DIR=""
PLATFORM=""
PULL=false
LIST=false
INNER_ARGS=()
DOCKER_ARGS=()

usage() {
  cat <<'EOF'
Usage: scripts/bench_docker.sh [options]
  --lines 4.0,3.4,...     Ruby release lines
  --kinds latest          latest or first,latest
  --pull                  pull images before running
  --platform PLATFORM     optional Docker platform
  --docker-arg ARG        extra docker run argument
  --results-dir DIR       output directory
  --list-images           resolve versions without running
All workload options are passed to the container runner.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lines) LINES="$2"; shift 2 ;;
    --kinds) KINDS="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --docker-arg) DOCKER_ARGS+=("$2"); shift 2 ;;
    --pull) PULL=true; shift ;;
    --list-images) LIST=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --smoke) INNER_ARGS+=("$1"); shift ;;
    *)
      [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 2; }
      INNER_ARGS+=("$1" "$2")
      shift 2
      ;;
  esac
done

versions="$(python3 "$ROOT_DIR/scripts/resolve_ruby_versions.py" --lines "$LINES" --kinds "$KINDS")"
if [[ "$LIST" == true ]]; then
  printf '%s\n' "$versions"
  exit 0
fi
if [[ -z "$RESULTS_DIR" ]]; then
  RESULTS_DIR="$ROOT_DIR/results/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$RESULTS_DIR"
docker_base=(docker run --rm)
[[ -n "$PLATFORM" ]] && docker_base+=(--platform "$PLATFORM")
[[ ${#DOCKER_ARGS[@]} -gt 0 ]] && docker_base+=("${DOCKER_ARGS[@]}")
total="$(printf '%s\n' "$versions" | wc -l | tr -d ' ')"
index=0

while IFS=$'\t' read -r line kind version image; do
  index=$((index + 1))
  [[ "$PULL" == true ]] && docker pull "$image"
  label="ruby$line-$kind-$version"
  output="$RESULTS_DIR/$label"
  mkdir -p "$output"
  printf '%s\n' "$image" > "$output/IMAGE.txt"
  printf '== runtime %s/%s: %s (%s) ==\n' "$index" "$total" "$label" "$image" >&2
  command=("${docker_base[@]}" -v "$ROOT_DIR:/work:ro" -v "$output:/out" -w /work
    -e BENCH_VERSION_INDEX="$index" -e BENCH_VERSION_TOTAL="$total"
    "$image" bash /work/scripts/run_in_container.sh --out-dir /out)
  [[ ${#INNER_ARGS[@]} -gt 0 ]] && command+=("${INNER_ARGS[@]}")
  "${command[@]}"
done <<< "$versions"

python3 "$ROOT_DIR/scripts/aggregate.py" "$RESULTS_DIR"
printf 'Report: %s/dashboard.html\n' "$RESULTS_DIR" >&2
