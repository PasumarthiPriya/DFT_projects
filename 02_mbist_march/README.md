# 02 — Memory BIST (March Algorithms)

**Result: 63.1 % (MATS) → 94.7 % (March C-) memory fault coverage.**

## What this demonstrates

Embedded SRAM has no pin access, so it cannot be reached from a tester. A small on-chip
controller must test it by running a **March algorithm** — a fixed sequence of reads and
writes swept across the address space. This project shows that the *choice of algorithm*
is what determines which defects you actually catch.

## The design

### `mbist_mem.v` — SRAM with fault injection

An 8-word × 4-bit synchronous SRAM. One fault is injected at a time via the `f_*` ports,
covering the classic memory fault models:

| Model | Meaning |
|-------|---------|
| SAF | stuck-at — cell locked at 0 or 1 |
| TF | transition — cell cannot rise, or cannot fall |
| CFid | idempotent coupling — a write to one cell forces another to a value |
| CFin | inversion coupling — a write to one cell inverts another |
| AF | address decoder — two addresses alias to the same row |
| LCF | linked coupling — two aggressors cancel each other (the ceiling fault) |

`init`/`init_val` provide a backdoor preset of the whole array. A real SRAM powers up in
an arbitrary state, so the testbench uses this to start every grading run from a known
background.

### `mbist_ctrl.v` — microcoded March sequencer

A March test is a list of *elements*; each element sweeps all addresses in one direction
applying a short read/write sequence per cell. The controller's element table encodes
both algorithms, selected by `MODE`:

- `MODE=0` — **MATS** (4N): `↑(w0); ↑(r0,w1); ↑(r1)` — weak baseline
- `MODE=1` — **March C-** (10N): `↑(w0); ↑(r0,w1); ↑(r1,w0); ↓(r0,w1); ↓(r1,w0); ↑(r0)`

On any read mismatch it latches `fail` and `fail_addr` — the diagnosis output real MBIST
provides.

## Grading criterion — "guaranteed detection"

Each fault is run **twice**: once from an all-0 background, once from all-1. It counts as
detected only if flagged in **both**.

This matters. Grading from a single background inflates the score: starting from all-1s,
MATS's opening `w0` accidentally creates the falling transitions that expose can't-fall
faults — detection by luck, not by algorithm. The `[bg0 n bg1 y]` tags in the output show
exactly which faults MATS caught only by luck.

## Running it

Add all three files, set `mbist_tb` as simulation top, Run All.

## Expected output

```
  fault  7  type2 A(6.3) V(0.0) :  MATS --- [bg0 n bg1 y]   MarchC- DET
  ...
  BASELINE  MATS   (4N) : 12 / 19  =  63.1 %
  MBIST     MarchC-(10N): 18 / 19  =  94.7 %
     MATS    12/19 guaranteed vs 15/19 luck-dependent  -> NOT robust
     MarchC- 18/19 guaranteed vs 18/19 luck-dependent  -> robust
  Ceiling               : 1 fault (linked coupling) escapes March C-
```

## Reading the result

The faults MATS misses are all **fall-transition and coupling** faults. March C- recovers
every one except the linked coupling fault, where two aggressors cancel.

The strongest line is the robustness comparison: March C- detects 18/19 from *both*
backgrounds, so its coverage is **initial-state independent**. MATS's is not. That is why
March C- is the industry standard — not merely more coverage, but coverage that does not
depend on power-on luck.
