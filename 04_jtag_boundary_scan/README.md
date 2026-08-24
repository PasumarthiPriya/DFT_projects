# 04 — IEEE 1149.1 Boundary Scan (JTAG)

**Result: board interconnect coverage 53.8 % (naive test) → 100 % (counting sequence),
plus a demonstration of EXTEST's scope limit against INTEST.**

## What this demonstrates

Once chips are soldered onto a board you cannot put a probe on the tracks between them.
Boundary scan solves this by placing a shift-register cell at every pin, so the wiring is
tested *through* a four-wire test port.

## The design

### `jtag_chip.v` — one chip with a complete TAP

- **TAP controller** — the standard **16-state FSM**, navigated purely by TMS:
  `TEST_LOGIC_RESET`, `RUN_TEST_IDLE`, and the two symmetric DR/IR columns
  (`SELECT → CAPTURE → SHIFT → EXIT1 → PAUSE → EXIT2 → UPDATE`).
- **Instruction register** — 4-bit, capturing `0001` as the standard mandates.
- **Data registers** — 32-bit IDCODE, 1-bit BYPASS, and a 16-cell **boundary scan
  register**: `bsr[7:0]` are output cells driving the pins, `bsr[15:8]` are input cells
  observing them. Each cell has a capture stage (the shift path) and an update stage (the
  parallel output latch), which is what lets a new value be shifted in while the old one
  is still driven.

| Instruction | Code | Purpose |
|-------------|------|---------|
| EXTEST | `0000` | pins driven from update latches, input cells capture pins → tests **board wiring** |
| SAMPLE/PRELOAD | `0001` | snapshot pins during normal operation, or preload the update latches |
| INTEST | `0010` | core driven *from* input cells, response captured *into* output cells → tests **core logic** |
| IDCODE | `1110` | 32-bit device identification (the reset default) |
| BYPASS | `1111` | single flip-flop, so an uninteresting chip costs 1 bit instead of its whole boundary register |

Shift convention: LSB first, TDI enters at the MSB end, TDO leaves from bit 0.

### `jtag_board_tb.v` — a two-chip board

```
TDI -> [chip A] -> [chip B] -> TDO            (daisy-chained TAPs)
chip A pin_out[7:0]  --- 8 board nets --->  chip B pin_in[7:0]
```

Injectable board faults: stuck-at-0/1, opens (receiver pulls up), and wired-AND /
wired-OR shorts between net pairs.

## Interconnect test theory

Give every net a **unique non-zero code** across the test vectors. With that, N nets need
only ⌈log₂(N+1)⌉ vectors — here **4 vectors for 8 nets**.

- A zero code is forbidden — indistinguishable from stuck-at-0.
- Duplicate codes would hide shorts.
- The observed code per net is its **syndrome**, which both *detects* and *localises*
  the fault.

The naive all-0/all-1 test fails structurally: two shorted nets driven to the *same*
value produce no discrepancy, so it is blind to every short no matter how often it runs.

## Running it

Add both files, set `jtag_board_tb` as simulation top, Run All. Fast — a few thousand
TCK cycles.

## Expected output

```
 TEST 1  IDCODE through the daisy chain
   chip A = 0x12345673 (expect 0x12345673)   PASS
   chip B = 0xABCDE893 (expect 0xABCDE893)   PASS

 TEST 2  BYPASS : 2 chips x 1 bit = 2-bit chain (vs 32-bit boundary chain)
   pattern returned delayed by exactly 2 bits   PASS

 TEST 3  EXTEST board interconnect test
   fault-free syndromes:  net0..7 = 1 2 3 4 5 6 7 8
   SA0/SA1/OPEN faults    ->  both tests DET
   AND-short / OR-short   ->  weak ---   counting DET
   2-vector weak     : 7/13 = 53.8 %   (blind to every short)
   4-vector counting : 13/13 = 100.0 %

 TEST 4  a CORE fault inside chip A
   EXTEST detects it? NO   <- correct: EXTEST disconnects the core
   INTEST core response  good=0x24  faulty=0x33   detects it? YES
```

## Reading the result

**TEST 4 is the most instructive.** `EXTEST detects it? NO` looks like a failure and is
the correct result: EXTEST deliberately disconnects the core and drives the pins from the
update latches, because its job is the wiring — a core fault *cannot* reach the
interconnect syndrome. INTEST reverses the data flow and catches it immediately. That is
the answer to "why would you ever need INTEST when you have EXTEST?"

One detail worth noting: pattern `0x5A` does **not** detect the core fault, because its
bit 0 is already 0 and so never sensitises a stuck-at-0 on that node — a concrete example
of fault sensitisation.
