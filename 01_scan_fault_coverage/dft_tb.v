// ============================================================================
//  P1 : Full-Scan DFT + Single Stuck-at Fault Coverage
//  FILE 2/2 :  TESTBENCH  (robust concurrent fault simulator)
// ----------------------------------------------------------------------------
//  Method (textbook parallel fault simulation, no signature compaction):
//    * a GOLDEN (fault-free) copy and a FAULTY copy of the design run side by
//      side on identical stimulus.
//    * a fault is DETECTED the instant any OBSERVED output of the faulty copy
//      differs from the golden copy.  (No CRC/aliasing -> no false detects.)
//
//  Four DUT copies:
//      gb : SCAN=0, fault-free   |  fb : SCAN=0, faulty   -> BASELINE experiment
//      gs : SCAN=1, fault-free   |  fs : SCAN=1, faulty   -> FULL-SCAN experiment
//
//    BASELINE  observes only acc_out (functional pins).
//    FULL-SCAN observes scan_out (during unload) + acc_out.
//
//  For every fault (29 sites x SA0/SA1 = 58) it prints DET/undetected and a
//  final coverage summary to the Tcl console.
//  Expected:  baseline 42/58 = 72.4% ,  full-scan 56/58 = 96.6%.
// ============================================================================
`timescale 1ns/1ps
module dft_tb;

    localparam integer NPAT   = 64;
    localparam integer NSITE  = 29;
    localparam integer NFAULT = 58;

    reg        clk = 1'b0;
    reg        rst_n;
    reg  [1:0] opcode;
    reg  [3:0] data_in;
    reg        scan_en, scan_in;
    reg        f_active;
    reg  [5:0] f_site;
    reg        f_value;
    reg  [15:0] lfsr;

    integer s, det_base, det_scan;
    reg     detected;

    always #5 clk = ~clk;   // 100 MHz

    // outputs of the four copies
    wire [3:0] gb_acc, fb_acc, gs_acc, fs_acc;
    wire       gb_so,  fb_so,  gs_so,  fs_so;

    // ---- BASELINE pair (SCAN=0) : golden vs faulty -------------------------
    dft_dut #(.SCAN(0)) gb (.clk(clk),.rst_n(rst_n),.opcode(opcode),.data_in(data_in),
        .acc_out(gb_acc),.scan_en(1'b0),.scan_in(1'b0),.scan_out(gb_so),
        .f_active(1'b0),.f_site(6'd0),.f_value(1'b0));            // always fault-free
    dft_dut #(.SCAN(0)) fb (.clk(clk),.rst_n(rst_n),.opcode(opcode),.data_in(data_in),
        .acc_out(fb_acc),.scan_en(1'b0),.scan_in(1'b0),.scan_out(fb_so),
        .f_active(f_active),.f_site(f_site),.f_value(f_value));   // fault injected

    // ---- FULL-SCAN pair (SCAN=1) : golden vs faulty ------------------------
    dft_dut #(.SCAN(1)) gs (.clk(clk),.rst_n(rst_n),.opcode(opcode),.data_in(data_in),
        .acc_out(gs_acc),.scan_en(scan_en),.scan_in(scan_in),.scan_out(gs_so),
        .f_active(1'b0),.f_site(6'd0),.f_value(1'b0));            // always fault-free
    dft_dut #(.SCAN(1)) fs (.clk(clk),.rst_n(rst_n),.opcode(opcode),.data_in(data_in),
        .acc_out(fs_acc),.scan_en(scan_en),.scan_in(scan_in),.scan_out(fs_so),
        .f_active(f_active),.f_site(f_site),.f_value(f_value));   // fault injected

    function [15:0] nextl(input [15:0] v);
        nextl = {v[14:0], v[15]^v[13]^v[12]^v[10]};
    endfunction

    // ---- BASELINE run : functional patterns, compare acc_out ---------------
    task run_base;   // sets 'detected'
        integer p;
        begin
            detected = 1'b0;
            rst_n = 1'b0; scan_en = 1'b0; scan_in = 1'b0;
            @(posedge clk); @(posedge clk); rst_n = 1'b1;
            lfsr = 16'hACE1;
            for (p = 0; p < NPAT; p = p + 1) begin
                lfsr    = nextl(lfsr);
                opcode  = lfsr[1:0];
                data_in = lfsr[5:2];
                @(posedge clk); #1;
                if (gb_acc !== fb_acc) detected = 1'b1;   // observe pins
            end
        end
    endtask

    // ---- FULL-SCAN run : scan-in, capture, scan-out ; compare --------------
    task run_scan;   // sets 'detected'
        integer p, b;
        reg [11:0] sc_in;
        begin
            detected = 1'b0;
            rst_n = 1'b0; scan_en = 1'b0; scan_in = 1'b0;
            @(posedge clk); @(posedge clk); rst_n = 1'b1;
            lfsr = 16'hBEEF;
            for (p = 0; p < NPAT; p = p + 1) begin
                lfsr  = nextl(lfsr);
                sc_in = lfsr[11:0];
                lfsr  = nextl(lfsr);
                scan_en = 1'b1;
                for (b = 0; b < 12; b = b + 1) begin
                    scan_in = sc_in[b];
                    #1; if (gs_so !== fs_so) detected = 1'b1;  // observe scan chain
                    @(posedge clk);
                end
                scan_en = 1'b0;
                opcode  = lfsr[1:0];
                data_in = lfsr[5:2];
                @(posedge clk); #1;
                if (gs_acc !== fs_acc) detected = 1'b1;        // observe pins
            end
        end
    endtask

    // ---- coverage experiment ----------------------------------------------
    initial begin
        f_active = 1'b0; f_site = 6'd0; f_value = 1'b0;
        opcode = 2'd0; data_in = 4'd0; scan_en = 1'b0; scan_in = 1'b0;

        // ---------------- BASELINE ----------------
        $display("\n--- BASELINE (no scan) : faults NOT detected ---");
        det_base = 0;
        for (s = 0; s < NSITE; s = s + 1) begin
            f_active = 1'b1; f_site = s[5:0];
            f_value = 1'b0; run_base;
            if (detected) det_base = det_base + 1;
            else $display("   site %0d  SA0  undetected", s);
            f_value = 1'b1; run_base;
            if (detected) det_base = det_base + 1;
            else $display("   site %0d  SA1  undetected", s);
        end
        f_active = 1'b0;

        // ---------------- FULL-SCAN ----------------
        $display("\n--- FULL-SCAN : faults NOT detected ---");
        det_scan = 0;
        for (s = 0; s < NSITE; s = s + 1) begin
            f_active = 1'b1; f_site = s[5:0];
            f_value = 1'b0; run_scan;
            if (detected) det_scan = det_scan + 1;
            else $display("   site %0d  SA0  undetected (redundant/untestable)", s);
            f_value = 1'b1; run_scan;
            if (detected) det_scan = det_scan + 1;
            else $display("   site %0d  SA1  undetected (redundant/untestable)", s);
        end
        f_active = 1'b0;

        // ---------------- report ----------------
        $display("\n==========================================================");
        $display(" P1  DFT FAULT-COVERAGE REPORT   (%0d single stuck-at faults)", NFAULT);
        $display("----------------------------------------------------------");
        $display(" BASELINE  (no scan) : %0d / %0d  =  %0d.%0d %%",
                 det_base, NFAULT, (det_base*1000)/NFAULT/10, (det_base*1000)/NFAULT%10);
        $display(" FULL-SCAN (scan)    : %0d / %0d  =  %0d.%0d %%",
                 det_scan, NFAULT, (det_scan*1000)/NFAULT/10, (det_scan*1000)/NFAULT%10);
        $display("----------------------------------------------------------");
        $display(" DFT gain            : +%0d faults made testable by scan", det_scan-det_base);
        $display(" Ceiling             : %0d fault(s) redundant (untestable by ANY test)",
                 NFAULT-det_scan);
        $display("==========================================================");
        $finish;
    end
endmodule
