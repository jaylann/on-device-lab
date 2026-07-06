#!/usr/bin/env python3
"""
On-device LLM benchmark — the two numbers that matter on a phone.

Measures, for each model, on Apple Silicon via MLX:
  * TTFT  — time to first token (prompt-eval + first decode), the latency a user feels.
  * tok/s — sustained decode throughput once tokens start flowing.

It runs a warmup, then N timed runs, and reports p50 / p99 so you can see the tail.
Output: results.json (machine-readable) + a Markdown table you can paste into a slide.

Apple Silicon only — MLX runs on the Mac GPU via Metal. A generic Linux VM cannot run this.

Usage:
    pip install -r requirements.txt
    python bench.py                       # default models, 5 runs
    python bench.py --runs 8 --max-tokens 200
    python bench.py --models mlx-community/Qwen3-0.6B-4bit
"""
from __future__ import annotations

import argparse
import json
import platform
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass, asdict, field

# Models matching the talk: Qwen3 0.6B (extraction class) and 1.7B (the model NeatPass ships).
DEFAULT_MODELS = [
    "mlx-community/Qwen3-0.6B-4bit",
    "mlx-community/Qwen3-1.7B-4bit",
]

# A realistic, on-theme long-form generation prompt: an in-car assistant answering a passenger.
# Prose output (≥500 tok) gives a stable steady-state decode window and keeps the AFM chars/4
# estimate honest (JSON output is token-dense and makes chars/4 undercount).
DEFAULT_PROMPT = """You are an in-car voice assistant. A passenger asks how regenerative braking \
works and how it affects the car's range in city versus highway driving. Answer in clear, friendly \
prose of at least 500 words. Cover the physics of turning motion back into charge, what the driver \
feels through the pedal, when it helps most, when it barely helps, and its limits in cold weather \
and at high speed."""


def mac_device_label() -> str:
    """Friendly hardware label, e.g. 'Apple M3 Pro · MacBookPro18,3 · 36 GB'."""
    chip = model_id = mem = ""
    try:
        out = subprocess.run(
            ["system_profiler", "SPHardwareDataType"],
            capture_output=True, text=True, timeout=30,
        ).stdout
        for line in out.splitlines():
            s = line.strip()
            if s.startswith("Chip:"):
                chip = s.split(":", 1)[1].strip()
            elif s.startswith("Model Identifier:"):
                model_id = s.split(":", 1)[1].strip()
            elif s.startswith("Memory:"):
                mem = s.split(":", 1)[1].strip()
    except Exception:
        pass
    if not chip:
        try:
            model_id = model_id or subprocess.run(
                ["sysctl", "-n", "hw.model"], capture_output=True, text=True
            ).stdout.strip()
        except Exception:
            pass
    parts = [p for p in (chip, model_id, mem) if p]
    return " · ".join(parts) or platform.platform()


@dataclass
class RunStats:
    ttft_s: list[float] = field(default_factory=list)
    decode_tps: list[float] = field(default_factory=list)
    prompt_tokens: int = 0
    gen_tokens: int = 0
    peak_mem_gb: float = 0.0

    def summary(self) -> dict:
        def p(vals, q):
            if not vals:
                return None
            vs = sorted(vals)
            k = min(len(vs) - 1, max(0, round(q * (len(vs) - 1))))
            return vs[k]
        return {
            "ttft_p50_s": round(statistics.median(self.ttft_s), 4) if self.ttft_s else None,
            "ttft_p99_s": round(p(self.ttft_s, 0.99), 4) if self.ttft_s else None,
            "decode_tps_p50": round(statistics.median(self.decode_tps), 1) if self.decode_tps else None,
            "decode_tps_p99": round(p(self.decode_tps, 0.99), 1) if self.decode_tps else None,
            "prompt_tokens": self.prompt_tokens,
            "gen_tokens": self.gen_tokens,
            "peak_mem_gb": round(self.peak_mem_gb, 2),
            "runs": len(self.ttft_s),
        }


def build_prompt(tokenizer, raw: str) -> str:
    """Wrap the raw prompt in the model's chat template if it has one.

    enable_thinking=False keeps Qwen3 in non-thinking mode (the way NeatPass runs extraction);
    it's an extra template kwarg that models without it simply ignore.
    """
    msgs = [{"role": "user", "content": raw}]
    try:
        return tokenizer.apply_chat_template(
            msgs, add_generation_prompt=True, tokenize=False, enable_thinking=False)
    except Exception:
        try:
            return tokenizer.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False)
        except Exception:
            return raw


def _peak_mem_gb() -> float:
    """Best-effort GPU peak memory in GB across mlx versions (0.0 if unavailable)."""
    try:
        import mlx.core as mx
        for attr in ("get_peak_memory", "metal"):
            obj = getattr(mx, attr, None)
            if attr == "get_peak_memory" and obj:
                return obj() / 1e9
            if attr == "metal" and obj and hasattr(obj, "get_peak_memory"):
                return obj.get_peak_memory() / 1e9
    except Exception:
        pass
    return 0.0


