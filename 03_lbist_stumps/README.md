# 03 — Logic BIST (STUMPS)

**Result: coverage curve 6.3 % @ 1 pattern → 90.6 % @ 8 → 96.9 % @ 1024, plus a
measured demonstration of MISR signature aliasing.**

## What this demonstrates

Projects 01 and 02 assume an external tester. LBIST removes it: the chip tests *itself*,
with no stored patterns and no ATE. The cost is that pseudo-random patterns are far less
efficient than deterministic ones — which is exactly what this project measures.

STUMPS = **S**elf-**T**est **U**sing **M**ISR and **P**arallel **S**hift-register
sequence generator.

## The design

### `lbist_cut.v` — circuit under test

The datapath from project 01, re-split into **two parallel 6-bit scan chains**
(chain A = accumulator + op counter, chain B = status bits). Two things are embedded
deliberately:

- **Four rarely-asserted nodes** with probabilities 1/64, 1/256, 1/1024 and 1/4096. A
  stuck-at-**0** on such a node is only sensitised when the node should be 1, so random
  patterns need thousands of vectors to catch it. These are the
  **random-pattern-resistant** faults that create LBIST's long tail.
- **One redundant reconvergent cone** (site 29) — untestable by any pattern, the hard
  ceiling.

32 sites × SA0/SA1 = **64 single stuck-at faults**.

### `lbist_engine.v` — the self-test hardware

| Block | Role |
|-------|------|
| **PRPG** | 16-bit maximal-length LFSR generating pseudo-random patterns on chip |
| **Phase shifter** | XOR taps at different LFSR positions feed the two chains. Adjacent LFSR bits are time-shifted copies of each other, so without this the chains would be strongly correlated and coverage would suffer. |
| **MISR** | compacts the entire response stream into one signature word; width is a parameter |
| **FSM** | per pattern: 6 shift cycles (fill chains, unload previous response into the MISR), then 1 capture cycle |

### `lbist_tb.v` — grading

A golden engine+CUT runs against a faulty engine+CUT, comparing signatures produced by
**real MISR hardware** — the same pass/fail decision a real LBIST controller makes. The
whole curve comes from one simulation: each fault runs once to 2048 patterns with
signatures sampled at every checkpoint.

## Running it

Add all three files, set `lbist_tb` as simulation top, Run All.
**This one takes 1–2 minutes** (~0.9 M clock cycles) — it is not hung.

## Expected output

```
   patterns |  16-bit MISR   |   8-bit MISR   | aliasing
        1   |   4/64 =  6.3 %  |   4/64 =  6.3 %  |
        2   |  31/64 = 48.4 %  |  31/64 = 48.4 %  |
        4   |  51/64 = 79.7 %  |  51/64 = 79.7 %  |
        8   |  58/64 = 90.6 %  |  58/64 = 90.6 %  |
      ...     (plateau through 128)
      256   |  59/64 = 92.2 %  |  58/64 = 90.6 %  | <-- fault hidden by signature collision
     1024   |  62/64 = 96.9 %  |  61/64 = 95.3 %  | <-- fault hidden by signature collision
     2048   |  62/64 = 96.9 %  |  62/64 = 96.9 %  |

RANDOM-PATTERN-RESISTANT faults (first detected only at >=256 patterns):
   site 25 SA0  first detected at pattern 256
   site 26 SA0  first detected at pattern 1024
   site 27 SA0  first detected at pattern 1024
   site 30 SA0  first detected at pattern 1024

UNDETECTED after 2048 patterns:
   site 29 SA0/SA1  -> REDUNDANT (untestable by any pattern)
```

## Reading the result

**The plateau from 8 to 128 patterns is the real lesson.** Sixteen times more patterns
bought zero extra coverage: pseudo-random patterns exhaust the easy faults almost
immediately, and everything after is the hard tail. This is why production LBIST is
paired with **test point insertion**.

**The tail tracks the node probabilities.** Site 25 (1/64) surfaced at 256 patterns;
sites 26, 27 and 30 (1/256, 1/1024, 1/4096) needed 1024. The tail's shape is set by the
sensitisation probability of each node.

**The aliasing rows are the sharpest result.** At 1024 patterns the 8-bit MISR reports
95.3 % where the 16-bit reports 96.9 % on *identical* stimulus — a genuinely detected
fault hidden because the faulty signature collided back onto the good one. A chip
reporting PASS while defective. This is why real MISRs are wide.

Note that LBIST's 96.9 % here is *below* what deterministic scan patterns achieve on
comparable logic (project 01 hit its ceiling with 64 patterns). That is the real
trade-off: LBIST costs coverage and pattern count but eliminates ATE pattern storage
entirely.
