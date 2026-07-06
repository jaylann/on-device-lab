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
- **Xcode 26** and ~4 GB free disk. (The open-weight path builds on older Xcode too, but the
  Apple Foundation Model tasks need the `FoundationModels` SDK that ships with Xcode 26.)
- For the iPhone: an iPhone 12 or newer, iOS 17+

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The committed
`.xcodeproj` works as-is; only run `xcodegen generate` if you change `project.yml`. No signing
team is set on purpose — with none, macOS falls back to "Sign to Run Locally" and ⌘R just works.

## Quick start
```bash
git clone https://github.com/jaylann/on-device-lab
cd on-device-lab
open OnDeviceLab.xcodeproj      # then ⌘R
```
Pick **Qwen3 0.6B · 4-bit**, press **Load** (it uses your pre-cached weights, or the local
share — see below), type a prompt, press **Send**. Tokens stream. That's the whole on-device stack.

> **Xcode red on ⌘R?** Signing → target → *Signing & Capabilities* → Team = **None / Sign to Run
> Locally** (macOS needs no team). Mangled your checkout mid-exercise? `git stash` to park your
> edits, or last resort `cd .. && rm -rf on-device-lab && git clone …` to start clean.

---

## The exercise — four milestones

Each milestone maps to a round from the talk's "Gauntlet", and each coding task exists in two
flavours: the **open-weight** way and the **Apple Foundation Model** way — the same job, opposite
philosophies. That contrast is the whole point.

> **Everything is skippable.** Every `TODO` has a reference implementation in
> `OnDeviceLab/Solutions/Solutions.swift`, compiled only by the **`OnDeviceLab (Solution)`**
> scheme (`#if SOLUTION`). Stuck? Switch to that scheme to unblock — it keeps your own edits, and
> the answers aren't sitting inline in the file you're editing (so no accidental spoilers).
>
> **AFM tasks:** you *write* them on any Xcode 26, but they only *run* on macOS 26 + Apple
> Intelligence. The open-weight tasks run on every Apple Silicon Mac.

### M1 · Run it
Load Qwen3 0.6B, prompt it, watch the stream. Done above. No code.

### M2 · Measure it — round 1 (latency)
`OnDeviceLab/Benchmark.swift`, `measure(...)`. Loop, warmup, percentiles, export are written.
**Two lines are not** — `TODO 1` (stamp `firstTokenTime = Date()` on the first chunk) and
`TODO 2` (increment `tokenCount` per chunk). Until then the **Benchmark** sheet reports `0 tok/s`.
Fill them, hit **Run suite**, shout your numbers — we collect them across M1 → M4 chips. (Export
JSON matches the Python harness schema in `bench/`.)

### M3 · Extract it — round 2 (structured output)
`OnDeviceLab/Demos/TicketExtraction.swift`. Pull six fields out of a messy charging receipt.
- **Open-weight** — done for you: the Extract tab runs a **grammar lock**
  (mlx-swift-structured / XGrammar constrains decoding to the six-field schema), so malformed
  JSON is impossible on this side too. *Same guarantee as Apple's, off the shelf.*
- **Apple FM** — `TODO 3b` in `AFMExtractor.extractInvoice`: one `session.respond(to:,
  generating: GenerableInvoice.self)` call. *Generate straight into a type — bad JSON is impossible.*

### M4 · Tool it — round 3 (tool calling)
`OnDeviceLab/Demos/CarTools.swift`. Answer a driver's question by calling car tools.
- **Open-weight** — done for you: a grammar-locked JSON loop (the tool name can only be one of
  the registered ones), every hop rendered in the trace. *Constrained calls, hand-run loop.*
- **Apple FM** — `TODO 4b` in `WeatherTool.call(arguments:)`: implement one `Tool` struct
  (the other two are done for reference). *Typed structs; the runtime runs the call loop.*

### Bonus · Stress it — round 4 (context)
Switch to **Qwen3 4B** and feel what several billion more params cost. Pick **Long-context prompt**
from the **Sample prompts** menu and watch the window fill. **Turn off Wi-Fi** mid-generation —
it keeps streaming, fully offline. That's the entire thesis of the talk. Still going? Race the Arena.

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

See [`bench/README.md`](bench/README.md) for the cloud-probe backends and the AFM harness.

---

## Models & the venue Wi-Fi
Six models, all 4-bit MLX quants:

| Model | Class | Size |
|---|---|---|
| `Qwen3-0.6B-4bit` | extraction | ~0.3 GB |
| `Qwen3-1.7B-4bit` | robust (the model NeatPass ships) | ~1 GB |
| `Qwen3.5-2B-MLX-4bit` | arena / 262k context | ~1.4 GB |
| `Qwen3-4B-4bit` | stress (bonus) | ~2.3 GB |
| `SmolLM3-3B-4bit` | arena | ~1.7 GB |
| `SmolLM2-1.7B-Instruct-MLX-4bit` | arena (community quant) | ~1 GB |

**Before the venue — do this at home.** Open the app once on any internet and **Load** each model
(0.6B, 1.7B, 4B). MLX caches the weights to `~/.cache/huggingface`, so from then on the app runs
fully offline — no venue Wi-Fi, no USB needed. 25 people downloading ~3.6 GB each at 09:00 is the
meltdown we're avoiding; a few minutes at home over breakfast spreads it out.

**Backup only** — for a locked-down / offline machine that can't pre-download (some corp laptops
block Hugging Face): grab pre-staged weights from the on-site local share.
```bash
./fetch-models.sh                 # stages ./models (run once, ahead of time)
# copy ./models to the Mac's ~/Documents/models/  → the app loads them with zero network
```

---

## How it works
- **MLX / mlx-swift** drives the Mac/phone GPU through Metal. `MLXLLM` + `MLXLMCommon`
  (from [`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm), pinned to 2.31.3) provide
  model loading, the tokenizer, and streaming generation.
- `ModelCatalog` loads a `ModelContainer` (HF id or a local directory).
- `LLMEngine` streams a chat reply (`ChatSession.streamResponse`).
- The `#if SOLUTION` teaching TODOs: M2 in `Benchmark.swift` (measure), M3b in
  `TicketExtraction.swift` (AFM extraction), M4b in `CarTools.swift` (AFM weather tool).
  The open-weight extract/tools paths are grammar-locked and fully wired.

> **Presenting?** Run the **`OnDeviceLab (Solution)`** scheme so the Extract / Tools / Arena tabs
> are fully wired for the live demos. Participants use the default scheme (the TODO stubs).

## License
MIT — see [LICENSE](LICENSE). Model weights are under their own licenses (Qwen3, Apache-2.0).
Built by [Justin Lanfermann](https://lanfermann.dev) · [neatpass.app](https://neatpass.app).
