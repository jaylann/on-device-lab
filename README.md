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
In Xcode, ⌘R to build and run. There are two schemes:
- **`OnDeviceLab`** — your workspace. A handful of `TODO`s are left blank for you to fill in
  ([see below](#the-tasks--fill-in-the-todos)); until you do, some demos won't produce numbers.
- **`OnDeviceLab (Solution)`** — the finished reference. Run it to see everything working, or peek
  when you get stuck.

The first time you **Load** a model it downloads the weights (a few hundred MB to ~2 GB); after
that it runs fully offline. Load each model once on any connection ahead of time.

- **Requirements:** Apple Silicon Mac (M1 or newer), Xcode 26, ~4 GB free disk. On iPhone: iPhone 12+, iOS 17+.
- **Signing:** none is set on purpose → macOS uses "Sign to Run Locally" and ⌘R just works.
  (Red on ⌘R? Signing & Capabilities → Team = **None / Sign to Run Locally**.)
- **Apple FM demos** need macOS 26 / iOS 26 with Apple Intelligence turned on. Without it, the
  Apple FM lane politely sits out and the open-weight lanes still run everywhere.

## Running offline (venue distribution)
No Wi-Fi at the venue, or 30 people about to download the same weights at once? The app reads
models straight from `~/Documents/models/<repo-leaf>/` when present (see
`ModelCatalog.localDirectory`) — no network, no in-app import step. Just get the folders there.

**Easiest — pre-load beforehand.** On any connection, open the app and **Load** each model once.
The weights cache locally and every run after that is fully offline. If everyone does this the
night before, there's nothing to distribute.

**No connection — hand out the `models` folder.** It holds the three folders the app needs
(~3.4 GB total; Apple FM is a system model with no file):

```
models/
  Qwen3-0.6B-4bit/
  SmolLM3-3B-4bit/
  Qwen3.5-2B-MLX-4bit/
```

Share the whole `models` folder however you like — USB stick or AirDrop — then on each Mac
**drop it into `~/Documents/`**, so you end up with `~/Documents/models/Qwen3-0.6B-4bit/` and so
on. That's the whole setup: no in-app step, and Load then runs with Wi-Fi off (the app reads
`~/Documents/models/<name>/` directly — see `ModelCatalog.localDirectory`).

- It must be `~/Documents/models/` — **not** `~/Library/Caches/…`; only the Documents path
  loads without network. Keep the folder names exactly as above (they're the Hugging Face repo
  leaf) — a rename or extra nesting makes the app silently download instead.
- iPhone can't be sideloaded this way (sandboxed Documents) — pre-load on the phone beforehand.

## The four engines
Every screen races the same lineup:

| Engine | What it is |
|---|---|
| **Apple FM · ~3B** | Apple's on-device Foundation Model (needs Apple Intelligence) |
| **Qwen3 0.6B · 4-bit** | tiny & fast — the one that fails just often enough to be interesting |
| **SmolLM3 3B · 4-bit** | mid-size open-weight, 64k context |
| **Qwen3.5 2B · 4-bit** | 262k context — the long-window contender |

## The demos — five tabs
The app is five tabs along the bottom. Each is one story; run them left to right.

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
broken syntax. Apple FM's failure mode is refusal, not malformed JSON.

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

## The tasks — fill in the TODOs
On the plain `OnDeviceLab` scheme, the interesting lines are blank. Each demo is powered by one or
two `TODO`s you write in — usually the same job twice, the open-weight way and the Apple FM way.
The finished answers live in `OnDeviceLab/Solutions/Solutions.swift` (what the Solution scheme
compiles), so you can check your work or unblock without hunting.

| `TODO` | Powers | File | What you write |
|---|---|---|---|
| **1 & 2** | Chat → Benchmark | `Benchmark.swift` | stamp the first-token time and count streamed tokens — until then it reads `0 tok/s` |
| **3a** | Extract · open-weight | `Engines/GrammarLock.swift` | the six-field JSON schema the grammar locks decoding to |
| **3b** | Extract · Apple FM | `Demos/TicketExtraction.swift` | one `respond(generating:)` call that decodes straight into a typed struct |
| **4a** | Tools · open-weight | `Demos/CarTools.swift` | route the model's tool call to the matching `CarToolbox` function |
| **4b** | Tools · Apple FM | `Demos/CarTools.swift` | implement `WeatherTool.call` |

Stuck on any of them? Switch to **`OnDeviceLab (Solution)`**, see it run, then come back.

## Reproducing the numbers headless
`bench/` is a Python + Swift harness that measures the same TTFT/throughput from the command line
(Apple Silicon only) and exports the same JSON schema the app does — so phone, Mac, and CLI runs
feed the same numbers. See [`bench/README.md`](bench/README.md).

## License
MIT — see [LICENSE](LICENSE). Model weights are under their own licenses (Qwen3, Apache-2.0).
Built by [Justin Lanfermann](https://lanfermann.dev) · [neatpass.app](https://neatpass.app).
