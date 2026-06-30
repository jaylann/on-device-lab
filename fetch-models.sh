#!/usr/bin/env bash
# Pre-stage the lab's models into ./models so 30 people don't hammer the venue Wi-Fi.
#
# After running, copy ./models to a USB stick or local web share. On each Mac, drop the
# model folders into ~/Documents/models/ — the app loads them from there with no network
# (see ModelCatalog.localDirectory). If the folder is absent, the app downloads from
# Hugging Face on first use instead.
set -euo pipefail
cd "$(dirname "$0")"

MODELS=(
  "mlx-community/Qwen3-0.6B-4bit"
  "mlx-community/Qwen3-1.7B-4bit"
  "mlx-community/Qwen3-4B-4bit"
)
PY="${PYTHON:-python3}"

"$PY" - <<'PY'
import importlib.util, subprocess, sys
if importlib.util.find_spec("huggingface_hub") is None:
    print("installing huggingface_hub…")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "huggingface_hub"])
PY

for repo in "${MODELS[@]}"; do
  leaf="${repo##*/}"
  echo "→ $repo  →  models/$leaf"
  "$PY" - "$repo" "models/$leaf" <<'PY'
import sys
from huggingface_hub import snapshot_download
repo, dest = sys.argv[1], sys.argv[2]
snapshot_download(
    repo_id=repo, local_dir=dest,
    allow_patterns=["*.safetensors", "*.json", "*.txt", "*.model", "tokenizer*", "*.tiktoken"],
)
print("  staged", dest)
PY
done

echo
echo "Done. ./models contains the weights."
echo "Venue: copy ./models to a share; on each Mac put the folders in ~/Documents/models/"
