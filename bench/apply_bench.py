#!/usr/bin/env python3
"""
Patch slide 21 of the Tech Day deck with measured benchmark numbers.

Reads one or more results JSON files (the same schema bench.py and the iOS app emit) and
rewrites the <tbody> of the Benchmarks slide, dropping the PLACEHOLDER banner.

  python apply_bench.py --deck "../../deck/Tech Day Deck.html" \
      --device results.json \
      --device iphone-results.json \
      --cloud cloud_results.json

Each --device file contributes its rows (one per model). --cloud adds the cloud row.
A .bak copy of the deck is written before patching. Re-run any time new numbers arrive.
"""
from __future__ import annotations

import argparse
import json
import re
import sys


def model_name(model_id: str) -> str:
    leaf = model_id.split("/")[-1]
    m = re.search(r"(\d+\.?\d*\s*B)", leaf, re.I)
    size = m.group(1).replace(" ", "") if m else leaf
    fam = "Qwen" if "qwen" in leaf.lower() else ("SmolLM" if "smol" in leaf.lower() else leaf.split("-")[0])
    return f"{fam} {size}" if m else leaf


def short_device(label: str) -> str:
    # "Apple M2 Pro · Mac14,10 · 16 GB" -> "Apple M2 Pro"; "iPhone 14 Pro Max" stays.
    return label.split("·")[0].strip()


def fmt_ttft(seconds: float) -> str:
    if seconds is None:
        return "—"
    return f"~{seconds * 1000:.0f} ms" if seconds < 1 else f"~{seconds:.1f} s"


def fmt_tps(tps: float) -> str:
    return "—" if tps is None else f"~{tps:.0f} tok/s"


def rows_from_device(payload: dict) -> list[dict]:
    dev = short_device(payload.get("device", "device"))
    prelim = payload.get("preliminary", False)
    out = []
    for r in payload.get("results", []):
        if "error" in r:
            continue
        out.append({
            "setup": f"{model_name(r['model'])} · 4-bit · {dev}" + (" *" if prelim else ""),
            "ttft": fmt_ttft(r.get("ttft_p50_s")),
            "tput": fmt_tps(r.get("decode_tps_p50")),
            "offline": "yes",
            "p99": "≈ p50 — no network tail",
            "hl": True,
        })
    return out


def row_from_cloud(payload: dict) -> dict:
    p50 = payload.get("ttft_p50_s")
    p99 = payload.get("ttft_p99_s")
    if p50 and p99 and p99 > p50 * 1.15:
        ttft = f"{p50:.1f}–{p99:.1f} s"
    else:
        ttft = fmt_ttft(p50)
    name = payload.get("model", "small model class")
    return {
        "setup": f"Cloud API · {name}",
        "ttft": ttft,
        "tput": fmt_tps(payload.get("decode_tps_p50")),
        "offline": "no",
        "p99": "network-bound, long tail",
        "hl": False,
    }


def render_tbody(rows: list[dict]) -> str:
    lines = ["      <tbody>"]
    for r in rows:
        cls = ' class="hl"' if r["hl"] else ""
        lines.append("        <tr>")
        lines.append(f'          <td{cls}>{r["setup"]}</td>')
        lines.append(f'          <td>{r["ttft"]}</td>')
        lines.append(f'          <td>{r["tput"]}</td>')
        lines.append(f'          <td>{r["offline"]}</td>')
        lines.append(f'          <td>{r["p99"]}</td>')
        lines.append("        </tr>")
    lines.append("      </tbody>")
    return "\n".join(lines)


def patch(deck_path: str, rows: list[dict], any_prelim: bool, note: str | None) -> None:
    with open(deck_path, encoding="utf-8") as f:
        html = f.read()

    # Isolate the Benchmarks slide section.
    m = re.search(r'(<section[^>]*data-label="Benchmarks".*?</section>)', html, re.S)
    if not m:
        sys.exit("Could not find the Benchmarks slide (data-label=\"Benchmarks\").")
    section = m.group(1)
    new_section = section

    # Replace the first <tbody>…</tbody> with the measured rows.
    if not re.search(r"<tbody>.*?</tbody>", new_section, re.S):
        sys.exit("No <tbody> found in the Benchmarks slide.")
    new_section = re.sub(r"<tbody>.*?</tbody>", render_tbody(rows).strip(), new_section, count=1, flags=re.S)

    # Replace the PLACEHOLDER ph-tag with a dated/measured note (or remove it).
    footnote = note or "Measured values."
    if any_prelim and note is None:
        footnote += "  * iPhone = preliminary; finalize on-device before 07.07."
    if re.search(r'<p class="ph-tag[^>]*>.*?</p>', new_section, re.S):
        new_section = re.sub(
            r'<p class="ph-tag([^"]*)"([^>]*)>.*?</p>',
            f'<p class="ph-tag\\1"\\2>{footnote}</p>',
            new_section, count=1, flags=re.S)

    html = html.replace(section, new_section)
    with open(deck_path + ".bak", "w", encoding="utf-8") as f:
        f.write(m.string)  # original full html backup
    with open(deck_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Patched {deck_path} with {len(rows)} rows (backup: {deck_path}.bak)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--deck", required=True)
    ap.add_argument("--device", action="append", default=[], help="on-device results JSON (repeatable)")
    ap.add_argument("--cloud", help="cloud_results.json")
    ap.add_argument("--note", help="override the footnote under the table")
    args = ap.parse_args()

    rows: list[dict] = []
    any_prelim = False
    for path in args.device:
        with open(path) as f:
            payload = json.load(f)
        any_prelim = any_prelim or payload.get("preliminary", False)
        rows.extend(rows_from_device(payload))
    if args.cloud:
        with open(args.cloud) as f:
            rows.append(row_from_cloud(json.load(f)))

    if not rows:
        sys.exit("No rows — pass at least one --device <results.json>.")
    patch(args.deck, rows, any_prelim, args.note)
    return 0


if __name__ == "__main__":
    sys.exit(main())
