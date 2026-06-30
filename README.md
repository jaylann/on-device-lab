# On-Device Lab

A tiny SwiftUI app that runs an **open-weight LLM entirely on your Mac or iPhone** via
[MLX](https://github.com/ml-explore/mlx-swift) — no API key, no server, works in airplane mode.
Built for the **Porsche Tech Day** code-along: load a model, stream tokens, and measure the
two numbers that decide on-device UX — **TTFT** (time to first token) and **throughput** (tokens/sec).

> Companion to the talk *"Not Every On-Device AI Is Apple Intelligence"* — open-weight models in
> production on iPhone (NeatPass), and what they mean for the car.

---

## Requirements
- **Apple Silicon Mac** (M1 or newer — any of them, including Air)
- **Xcode 16+** (developed against Xcode 26) and ~4 GB free disk
- For the iPhone: an iPhone 12 or newer, iOS 17+

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The committed
`.xcodeproj` works as-is; only run `xcodegen generate` if you change `project.yml`.

## Quick start
```bash
git clone https://github.com/jaylann/on-device-lab
cd on-device-lab
open OnDeviceLab.xcodeproj      # then ⌘R
```
Pick **Qwen3 0.6B · 4-bit**, press **Load** (first load downloads ~0.3 GB, or reads the local
share — see below), type a prompt, press **Send**. Tokens stream. That's the whole on-device stack.

---

## The exercise — three milestones

### M1 · Run it
Load Qwen3 0.6B, prompt it, watch the stream. Done above.

### M2 · Measure it  ← the actual exercise
Open **`OnDeviceLab/Benchmark.swift`** and find `measure(...)`. The loop, warmup, percentiles and
JSON export are written for you. **Two lines are not** — marked `TODO 1` and `TODO 2`:
1. **TTFT** — the first time a chunk arrives, stamp `firstTokenTime = Date()` (once).
2. **Throughput** — increment `tokenCount` once per chunk.

Until you fill them, the **Benchmark** sheet reports `0 tok/s` — that's the point. Fill them, hit
**Run suite**, and shout your numbers. We collect everyone's across M1 → M4 chips.

> Stuck or just want numbers fast? Switch the scheme to **OnDeviceLab (Solution)** — it compiles a
> reference implementation (`#if SOLUTION`) so you can check your answer.

Export results as JSON from the sheet (AirDrop from iPhone → Mac). The JSON matches the Python
harness schema, so `bench/apply_bench.py` can drop your numbers straight onto the slide.

### M3 · Stress it
Switch to **Qwen3 4B** and feel what several billion more params cost. Pick **Long-context prompt**
from the **Sample prompts** menu (top-right) and watch the window fill. **Turn off Wi-Fi**
mid-generation — generation keeps streaming, fully offline. That's the entire thesis of the talk.

Finished early? Make the model return strict JSON for a messy ticket, then try to break it.

---

## Benchmark harness (reproducible, headless) — `bench/`
A Python [`mlx-lm`](https://github.com/ml-explore/mlx-lm) harness that measures the same two numbers
from the command line. Use it on your Mac, or over SSH on a cloud Apple-Silicon Mac.
```bash
cd bench
./run.sh                                  # on-device: results.json + a Markdown table
RUNS=8 MAX_TOKENS=200 ./run.sh            # tune it
# add a measured cloud-API comparison row (your network, your key):
CLOUD_API_KEY=sk-... CLOUD_MODEL=gpt-4o-mini ./run.sh
```
> **Apple Silicon only.** MLX runs on the Mac GPU via Metal — a generic Linux VM can't run it; an
> "SSH box" must be an M-series Mac (e.g. a cloud Mac mini).

See [`bench/README.md`](bench/README.md) for the cloud-probe backends and `apply_bench.py`.

---

## Models & the venue Wi-Fi
Three 4-bit models, all from `mlx-community`:

| Model | Class | Size |
|---|---|---|
| `Qwen3-0.6B-4bit` | extraction | ~0.3 GB |
| `Qwen3-1.7B-4bit` | robust (the model NeatPass ships) | ~1 GB |
| `Qwen3-4B-4bit` | stress (M3) | ~2.3 GB |

By default the app downloads from Hugging Face on first use. To avoid 30 simultaneous downloads at
the venue, pre-stage them and use the local share:
```bash
./fetch-models.sh                 # stages ./models
# copy ./models to each Mac's ~/Documents/models/  → the app loads them offline
```

---

## How it works
- **MLX / mlx-swift** drives the Mac/phone GPU through Metal. `MLXLLM` + `MLXLMCommon`
  (from [`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm), pinned to 2.31.3) provide
  model loading, the tokenizer, and streaming generation.
- `ModelCatalog` loads a `ModelContainer` (HF id or a local directory).
- `LLMEngine` streams a chat reply (`ChatSession.streamResponse`).
- `Benchmark` wraps the same stream to time it — the teaching core.

## License
MIT — see [LICENSE](LICENSE). Model weights are under their own licenses (Qwen3, Apache-2.0).
Built by [Justin Lanfermann](https://lanfermann.dev) · [neatpass.app](https://neatpass.app).