def _reset_peak_mem() -> None:
    try:
        import mlx.core as mx
        for attr in ("reset_peak_memory", "metal"):
            obj = getattr(mx, attr, None)
            if attr == "reset_peak_memory" and obj:
                obj(); return
            if attr == "metal" and obj and hasattr(obj, "reset_peak_memory"):
                obj.reset_peak_memory(); return
    except Exception:
        pass


def one_run(model, tokenizer, prompt: str, max_tokens: int, stream_generate) -> tuple[float, float, int, int, float]:
    """Return (ttft_s, decode_tps, prompt_tokens, gen_tokens, peak_mem_gb) for a single generation."""
    _reset_peak_mem()
    start = time.perf_counter()
    first_t = None
    gen_tokens = 0
    prompt_tokens = 0
    peak_mem_gb = 0.0
    last_resp = None
    for resp in stream_generate(model, tokenizer, prompt, max_tokens=max_tokens):
        if first_t is None:
            first_t = time.perf_counter()
        gen_tokens += 1
        last_resp = resp
    end = time.perf_counter()
    ttft = (first_t - start) if first_t else (end - start)
    decode_time = max(end - first_t, 1e-6) if first_t else (end - start)
    # mlx-lm exposes richer counters on the final response — prefer them when present.
    if last_resp is not None:
        prompt_tokens = getattr(last_resp, "prompt_tokens", 0) or 0
        gen_tokens = getattr(last_resp, "generation_tokens", gen_tokens) or gen_tokens
    peak_mem_gb = _peak_mem_gb()
    decode_tps = gen_tokens / decode_time if decode_time > 0 else 0.0
    return ttft, decode_tps, prompt_tokens, gen_tokens, peak_mem_gb


def bench_model(model_id: str, prompt_raw: str, runs: int, warmup: int, max_tokens: int) -> dict:
    from mlx_lm import load, stream_generate  # imported here so --help works without mlx

    t0 = time.perf_counter()
    model, tokenizer = load(model_id)
    load_s = time.perf_counter() - t0
    prompt = build_prompt(tokenizer, prompt_raw)

    for _ in range(warmup):
        one_run(model, tokenizer, prompt, max_tokens, stream_generate)

    stats = RunStats()
    for i in range(runs):
        ttft, tps, ptok, gtok, mem = one_run(model, tokenizer, prompt, max_tokens, stream_generate)
        stats.ttft_s.append(ttft)
        stats.decode_tps.append(tps)
        stats.prompt_tokens = ptok or stats.prompt_tokens
        stats.gen_tokens = gtok or stats.gen_tokens
        stats.peak_mem_gb = max(stats.peak_mem_gb, mem)
        print(f"    run {i+1}/{runs}: TTFT {ttft*1000:6.0f} ms · {tps:5.1f} tok/s", flush=True)

    out = {"model": model_id, "load_s": round(load_s, 2), **stats.summary()}
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--models", nargs="+", default=DEFAULT_MODELS)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--warmup", type=int, default=1)
    ap.add_argument("--max-tokens", type=int, default=600)
    ap.add_argument("--prompt", default=DEFAULT_PROMPT)
    ap.add_argument("--out", default="results.json")
    args = ap.parse_args()

    device = mac_device_label()
    print(f"Device: {device}")
    print(f"Models: {len(args.models)} · runs={args.runs} warmup={args.warmup} max_tokens={args.max_tokens}\n")

    results = []
    for mid in args.models:
        print(f"[{mid}]", flush=True)
        try:
            results.append(bench_model(mid, args.prompt, args.runs, args.warmup, args.max_tokens))
        except Exception as e:
            print(f"    FAILED: {e}", flush=True)
            results.append({"model": mid, "error": str(e)})
        print()

    payload = {
        "kind": "on-device",
        "device": device,
        "platform": platform.platform(),
        "max_tokens": args.max_tokens,
        "runs": args.runs,
        "results": results,
    }
    with open(args.out, "w") as f:
        json.dump(payload, f, indent=2)
    print(f"Wrote {args.out}")

    # Markdown table — paste-ready.
    print("\n| Model | TTFT p50 | TTFT p99 | tok/s p50 | Peak RAM |")
    print("|---|---|---|---|---|")
    for r in results:
        if "error" in r:
            print(f"| {r['model']} | — | — | — | error |")
            continue
        name = r["model"].split("/")[-1]
        print(f"| {name} | {r['ttft_p50_s']*1000:.0f} ms | {r['ttft_p99_s']*1000:.0f} ms | "
              f"{r['decode_tps_p50']:.0f} | {r['peak_mem_gb']:.1f} GB |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
