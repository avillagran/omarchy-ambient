# Intel carousel performance

Physical mbp-intel (i5-5257U, Iris 6100), 2026-11-01 local date.
Work stays on `perf/carousel-paint`; nothing published.

The optional AmbientCells painter keeps the Canvas fallback. It parses cells
without allocating lists/substrings, caches consecutive colors, and draws
consecutive rectangles of the same color together without changing draw order.
Hidden slices disable their offscreen layers. Parallax animations only run
while visible, including the existing fix from the preceding round.

## Validation

- Real carousel, previous local native painter versus this variant, same paced
  preview producer; ABBA, two 8-second samples per variant per scene.
- Fixed 87x25 grid, DPR 2, 20 FPS requested; 19–20 FPS received.
- CPU sums shell, preview producer, Python bridge and parec. 100% is one
  logical core; compositor CPU is excluded.
- Neon City: median CPU 56.12% → 52.57% (6.3% relative reduction).
- Aquarium: 47.33% → 47.05%; no convincing improvement at this sample size.
- RC6 GPU estimates: City 59.97% → 59.60%, Aquarium 61.62% → 61.93%.
  No demonstrated GPU saving; this is not a power measurement.
- Sampled temperatures during the measured intervals: 81–83 C maxima;
  reading after IPC/startup reached 87 C. These are short samples, not thermal
  equilibrium. A preceding exploratory batch stopped at 90 C and is excluded;
  compilation also overlapped exploratory work. The final ABBA batch completed
  without a thermal stop, with an 88 C interval guard and cooling between runs.
- Native parsing microbenchmark: 300 recorded frames, 218 ms → 74 ms in both
  ABBA repetitions. This isolates parsing, not total carousel performance.
- Four recorded frames (City, Lunar, Tunnel, Aquarium) produce identical PNGs
  before/after, both opaque and at opacity 0.78, 768x475, DPR 1. This does not
  establish pixel equivalence for every DPR/transform.
- Qt 6.12 Intel compilation with `-Wall -Wextra`; 14 selector tests pass.

Intel restored the exact installed renderer and plugin tree (official 0.4.0),
with no preview or parec processes, no live background, and stay-awake enabled.
The tested variant is not installed permanently. M2 not tested in this round.

Private harness, snapshots and redacted report: `/var/tmp/ambient-intel-round/`
on the coordination host; `report.json` identifies the data and limitations.

## Edge-mask composition round (2026-11-01)

The native painter now applies the slice silhouette itself. It caches only
left/right alpha strips (about 416 KiB at the tested size), then multiplies
those strips into the frame. The opaque center needs no alpha-mask pass.
The selected native preview bypasses the parent's offscreen layer and
MultiEffect; static neighbors, non-native content and Canvas keep their masks.
If creation fails after allocating an older native type, destroy that partial
item so Canvas can become visible.

A full-image CPU mask was rejected: GPU use fell, but shell CPU rose to about
70–75%. Applying only the edge strips retained the GPU saving without that
large CPU increase.

Physical Intel ABBA against 406e18e, same paced producer, fixed 87x25/DPR 2,
20 FPS requested; two six-second samples per variant per scene:

| Scene | Measured CPU before → after | RC6 GPU estimate before → after |
|---|---|---|
| Neon City | 62.80% → 53.01% (−15.6%) | 59.70% → 29.60% |
| Aquarium | 62.19% → 43.85% (−29.5%) | 61.82% → 29.95% |

This round's CPU total **includes compositor CPU**, in addition to shell,
producer, bridge and parec. It is not directly comparable to the preceding
round's total, which excludes compositor. 100% still means one logical core.
Received cadence stayed about 19–20 FPS. No watts/equilibrium claim: starting
temperatures differ; interval peaks were 81–82 C before and 73–75 C after.

One fixed-frame capture of the real masked preview, including title/border,
was compared at 1536x950 physical pixels. The scene and corners match; 160
pixels differ by at most 2/255 in the title label due to compositing rounding.
This is not pixel-identity evidence for all content/transforms.

Fresh automatic-mode checks for City and Aquarium both settled at level 2,
about 19–20 FPS, with interval peaks 77 C and 76 C respectively. A fresh shell
with an older native library lacking `skew` used Canvas and successfully saved
its preview. Final source compiled on Intel with `-Wall -Wextra`; 14 selector
tests pass. No M2 validation in this round.

The installed renderer, plugin and preview bridge were restored after each
trial; official Ambient 0.4.0 remains installed. Detailed samples, harness and
redacted report: `/var/tmp/ambient-composition/report.json` on the coordination
host. No source push or release.
