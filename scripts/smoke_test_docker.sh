#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

bash "$ROOT_DIR/scripts/bench_docker.sh" --lines 4.0 --results-dir "$TMP_DIR/results" --smoke
python3 - "$TMP_DIR/results" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
files = list(root.glob("ruby*/profile-light/*/fork1/result.json"))
assert len(files) == 10, f"expected 10 results, found {len(files)}"
for path in files:
    data = json.loads(path.read_text())
    assert data["results"]["ops"] > 0, path
    latency = data["results"]["latency"]
    assert latency["p50_us"] <= latency["p95_us"] <= latency["p99_us"] <= latency["max_us"], path
assert (root / "dashboard.html").stat().st_size > 5000
print("Ruby Docker smoke test OK")
PY
