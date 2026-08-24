# DFT Projects — Design-for-Testability Infrastructure in Verilog

Four self-contained Design-for-Testability (DFT) blocks written in Verilog-2001 and
verified in Xilinx Vivado (XSim). Each project builds the test hardware, injects a
defined fault population, and **measures fault coverage before and after** the DFT
technique is applied — so every claim in this repo is a number produced by a
simulation you can re-run, not an assertion.

A deliberate theme runs through all four: each one has an **honest coverage ceiling**
— faults that remain undetected for a structural reason — because understanding *why*
100% is usually unreachable is the point of the exercise.

---

## Results at a glance

| # | Project | Technique | Baseline | After DFT | Ceiling / limit |
|---|---------|-----------|----------|-----------|-----------------|
| 01 | Scan + fault coverage | Full muxed-D scan insertion | **72.4 %** | **96.6 %** | 2 structurally redundant faults |
| 02 | Memory BIST | March C- vs MATS | **63.1 %** | **94.7 %** | 1 linked coupling fault |
| 03 | Logic BIST | STUMPS: PRPG + phase shifter + MISR | 6.3 % @ 1 pattern | **96.9 %** @ 1024 | redundant fault + random-pattern-resistant tail |
| 04 | Boundary scan | IEEE 1149.1 TAP, EXTEST | **53.8 %** | **100 %** | EXTEST is blind to core faults by construction |

---

## Repository layout

```
01_scan_fault_coverage/    full scan insertion + stuck-at fault grading
02_mbist_march/            microcoded March MBIST controller + SRAM
03_lbist_stumps/           STUMPS logic BIST: LFSR PRPG, phase shifter, MISR
04_jtag_boundary_scan/     IEEE 1149.1 TAP + two-chip board interconnect test
```

Each folder has its own README with the design description, how to run it, and the
expected console output.

---

## How to run (Vivado)

1. Create an RTL project (any part — nothing is synthesised, this is simulation only).
2. **Add Sources → Add or create simulation sources**, and add every `.v` file from
   one project folder.
3. Set the testbench as simulation top (`dft_tb`, `mbist_tb`, `lbist_tb`, or
   `jtag_board_tb`).
4. **Run Simulation → Run Behavioral Simulation**, then **Run All** (each testbench
   ends itself with `$finish`).
5. Read the report in the **Tcl Console**.

Runtimes are a few seconds except project 03, which sweeps 64 faults × 2048 patterns
(~0.9 M clock cycles) and takes roughly 1–2 minutes.

Nothing is Vivado-specific — the sources are plain Verilog-2001 and also run under
Icarus Verilog:

```sh
iverilog -o sim *.v && vvp sim
```

---

## The four projects

### 01 — Full scan insertion and stuck-at fault coverage

A small ALU datapath whose accumulator is the only pin-visible output, plus a 6-bit
**buried status register** that drives nothing functionally and is therefore
unobservable from the pins. The same RTL is elaborated twice — once with ordinary
flip-flops, once with muxed-D scan cells on a scan chain — and 58 single stuck-at
faults are graded against each by golden-vs-faulty simulation.

Coverage rises **72.4 % → 96.6 %**. Every fault the baseline misses is a buried
status-register fault; the two that survive scan are a **structurally redundant
reconvergent cone** that no pattern can ever detect.

### 02 — Memory BIST (March algorithms)

An 8×4 SRAM with injectable memory fault models — stuck-at, transition, coupling
(idempotent and inversion), address-decoder, and one linked coupling fault. A single
**microcoded March sequencer** runs either algorithm, selected by a parameter.

March C- reaches **94.7 %** against **63.1 %** for a MATS baseline. Each fault is
graded from **both an all-0 and an all-1 background**, and counted only if detected
from both — the "guaranteed detection" criterion, since a real SRAM powers up in an
arbitrary state. March C- scores identically from both backgrounds; MATS does not,
which is a concrete demonstration of *why* March C- is the standard.

### 03 — Logic BIST (STUMPS)

Self-test with no tester and no stored patterns: a 16-bit LFSR **PRPG** feeds two
parallel scan chains through an XOR **phase shifter**, and a **MISR** compacts the
whole response stream into one signature.

The measured coverage curve is the classic LBIST shape — steep rise, long plateau,
slow tail, hard ceiling: **6.3 % @ 1 pattern → 90.6 % @ 8 → 96.9 % @ 1024**. The tail
is caused by four deliberately embedded **random-pattern-resistant** nodes, and the
testbench identifies them automatically along with the redundant fault.

An 8-bit MISR runs concurrently on identical stimulus to demonstrate **signature
aliasing**: it reports 95.3 % where the 16-bit MISR reports 96.9 %, because a faulty
signature collided back onto the good one — a defective chip reporting PASS.

### 04 — IEEE 1149.1 boundary scan (JTAG)

A complete Test Access Port — the standard **16-state TAP FSM**, instruction register,
IDCODE, BYPASS, and a 16-cell boundary scan register — implementing EXTEST,
SAMPLE/PRELOAD, INTEST, IDCODE and BYPASS. Two chips are daisy-chained
(`TDI → A → B → TDO`) on a board with 8 interconnect nets carrying injectable stuck-at,
open, and wired-AND / wired-OR short faults.

A **counting sequence** giving every net a unique non-zero code detects **13/13** board
faults using only 4 vectors, against **53.8 %** for a naive all-0/all-1 test which is
structurally blind to shorts. A fifth experiment shows a **core fault that EXTEST
cannot see** — correctly, since EXTEST disconnects the core — and that INTEST catches it.

---

## Scope and honest framing

- These are **small designs sized so the entire fault population can be enumerated and
  graded exhaustively**. That is deliberate: every number here is an exact count, not
  a sample.
- The projects perform **fault injection and coverage measurement**, not automatic test
  pattern generation. There is no ATPG engine here — ATPG (D-algorithm, PODEM, FAN) is
  a software search problem, and commercial tools such as TetraMAX or Tessent solve it.
  Test patterns in this repo are hand-derived, algorithmic (March), or pseudo-random
  (LFSR).
- The `f_*` fault-injection ports and the memory backdoor preset are **simulation-only
  harnesses**. They would not exist in silicon; the synthesisable parts are the scan
  chains, BIST controllers, and TAP.

## Verification note

Every coverage figure was cross-checked against an independent reference model of the
same algorithm before the RTL was trusted, and the reported numbers are what the
Verilog actually prints. Two real bugs were found and fixed this way: an MBIST
testbench that inflated its baseline because the SRAM was never cleared between fault
runs (catching transition faults by luck from leftover data), and an LBIST circuit that
took spurious capture clocks while its engine sat idle.
