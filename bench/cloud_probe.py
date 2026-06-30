#!/usr/bin/env python3
"""
Cloud-API latency probe — the honest other side of the benchmark.

Measures, against a real hosted small model, the same two numbers as bench.py:
  * TTFT  — time to the first streamed content byte (what the network actually costs you).
  * tok/s — completion throughput once the stream is flowing.

Two backends:
  * openai   — any OpenAI-compatible /chat/completions endpoint with stream=true
               (OpenAI, Groq, Together, OpenRouter, Fireworks, vLLM, …).
  * anthropic — the native Anthropic Messages streaming API.

Nothing is hardcoded: pass --base-url / --model and an API key via env. Run it on the
same network you'd demo from, so the comparison is fair.

Examples:
    export CLOUD_API_KEY=sk-...
    python cloud_probe.py --backend openai \
        --base-url https://api.openai.com/v1 --model gpt-4o-mini --runs 5
    python cloud_probe.py --backend openai \
        --base-url https://openrouter.ai/api/v1 --model qwen/qwen-2.5-7b-instruct
    python cloud_probe.py --backend anthropic --model claude-haiku-4-5
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time

import httpx

DEFAULT_PROMPT = (
    "Extract type, title, venue, city, date and seat as JSON from this ticket text: "
    "Die Fantastischen Vier - Live 2026, Olympiahalle Muenchen, 12.09.2026, Block C Reihe 14 Platz 7. "
    "Return only JSON."
)


def probe_openai(client, base_url, model, key, prompt, max_tokens):
    url = base_url.rstrip("/") + "/chat/completions"
    body = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        # Newer OpenAI models (gpt-5+) require max_completion_tokens; it's also accepted by gpt-4o.
        "max_completion_tokens": max_tokens,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    start = time.perf_counter()
    first_t = None
    n_chunks = 0
    usage_completion = 0
    with client.stream("POST", url, json=body, headers=headers) as r:
        if r.status_code >= 400:
            raise RuntimeError(f"{r.status_code}: {r.read().decode('utf-8', 'replace')[:400]}")
        for line in r.iter_lines():
            if not line or not line.startswith("data:"):
                continue
            data = line[len("data:"):].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except json.JSONDecodeError:
                continue
            if obj.get("usage"):
                usage_completion = obj["usage"].get("completion_tokens", 0) or usage_completion
            choices = obj.get("choices") or []
            delta = (choices[0].get("delta") if choices else {}) or {}
            if delta.get("content"):
                if first_t is None:
                    first_t = time.perf_counter()
                n_chunks += 1
    end = time.perf_counter()
    return _finish(start, first_t, end, n_chunks, usage_completion)


def probe_anthropic(client, base_url, model, key, prompt, max_tokens):
    url = (base_url or "https://api.anthropic.com").rstrip("/") + "/v1/messages"
    body = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
        "stream": True,
    }
    headers = {
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
    }
    start = time.perf_counter()
    first_t = None
    n_chunks = 0
    out_tokens = 0
    with client.stream("POST", url, json=body, headers=headers) as r:
        if r.status_code >= 400:
            raise RuntimeError(f"{r.status_code}: {r.read().decode('utf-8', 'replace')[:400]}")
        for line in r.iter_lines():
            if not line or not line.startswith("data:"):
                continue
            try:
                obj = json.loads(line[len("data:"):].strip())
            except json.JSONDecodeError:
                continue
            t = obj.get("type")
            if t == "content_block_delta" and obj.get("delta", {}).get("text"):
                if first_t is None:
                    first_t = time.perf_counter()
                n_chunks += 1
            elif t == "message_delta":
                out_tokens = obj.get("usage", {}).get("output_tokens", 0) or out_tokens
    end = time.perf_counter()
    return _finish(start, first_t, end, n_chunks, out_tokens)


def _finish(start, first_t, end, n_chunks, usage_tokens):
    ttft = (first_t - start) if first_t else (end - start)
    decode_time = max(end - first_t, 1e-6) if first_t else (end - start)
    gen = usage_tokens or n_chunks
    return ttft, gen / decode_time if decode_time > 0 else 0.0, gen


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--backend", choices=["openai", "anthropic"], default="openai")
    ap.add_argument("--base-url", default=os.environ.get("CLOUD_BASE_URL", ""))
    ap.add_argument("--model", required=True)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--max-tokens", type=int, default=200)
    ap.add_argument("--prompt", default=DEFAULT_PROMPT)
    ap.add_argument("--out", default="cloud_results.json")
    args = ap.parse_args()
    if not args.base_url:
        args.base_url = "https://api.openai.com/v1" if args.backend == "openai" else "https://api.anthropic.com"

    key = os.environ.get("CLOUD_API_KEY") or os.environ.get("OPENAI_API_KEY") or os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        print("Set CLOUD_API_KEY (or OPENAI_API_KEY / ANTHROPIC_API_KEY).", file=sys.stderr)
        return 2

    probe = probe_openai if args.backend == "openai" else probe_anthropic
    ttfts, tpss, gens = [], [], 0
    print(f"Cloud probe: {args.backend} · {args.model} · runs={args.runs}")
    with httpx.Client(timeout=60.0) as client:
        for i in range(args.runs):
            try:
                ttft, tps, gen = probe(client, args.base_url, args.model, key, args.prompt, args.max_tokens)
                ttfts.append(ttft)
                tpss.append(tps)
                gens = gen or gens
                print(f"  run {i+1}/{args.runs}: TTFT {ttft*1000:6.0f} ms · {tps:5.1f} tok/s", flush=True)
            except Exception as e:
                print(f"  run {i+1} FAILED: {e}", flush=True)

    def p(vals, q):
        if not vals:
            return None
        vs = sorted(vals)
        return vs[min(len(vs) - 1, max(0, round(q * (len(vs) - 1))))]

    payload = {
        "kind": "cloud",
        "backend": args.backend,
        "model": args.model,
        "base_url": args.base_url,
        "ttft_p50_s": round(statistics.median(ttfts), 4) if ttfts else None,
        "ttft_p99_s": round(p(ttfts, 0.99), 4) if ttfts else None,
        "decode_tps_p50": round(statistics.median(tpss), 1) if tpss else None,
        "gen_tokens": gens,
        "runs": len(ttfts),
    }
    with open(args.out, "w") as f:
        json.dump(payload, f, indent=2)
    print(f"\nWrote {args.out}: TTFT p50 {payload['ttft_p50_s']}s (p99 {payload['ttft_p99_s']}s), "
          f"{payload['decode_tps_p50']} tok/s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
