# On-Device Lab

A SwiftUI app that runs open-weight LLMs **entirely on your Mac or iPhone** via
[MLX](https://github.com/ml-explore/mlx-swift) — no API key, no server, works in airplane mode.
Built for the Porsche Tech Day talk *"Not Every On-Device AI Is Apple Intelligence."* Every demo
runs the same job two ways — an **open-weight model** vs **Apple's Foundation Model** — so you can
see the contrast live: latency, structured output, tool calling, and context limits.

## Run it
```bash
git clone https://github.com/jaylann/on-device-lab
cd on-device-lab
brew install xcodegen        # once, if you don't have it
xcodegen generate           # builds OnDeviceLab.xcodeproj from project.yml
open OnDeviceLab.xcodeproj
```
In Xcode pick the **`OnDeviceLab (Solution)`** scheme, then ⌘R. **Use this scheme for the live
demos** — the plain `OnDeviceLab` scheme leaves the teaching stubs unfilled, so the demos won't
produce numbers.

The first time you **Load** a model it downloads the weights (a few hundred MB to ~2 GB); after
that it runs fully offline. Load each model once on any connection ahead of time.

- **Requirements:** Apple Silicon Mac (M1 or newer), Xcode 26, ~4 GB free disk. On iPhone: iPhone 12+, iOS 17+.
- **Signing:** none is set on purpose → macOS uses "Sign to Run Locally" and ⌘R just works.
  (Red on ⌘R? Signing & Capabilities → Team = **None / Sign to Run Locally**.)
- **Apple FM demos** need macOS 26 / iOS 26 with Apple Intelligence turned on. Without it, the
  Apple FM lane politely sits out and the open-weight lanes still run everywhere.

## The four engines
Every screen races the same lineup:

| Engine | What it is |
|---|---|
| **Apple FM · ~3B** | Apple's on-device Foundation Model (needs Apple Intelligence) |
| **Qwen3 0.6B · 4-bit** | tiny & fast — the one that fails just often enough to be interesting |
| **SmolLM3 3B · 4-bit** | mid-size open-weight, 64k context |
| **Qwen3.5 2B · 4-bit** | 262k context — the long-window contender |

## The demos — five tabs
The app is five tabs along the bottom. Each is one story; run them left to right to tell the whole one.

### 💬 Chat — "it just runs on the device"
The plain "load a model, stream tokens" screen.
1. Tap the **Model** pill (top) → **Choose a model** → pick one (default **Qwen3 0.6B**).
2. Press **Load** and wait for "Loaded".
3. Type in the **Message** box and hit send. Tokens stream in; **TTFT** (ms) and **Tokens/s**
   update live.

The **Sample prompts** menu (toolbar) has ready-made prompts, and the **Benchmark** button
(toolbar) runs a fixed suite over the lineup and exports the numbers as JSON. **The move:** start
generating, then turn off Wi-Fi — it keeps streaming.

### 🏁 Arena — "race them side by side"
The same prompt to all four engines at once, TTFT and tok/s reading like dashboard gauges.
1. Pick a preset chip — **Range question**, **Receipt extraction**, **Why on-device?** — or type
   your own prompt.
2. Press the checkered-flag button. The fastest-TTFT and fastest-tok/s lanes highlight.

The toolbar mode menu offers **Sequential** (default — one lane at a time, fair numbers) vs
**Race mode** (all at once — looks dramatic, but the lanes fight over the GPU, so it warns that the
numbers aren't comparable).

### `{ }` Extract — "structured output that can't be malformed"
Pull six fields out of a messy EV-charging receipt, graded live against ground truth.
1. Pick an **engine** chip (default **Qwen3 0.6B** — it misses fields, which is the interesting part).
2. Pick a **receipt** chip — **IONITY (clean)**, **EnBW (clean)**, or **Fastned (messy scan)**.
3. Press **Run extraction**. Each of the six fields grades **green (right) or red (wrong)**, and
   the **Scoreboard** tallies passes per engine.

The open-weight path uses a grammar lock, so its JSON is always well-formed — wrong values, never
broken syntax. Apple FM's failure mode is refusal, not malformed JSON. (Point that out.)

### 🔧 Tools — "let the model call the car"
Answer a driver's question by calling car tools; every hop draws itself into a trace timeline.
1. Pick an **engine** chip (default **SmolLM3**).
2. Edit the **Driver question** (default: *"I'm at 20% battery near Stuttgart — where should I
   charge?"*).
3. Send. The trace fills hop by hop: model turn → tool call → tool result → grounded answer.

### 🔎 Context — "where the window ends"
A growing needle-in-a-trip-log prompt (~1k → ~16k tokens) sent to each engine.
1. Pick a **size** chip (~1k / ~3k / ~5k / ~8k / ~16k tokens).
2. Toggle the **engines** (multi-select; all on by default).
3. Press **Send ~Nk tokens**. Rows accumulate so TTFT growth stays visible.

**The money shot:** Apple FM hits its **4,096-token hard wall** while the open windows keep going
(Qwen3 32k · SmolLM3 64k · Qwen3.5 262k).

## Reproducing the numbers headless
`bench/` is a Python + Swift harness that measures the same TTFT/throughput from the command line
(Apple Silicon only) and exports the same JSON schema the app does — so phone, Mac, and CLI runs
feed the same numbers. See [`bench/README.md`](bench/README.md).

## License
MIT — see [LICENSE](LICENSE). Model weights are under their own licenses (Qwen3, Apache-2.0).
Built by [Justin Lanfermann](https://lanfermann.dev) · [neatpass.app](https://neatpass.app).
