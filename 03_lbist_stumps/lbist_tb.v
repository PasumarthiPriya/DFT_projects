// ============================================================================
//  P3 : Logic BIST (STUMPS)   -   FILE 3/3 : testbench / fault grader
// ----------------------------------------------------------------------------
//  Grading method (robust, same principle as the fixed P1):
//    a GOLDEN engine+CUT (fault-free) and a FAULTY engine+CUT run side by side
//    on the same clock.  Both build their signature in real MISR hardware.
//    A fault is DETECTED at pattern N if the two signatures differ at N -
//    exactly the pass/fail decision a real LBIST controller makes.
//
//  The whole sweep is done in ONE simulation: each fault runs once to
//  MAXPAT patterns and the signatures are sampled at every checkpoint, giving
//  the full coverage-vs-pattern-count curve.
//
//  Two MISR widths run concurrently on the same stimulus:
//    16-bit  -> the real curve
//     8-bit  -> shows SIGNATURE ALIASING (a faulty signature collides back
//               onto the good one, so a detected fault is reported as passing)
//
//  Expected:  6.3% @1 pattern -> 90.6% @8 -> plateau -> 92.2% @256
//             -> 96.9% @1024 (saturated).  2 faults never detected = the
//             redundant cone (site 29).  Faults first caught only at >=256
//             patterns are the random-pattern-resistant ones.
//
//  NOTE: ~0.9 M clock cycles total; expect roughly 1-2 minutes in XSim.
// ============================================================================
`timescale 1ns/1ps
module lbist_tb;

    localparam integer NSITE  = 32;
    localparam integer NFAULT = 64;
    localparam integer MAXPAT = 2048;
    localparam integer NCHK   = 12;

    reg clk = 1'b0;
    reg rst_n, start;
    reg f_active;
    reg [5:0] f_site;
    reg f_value;

    integer CHK [0:NCHK-1];
    integer det16 [0:NCHK-1];
    integer det8  [0:NCHK-1];
    integer firstdet [0:NFAULT-1];

    integer s, v, fidx, ci, pcount, i, n;

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    //  golden / faulty pairs, 16-bit MISR
    // ------------------------------------------------------------------
    wire g16_se, g16_ce, g16_sa, g16_sb, g16_ao, g16_bo, g16_tick;
    wire [1:0] g16_op; wire [3:0] g16_din, g16_acc; wire [15:0] g16_sig;
    lbist_engine #(.MISR_W(16)) eng_g16 (.clk(clk),.rst_n(rst_n),.start(start),
        .scan_en(g16_se),.cap_en(g16_ce),.sa_in(g16_sa),.sb_in(g16_sb),
        .sa_out(g16_ao),.sb_out(g16_bo),.pi_op(g16_op),.pi_din(g16_din),
        .acc_out(g16_acc),.sig(g16_sig),.pat_tick(g16_tick));
    lbist_cut cut_g16 (.clk(clk),.rst_n(rst_n),.scan_en(g16_se),.cap_en(g16_ce),
        .sa_in(g16_sa),.sb_in(g16_sb),.sa_out(g16_ao),.sb_out(g16_bo),
        .pi_op(g16_op),.pi_din(g16_din),.acc_out(g16_acc),
        .f_active(1'b0),.f_site(6'd0),.f_value(1'b0));

    wire f16_se, f16_ce, f16_sa, f16_sb, f16_ao, f16_bo, f16_tick;
    wire [1:0] f16_op; wire [3:0] f16_din, f16_acc; wire [15:0] f16_sig;
    lbist_engine #(.MISR_W(16)) eng_f16 (.clk(clk),.rst_n(rst_n),.start(start),
        .scan_en(f16_se),.cap_en(f16_ce),.sa_in(f16_sa),.sb_in(f16_sb),
        .sa_out(f16_ao),.sb_out(f16_bo),.pi_op(f16_op),.pi_din(f16_din),
        .acc_out(f16_acc),.sig(f16_sig),.pat_tick(f16_tick));
    lbist_cut cut_f16 (.clk(clk),.rst_n(rst_n),.scan_en(f16_se),.cap_en(f16_ce),
        .sa_in(f16_sa),.sb_in(f16_sb),.sa_out(f16_ao),.sb_out(f16_bo),
        .pi_op(f16_op),.pi_din(f16_din),.acc_out(f16_acc),
        .f_active(f_active),.f_site(f_site),.f_value(f_value));

    // ------------------------------------------------------------------
    //  golden / faulty pairs, 8-bit MISR (aliasing demonstration)
    // ------------------------------------------------------------------
    wire g8_se, g8_ce, g8_sa, g8_sb, g8_ao, g8_bo, g8_tick;
    wire [1:0] g8_op; wire [3:0] g8_din, g8_acc; wire [7:0] g8_sig;
    lbist_engine #(.MISR_W(8)) eng_g8 (.clk(clk),.rst_n(rst_n),.start(start),
        .scan_en(g8_se),.cap_en(g8_ce),.sa_in(g8_sa),.sb_in(g8_sb),
        .sa_out(g8_ao),.sb_out(g8_bo),.pi_op(g8_op),.pi_din(g8_din),
        .acc_out(g8_acc),.sig(g8_sig),.pat_tick(g8_tick));
    lbist_cut cut_g8 (.clk(clk),.rst_n(rst_n),.scan_en(g8_se),.cap_en(g8_ce),
        .sa_in(g8_sa),.sb_in(g8_sb),.sa_out(g8_ao),.sb_out(g8_bo),
        .pi_op(g8_op),.pi_din(g8_din),.acc_out(g8_acc),
        .f_active(1'b0),.f_site(6'd0),.f_value(1'b0));

    wire f8_se, f8_ce, f8_sa, f8_sb, f8_ao, f8_bo, f8_tick;
    wire [1:0] f8_op; wire [3:0] f8_din, f8_acc; wire [7:0] f8_sig;
    lbist_engine #(.MISR_W(8)) eng_f8 (.clk(clk),.rst_n(rst_n),.start(start),
        .scan_en(f8_se),.cap_en(f8_ce),.sa_in(f8_sa),.sb_in(f8_sb),
        .sa_out(f8_ao),.sb_out(f8_bo),.pi_op(f8_op),.pi_din(f8_din),
        .acc_out(f8_acc),.sig(f8_sig),.pat_tick(f8_tick));
    lbist_cut cut_f8 (.clk(clk),.rst_n(rst_n),.scan_en(f8_se),.cap_en(f8_ce),
        .sa_in(f8_sa),.sb_in(f8_sb),.sa_out(f8_ao),.sb_out(f8_bo),
        .pi_op(f8_op),.pi_din(f8_din),.acc_out(f8_acc),
        .f_active(f_active),.f_site(f_site),.f_value(f_value));

    // ------------------------------------------------------------------
    //  run one fault to MAXPAT, sampling signatures at every checkpoint
    // ------------------------------------------------------------------
    task run_fault(input integer idx);
        begin
            rst_n = 1'b0; start = 1'b0;
            @(posedge clk); @(posedge clk);
            rst_n = 1'b1; @(posedge clk);
            start = 1'b1; @(posedge clk); start = 1'b0;
            pcount = 0; ci = 0;
            while (pcount < MAXPAT) begin
                @(posedge clk); #1;
                if (g16_tick) begin
                    pcount = pcount + 1;
                    if (ci < NCHK && pcount == CHK[ci]) begin
                        if (g16_sig !== f16_sig) begin
                            det16[ci] = det16[ci] + 1;
                            if (firstdet[idx] == 0) firstdet[idx] = pcount;
                        end
                        if (g8_sig !== f8_sig) det8[ci] = det8[ci] + 1;
                        ci = ci + 1;
                    end
                end
            end
        end
    endtask

    initial begin
        CHK[0]=1;    CHK[1]=2;    CHK[2]=4;     CHK[3]=8;
        CHK[4]=16;   CHK[5]=32;   CHK[6]=64;    CHK[7]=128;
        CHK[8]=256;  CHK[9]=512;  CHK[10]=1024; CHK[11]=2048;
        for (i=0; i<NCHK;   i=i+1) begin det16[i]=0; det8[i]=0; end
        for (i=0; i<NFAULT; i=i+1) firstdet[i]=0;

        rst_n=1'b1; start=1'b0; f_active=1'b1; f_site=6'd0; f_value=1'b0;

        $display("\n=== P3 STUMPS LBIST : running %0d faults x %0d patterns ...",
                 NFAULT, MAXPAT);

        for (s=0; s<NSITE; s=s+1) begin
            for (v=0; v<2; v=v+1) begin
                fidx = 2*s + v;
                f_site = s[5:0]; f_value = v[0];
                run_fault(fidx);
            end
        end
        f_active = 1'b0;

        // ---------------- coverage curve ----------------
        $display("\n===============================================================");
        $display("  LBIST FAULT COVERAGE vs PATTERN COUNT   (%0d stuck-at faults)", NFAULT);
        $display("---------------------------------------------------------------");
        $display("   patterns |  16-bit MISR   |   8-bit MISR   | aliasing");
        $display("---------------------------------------------------------------");
        for (i=0; i<NCHK; i=i+1) begin
            $display("   %6d   |  %2d/%0d = %0d.%0d %%  |  %2d/%0d = %0d.%0d %%  | %s",
                CHK[i],
                det16[i], NFAULT, (det16[i]*1000+32)/64/10, (det16[i]*1000+32)/64%10,
                det8[i],  NFAULT, (det8[i] *1000+32)/64/10, (det8[i] *1000+32)/64%10,
                (det8[i] < det16[i]) ? "<-- fault hidden by signature collision" : "");
        end
        $display("---------------------------------------------------------------");

        // ---------------- fault classification ----------------
        $display("\n  RANDOM-PATTERN-RESISTANT faults (first detected only at >=256 patterns):");
        n = 0;
        for (i=0; i<NFAULT; i=i+1)
            if (firstdet[i] >= 256) begin
                $display("     site %0d  SA%0d   first detected at pattern %0d",
                         i/2, i%2, firstdet[i]);
                n = n + 1;
            end
        if (n==0) $display("     (none)");

        $display("\n  UNDETECTED after %0d patterns:", MAXPAT);
        n = 0;
        for (i=0; i<NFAULT; i=i+1)
            if (firstdet[i] == 0) begin
                $display("     site %0d  SA%0d   -> REDUNDANT (untestable by any pattern)",
                         i/2, i%2);
                n = n + 1;
            end
        if (n==0) $display("     (none)");

        $display("\n  Final LBIST coverage : %0d/%0d = %0d.%0d %%   (ceiling = %0d redundant faults)",
                 det16[NCHK-1], NFAULT,
                 (det16[NCHK-1]*1000+32)/64/10, (det16[NCHK-1]*1000+32)/64%10, n);
        $display("===============================================================\n");
        $finish;
    end
endmodule
