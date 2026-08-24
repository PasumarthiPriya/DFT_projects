// ============================================================================
//  P4 : IEEE 1149.1 Boundary Scan (JTAG)   -   FILE 2/2 : board testbench
// ----------------------------------------------------------------------------
//  A two-chip board, exactly the situation boundary scan was invented for:
//  once chips are soldered down you cannot probe the tracks between them, so
//  the wiring is tested THROUGH the JTAG port.
//
//      TDI -> [chip A] -> [chip B] -> TDO          (daisy-chained TAPs)
//      chip A pin_out[7:0]  --- 8 board nets --->  chip B pin_in[7:0]
//
//  Four experiments:
//    1. IDCODE  - read both device IDs through the daisy chain
//                 (exercises the whole TAP FSM and the chain ordering)
//    2. BYPASS  - prove the chain collapses to 2 bits instead of 32
//    3. EXTEST  - board interconnect test, comparing a WEAK 2-vector test
//                 against the proper COUNTING SEQUENCE, over injected board
//                 faults: stuck-at, open, and wired-AND / wired-OR shorts
//    4. INTEST  - show a CORE fault that EXTEST cannot see by construction,
//                 and that INTEST does catch
//
//  Interconnect test theory: give every net a UNIQUE NON-ZERO code across the
//  test vectors.  N nets need only ceil(log2(N+1)) vectors - here 4 vectors for
//  8 nets.  Zero codes are forbidden (indistinguishable from stuck-at-0) and
//  duplicate codes would hide shorts.  The observed code per net is its
//  "syndrome", which both DETECTS and LOCALISES the fault.
//
//  Expected:  weak 2-vector 7/13 = 53.8% (blind to every short)
//             counting 4-vector 13/13 = 100%
// ============================================================================
`timescale 1ns/1ps
module jtag_board_tb;

    localparam integer NF = 13;

    reg tck = 1'b0;
    reg tms, tdi, trst_n;
    reg cf_active;                      // core fault in chip A

    reg        tdo_s;                   // sampled TDO
    reg [63:0] dr_out;
    reg [7:0]  VEC [0:3];
    reg [3:0]  syn  [0:7];
    reg [3:0]  gsyn [0:7];

    integer i, k, v, fidx, detW, detC;
    reg     mismatch;
    reg [8*13:1] fname;
    reg [7:0]    BP = 8'h4D;
    reg [7:0]    tv;

    always #10 tck = ~tck;              // 50 MHz TCK

    // ---- board interconnect with fault injection ---------------------------
    reg  [2:0] bf_type;                 // 0 none 1 SA0 2 SA1 3 OPEN 4 ANDshort 5 ORshort
    reg  [2:0] bf_n, bf_a, bf_b;

    wire [7:0] drv;                     // chip A outputs
    reg  [7:0] rcv;                     // what chip B actually receives
    always @* begin
        rcv = drv;
        case (bf_type)
            3'd1: rcv[bf_n] = 1'b0;                     // shorted to GND
            3'd2: rcv[bf_n] = 1'b1;                     // shorted to VCC
            3'd3: rcv[bf_n] = 1'b1;                     // open, receiver pulls up
            3'd4: begin                                  // wired-AND short
                rcv[bf_a] = drv[bf_a] & drv[bf_b];
                rcv[bf_b] = drv[bf_a] & drv[bf_b];
            end
            3'd5: begin                                  // wired-OR short
                rcv[bf_a] = drv[bf_a] | drv[bf_b];
                rcv[bf_b] = drv[bf_a] | drv[bf_b];
            end
            default: ;
        endcase
    end

    // ---- the two chips, TAPs daisy-chained ---------------------------------
    wire tdo_a, tdo_b;
    jtag_chip #(.IDCODE_VAL(32'h1234_5673)) chipA (
        .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo_a), .trst_n(trst_n),
        .pin_in(8'h00), .pin_out(drv), .cf_active(cf_active));
    jtag_chip #(.IDCODE_VAL(32'hABCD_E893)) chipB (
        .tck(tck), .tms(tms), .tdi(tdo_a), .tdo(tdo_b), .trst_n(trst_n),
        .pin_in(rcv), .pin_out(), .cf_active(1'b0));

    // ------------------------------------------------------------------
    //  TAP primitives
    // ------------------------------------------------------------------
    task tick(input t_ms, input t_di);
        begin
            @(negedge tck);
            tms = t_ms; tdi = t_di;
            #1 tdo_s = tdo_b;           // TDO is valid before the rising edge
            @(posedge tck);
        end
    endtask

    task tap_reset;                     // 5 TMS=1 clocks force TEST_LOGIC_RESET
        begin
            trst_n = 1'b0; @(negedge tck); trst_n = 1'b1;
            for (i=0; i<5; i=i+1) tick(1'b1, 1'b0);
            tick(1'b0, 1'b0);           // -> RUN_TEST_IDLE
        end
    endtask

    //  8-bit IR shift : chip B receives the first 4 bits, chip A the last 4
    task shift_ir(input [7:0] val);
        integer j;
        begin
            tick(1,0); tick(1,0); tick(0,0); tick(0,0);      // -> SHIFT_IR
            for (j=0; j<8; j=j+1) tick((j==7), val[j]);
            tick(1,0); tick(0,0);                            // UPDATE_IR -> RTI
        end
    endtask

    task shift_dr(input integer n, input [63:0] val);
        integer j;
        begin
            tick(1,0); tick(0,0); tick(0,0);                 // CAPTURE_DR -> SHIFT_DR
            for (j=0; j<n; j=j+1) begin
                tick((j==n-1), val[j]);
                dr_out[j] = tdo_s;
            end
            tick(1,0); tick(0,0);                            // UPDATE_DR -> RTI
        end
    endtask

    // ------------------------------------------------------------------
    //  EXTEST interconnect run : nv vectors, syndromes into syn[]
    // ------------------------------------------------------------------
    task extest_run(input integer nv);
        reg [7:0] vv;
        begin
            shift_ir(8'h00);                                 // EXTEST in both chips
            for (i=0; i<8; i=i+1) syn[i] = 4'd0;
            for (k=0; k<=nv; k=k+1) begin
                vv = (k<nv) ? VEC[k] : 8'h00;
                //  {A input cells, A output cells, chip B's 16 cells}
                shift_dr(32, {32'h0, 8'h00, vv, 16'h0000});
                if (k>0)
                    for (i=0; i<8; i=i+1) syn[i] = syn[i] | (dr_out[8+i] << (k-1));
            end
        end
    endtask

    task set_fault(input integer n);
        begin
            bf_type=3'd0; bf_n=3'd0; bf_a=3'd0; bf_b=3'd0;
            case (n)
                0: begin bf_type=1; bf_n=0; fname="SA0  net0    "; end
                1: begin bf_type=1; bf_n=3; fname="SA0  net3    "; end
                2: begin bf_type=1; bf_n=7; fname="SA0  net7    "; end
                3: begin bf_type=2; bf_n=1; fname="SA1  net1    "; end
                4: begin bf_type=2; bf_n=5; fname="SA1  net5    "; end
                5: begin bf_type=3; bf_n=2; fname="OPEN net2    "; end
                6: begin bf_type=3; bf_n=6; fname="OPEN net6    "; end
                7: begin bf_type=4; bf_a=0; bf_b=1; fname="AND-short 0,1"; end
                8: begin bf_type=4; bf_a=2; bf_b=3; fname="AND-short 2,3"; end
                9: begin bf_type=4; bf_a=4; bf_b=7; fname="AND-short 4,7"; end
               10: begin bf_type=5; bf_a=1; bf_b=2; fname="OR-short  1,2"; end
               11: begin bf_type=5; bf_a=5; bf_b=6; fname="OR-short  5,6"; end
               12: begin bf_type=5; bf_a=3; bf_b=4; fname="OR-short  3,4"; end
            endcase
        end
    endtask

    task grade(input integer nv, output r);
        begin
            extest_run(nv);
            r = 1'b0;
            for (i=0; i<8; i=i+1) if (syn[i] !== gsyn[i]) r = 1'b1;
        end
    endtask

    // ------------------------------------------------------------------
    reg [31:0] idA, idB;
    reg [7:0]  good_o, bad_o;
    reg        rW, rC;

    initial begin
        tms=1'b1; tdi=1'b0; trst_n=1'b1; cf_active=1'b0;
        bf_type=3'd0; bf_n=0; bf_a=0; bf_b=0;

        // counting sequence : net i carries the unique non-zero code (i+1)
        for (v=0; v<4; v=v+1) begin
            tv = 8'h00;
            for (i=0; i<8; i=i+1) tv[i] = ((i+1) >> v) & 1;
            VEC[v] = tv;
        end

        // ---------------- TEST 1 : IDCODE ----------------
        tap_reset;                       // IDCODE is the reset default instruction
        shift_dr(64, 64'h0);
        idB = dr_out[31:0];
        idA = dr_out[63:32];
        $display("\n=====================================================================");
        $display(" TEST 1  IDCODE through the daisy chain");
        $display("   chip A = 0x%08X (expect 0x12345673)   %s", idA,
                 (idA===32'h1234_5673) ? "PASS" : "FAIL");
        $display("   chip B = 0x%08X (expect 0xABCDE893)   %s", idB,
                 (idB===32'hABCD_E893) ? "PASS" : "FAIL");

        // ---------------- TEST 2 : BYPASS ----------------
        tap_reset;
        shift_ir(8'hFF);                 // BYPASS in both chips
        shift_dr(12, 64'h0000_0000_0000_004D);   // pattern 8'b0100_1101
        mismatch = 1'b0;
        for (i=0; i<8; i=i+1) if (dr_out[i+2] !== BP[i]) mismatch = 1'b1;
        $display("\n TEST 2  BYPASS : 2 chips x 1 bit = 2-bit chain (vs 32-bit boundary chain)");
        $display("   pattern returned delayed by exactly 2 bits   %s",
                 mismatch ? "FAIL" : "PASS");

        // ---------------- TEST 3 : EXTEST interconnect ----------------
        $display("\n TEST 3  EXTEST board interconnect test");
        $display("---------------------------------------------------------------------");
        tap_reset; bf_type=3'd0;
        extest_run(4);
        for (i=0; i<8; i=i+1) gsyn[i] = syn[i];
        $display("   fault-free syndromes (must equal the codes 1..8):");
        $display("     net0..7 = %0d %0d %0d %0d %0d %0d %0d %0d",
                 gsyn[0],gsyn[1],gsyn[2],gsyn[3],gsyn[4],gsyn[5],gsyn[6],gsyn[7]);
        $display("---------------------------------------------------------------------");
        $display("   board fault        | 2-vector weak | 4-vector counting");

        detW=0; detC=0;
        for (fidx=0; fidx<NF; fidx=fidx+1) begin
            // --- weak test : all-0 then all-1 ---
            tap_reset; bf_type=3'd0;
            VEC[0]=8'h00; VEC[1]=8'hFF;
            extest_run(2);
            for (i=0; i<8; i=i+1) gsyn[i]=syn[i];
            tap_reset; set_fault(fidx);
            grade(2, rW);

            // --- counting sequence ---
            for (v=0; v<4; v=v+1) begin
                tv = 8'h00;
                for (i=0;i<8;i=i+1) tv[i] = ((i+1) >> v) & 1;
                VEC[v] = tv;
            end
            tap_reset; bf_type=3'd0;
            extest_run(4);
            for (i=0; i<8; i=i+1) gsyn[i]=syn[i];
            tap_reset; set_fault(fidx);
            grade(4, rC);

            detW = detW + rW; detC = detC + rC;
            $display("   %s  |      %s      |        %s", fname,
                     rW ? "DET" : "---", rC ? "DET" : "---");
        end
        bf_type=3'd0;
        $display("---------------------------------------------------------------------");
        $display("   2-vector weak     : %0d/%0d = %0d.%0d %%   (blind to every short)",
                 detW, NF, (detW*1000)/NF/10, (detW*1000)/NF%10);
        $display("   4-vector counting : %0d/%0d = %0d.%0d %%",
                 detC, NF, (detC*1000)/NF/10, (detC*1000)/NF%10);

        // ---------------- TEST 4 : INTEST vs a core fault ----------------
        $display("\n TEST 4  a CORE fault inside chip A");
        tap_reset; bf_type=3'd0; cf_active=1'b0;
        extest_run(4);
        for (i=0; i<8; i=i+1) gsyn[i]=syn[i];
        tap_reset; cf_active=1'b1;
        grade(4, rC);
        $display("   EXTEST detects it? %0s  <- correct: EXTEST disconnects the core",
                 rC ? "YES" : "NO ");

        // INTEST : drive the core from the input cells, capture its response
        tap_reset; cf_active=1'b0;
        shift_ir(8'h22);                                   // INTEST in both chips
        shift_dr(32, {32'h0, 8'h31, 8'h00, 16'h0000});     // A input cells = 0x31
        shift_dr(32, 64'h0);
        good_o = dr_out[23:16];                            // A output cells
        tap_reset; cf_active=1'b1;
        shift_ir(8'h22);
        shift_dr(32, {32'h0, 8'h31, 8'h00, 16'h0000});
        shift_dr(32, 64'h0);
        bad_o = dr_out[23:16];
        $display("   INTEST core response  good=0x%02X  faulty=0x%02X   detects it? %0s",
                 good_o, bad_o, (good_o!==bad_o) ? "YES" : "NO ");
        $display("=====================================================================\n");
        $finish;
    end
endmodule
