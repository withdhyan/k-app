# k-app

The iOS client for [k-daemon](../../../k-daemon) — a sovereign personal agent. SwiftUI,
iPad + iPhone universal, one design language, no third-party dependencies.

## Surfaces

- **cadence** — home. The day as a single now-instrument: current block with start/elapsed,
  the next block folded under a hairline, recalibration shown as honest diffs when the agent
  reshapes the day, a live body rail (hrv, sleep, logged meals), and quiet one-tap acts.
- **chat** — conversation with K over the live camera dimmed to ink. Founder lines right and
  dim, K lines left; a terse text stream, no bubbles. Zero-friction meal logging from the composer.
- **build** — the decision desk: cards the factory raises (approvals, holds, discovered edges),
  answered with one tap each.
- **mind** — a verdict stack: what the agent's background passes surfaced, judged junk / nod /
  act-on in bursts. Verdicts are the eval's ground truth.
- **admin** — quarantined intake, parse-confirm, due-today marks.

## Design system

The language is codified and enforced:

- `docs/design/catalog.json` — the primitive catalog (versioned; a drift test fails if code and
  catalog disagree)
- `docs/doctrine.json` — the interaction laws (interruption classes ambient/peripheral/focal,
  one-slot arbiter, recognition-over-recall, silence-default)
- `Sources/KStyle.swift` — every token: 3pt radii, dim text hierarchy (.87/.64/.48/.30),
  lowercase mono metadata, paper/glass tones
- `Sources/KPrimitives.swift` — the components; views compose primitives, never restyle

Litmus: any screen should be readable by scanning type alone, and nothing may exceed the
now-instrument's contrast.

## Wire contract

`Tests/Fixtures/k-contract-fixture.json` is vendored from the daemon and decoded through the
real models in tests — server/client drift fails CI on both sides, not in production.

## Running

Open `Kedar.xcodeproj`, set your daemon address (UserDefaults `cskBaseURL`, defaults to
localhost), build to simulator or device. The camera backdrop is preview-only by construction:
no capture outputs are attached, frames are never recorded or transmitted.

## License

AGPL-3.0 — see [LICENSE](LICENSE).
