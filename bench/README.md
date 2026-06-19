# bench/ — reproducible on-device benchmark

Measures **TTFT** and **decode throughput** for small open-weight models on Apple Silicon via MLX,
and (optionally) the same numbers against a real cloud API for an honest comparison.

> **Apple Silicon only.** MLX uses the Mac GPU via Metal. A generic Linux VM cannot run this — an
> "SSH machine" must be an M-series Mac (cloud Mac mini, EC2 Mac, etc.).

## Run
```bash
./run.sh                         # creates .venv on first run, then benchmarks → results.json + table
RUNS=8 MAX_TOKENS=200 ./run.sh
python bench.py --models mlx-community/Qwen2.5-0.5B-Instruct-4bit --runs 5   # manual
```
`results.json` carries the device label, per-model TTFT p50/p99, decode tok/s, and peak RAM.

## Cloud comparison row
Measured live, against whatever small model you choose, from your own network (so it's fair):
```bash
# OpenAI-compatible (OpenAI, Groq, Together, OpenRouter, Fireworks, vLLM, …)
export CLOUD_API_KEY=sk-...
python cloud_probe.py --backend openai --base-url https://api.openai.com/v1 --model gpt-4o-mini --runs 5
python cloud_probe.py --backend openai --base-url https://openrouter.ai/api/v1 --model qwen/qwen-2.5-7b-instruct

# Anthropic native
export ANTHROPIC_API_KEY=sk-ant-...
python cloud_probe.py --backend anthropic --model claude-haiku-4-5 --runs 5
```
Writes `cloud_results.json`. `run.sh` calls this automatically when `CLOUD_API_KEY` + `CLOUD_MODEL` are set.

## Put the numbers on the slide
```bash
python apply_bench.py --deck "../../deck/Tech Day Deck.html" \
    --device results.json \
    --device iphone-results.json \    # exported from the iOS app (AirDrop), optional
    --cloud cloud_results.json        # optional
```
Rewrites the Benchmarks slide's table and drops the PLACEHOLDER banner. A `.bak` is written first.
The iOS app exports the identical JSON schema, so phone and Mac runs feed the same command.

## Files
- `bench.py` — on-device harness (warmup, N runs, p50/p99, JSON + Markdown).
- `cloud_probe.py` — streaming TTFT/throughput probe (OpenAI-compatible + Anthropic).
- `apply_bench.py` — patches slide 21 of the deck from result JSON files.
- `run.sh` — venv bootstrap + on-device (+ optional cloud) in one command.
