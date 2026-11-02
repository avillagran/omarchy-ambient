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
