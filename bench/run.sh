#!/usr/bin/env bash
# One command: on-device benchmark (+ optional cloud probe) → results.json + table.
#
# Apple Silicon Mac only (MLX needs Metal). Portable over SSH to a cloud M-series Mac.
#
#   ./run.sh                                  # on-device only
#   CLOUD_API_KEY=sk-... CLOUD_MODEL=gpt-4o-mini ./run.sh   # + cloud row
#
set -euo pipefail
cd "$(dirname "$0")"

PYTHON="${PYTHON:-python3}"
RUNS="${RUNS:-5}"
MAX_TOKENS="${MAX_TOKENS:-200}"

if [ ! -d .venv ]; then
  echo "→ creating venv + installing deps (first run only)…"
  "$PYTHON" -m venv .venv
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q -r requirements.txt
fi
PY=.venv/bin/python

echo "→ on-device benchmark"
$PY bench.py --runs "$RUNS" --max-tokens "$MAX_TOKENS" --out results.json

if [ -n "${CLOUD_API_KEY:-}${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}" ] && [ -n "${CLOUD_MODEL:-}" ]; then
  echo "→ cloud probe (${CLOUD_BACKEND:-openai} · ${CLOUD_MODEL})"
  $PY cloud_probe.py \
    --backend "${CLOUD_BACKEND:-openai}" \
    --base-url "${CLOUD_BASE_URL:-https://api.openai.com/v1}" \
    --model "$CLOUD_MODEL" --runs "$RUNS" --max-tokens "$MAX_TOKENS" \
    --out cloud_results.json
else
  echo "→ skipping cloud probe (set CLOUD_API_KEY + CLOUD_MODEL to enable)"
fi

echo "→ done. results.json"$([ -f cloud_results.json ] && echo " + cloud_results.json")
