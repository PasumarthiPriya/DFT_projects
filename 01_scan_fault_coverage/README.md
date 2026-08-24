# 01 — Full Scan Insertion and Stuck-at Fault Coverage

**Result: 72.4 % → 96.6 % single stuck-at coverage after scan insertion.**

## What this demonstrates

A sequential circuit is hard to test because you cannot directly control or observe its
internal flip-flops. Full scan fixes that by chaining every flip-flop into a shift
register, making all of them both controllable and observable. This project measures
exactly how much that is worth.

The same RTL is elaborated twice, selected by the `SCAN` parameter:

- `SCAN=0` — plain D flip-flops (**before DFT**)
- `SCAN=1` — muxed-D scan cells on one scan chain (**after DFT**)

## The design (`dft_dut.v`)

A 4-bit accumulator ALU (ADD / SUB / AND / OR), a 2-bit operation counter, and a 6-bit
status register. Three choices make it a clean DFT experiment:

- **Only `acc_out[3:0]` is a pin.** The datapath result is observable, as in any chip.
- **The 6-bit status register drives nothing.** Its bits record internal conditions
  (zero, carry, parity, MSB…) but have no path to any output pin. These are *buried
  nodes* — invisible from the pins, reachable only by scanning them out. This is the
  observability problem scan exists to solve.
- **One redundant reconvergent cone.** `rr = (s0 & g) | (s0 & ~g)` equals `s0` for every
  value of `g`, so a fault on `g` can never change the output — **provably untestable**.

Fault injection uses the standard *saboteur* technique: a `` `SAB(id, net) `` macro that
forces a selected net to a constant. 29 sites × SA0/SA1 = **58 single stuck-at faults**.

## The testbench (`dft_tb.v`)

Concurrent fault simulation. A golden (fault-free) copy and a faulty copy of each design
run side by side on identical stimulus, and a fault counts as detected only when a
faulty output bit actually differs from the golden one at the same instant — so a false
detection is structurally impossible.

## Running it

Add both files, set `dft_tb` as simulation top, Run Behavioral Simulation → Run All.

## Expected output

```
--- BASELINE (no scan) : faults NOT detected ---
   site 14  SA0  undetected
   ...  (sites 14-19, 26, 28)

--- FULL-SCAN : faults NOT detected ---
   site 28  SA0  undetected (redundant/untestable)
   site 28  SA1  undetected (redundant/untestable)

 BASELINE  (no scan) : 42 / 58  =  72.4 %
 FULL-SCAN (scan)    : 56 / 58  =  96.6 %
 DFT gain            : +14 faults made testable by scan
 Ceiling             : 2 fault(s) redundant (untestable by ANY test)
```

## Reading the result

The 14 faults the baseline misses are **exactly** the buried status-register faults —
no scan, no observability. Full scan recovers every one. The final 2 are the redundant
cone, undetectable by *any* pattern set: the concrete reason practical coverage targets
are ~98–99 %, never 100 %.
