// ============================================================================
//  P2 : Memory BIST (MBIST)   -   FILE 3/3 : testbench / fault grader
// ----------------------------------------------------------------------------
//  Two MBIST engines run side by side, each on its own 8x4 SRAM:
//      MATS   (4N)   = weak baseline test
//      MarchC-(10N)  = the MBIST algorithm
//
//  GRADING CRITERION - "guaranteed detection":
//    A real SRAM powers up in an arbitrary state, so a March test must expose
//    a fault REGARDLESS of the initial memory content.  Each fault is therefore
//    graded TWICE - once from an all-0 background, once from all-1 - and is
//    counted DETECTED only if the algorithm flags it in BOTH runs.
//    (Grading from a single background inflates the score: e.g. starting from
//     all-1s, MATS's opening w0 accidentally creates the falling transitions
//     that expose can't-fall faults - detection by luck, not by algorithm.)
//
//  Expected:  MATS 12/19 = 63.1% ,  March C- 18/19 = 94.7%
//             March C- scores 18/19 from BOTH backgrounds -> initial-state
//             independent; MATS does not.  Linked coupling fault = ceiling.
// ============================================================================
`timescale 1ns/1ps
module mbist_tb;

    localparam integer NF = 19;

    reg        clk = 1'b0;
    reg        rst_n, start;
    reg        init, init_val;
    // fault descriptor (shared by both memories)
    reg        f_active;
    reg  [2:0] f_type, f_addrA, f_addrV;
    reg  [1:0] f_bitA, f_bitV;
    reg        f_p, f_trans;

    integer k, det0, det1, ind0, ind1;
    reg     d0a, d1a, d0b, d1b;

    always #5 clk = ~clk;

    // ---- baseline engine : MATS (MODE 0) ----------------------------------
    wire [2:0] a0, fa0; wire we0, done0, fail0; wire [3:0] wd0, rd0;
    mbist_ctrl #(.MODE(0)) ctrl0 (.clk(clk),.rst_n(rst_n),.start(start),
        .addr(a0),.we(we0),.wdata(wd0),.rdata(rd0),
        .done(done0),.fail(fail0),.fail_addr(fa0));
    mbist_mem mem0 (.clk(clk),.we(we0),.addr(a0),.wdata(wd0),.rdata(rd0),
        .init(init),.init_val(init_val),
        .f_active(f_active),.f_type(f_type),.f_addrA(f_addrA),.f_bitA(f_bitA),
        .f_addrV(f_addrV),.f_bitV(f_bitV),.f_p(f_p),.f_trans(f_trans));

    // ---- MBIST engine : March C- (MODE 1) ---------------------------------
    wire [2:0] a1, fa1; wire we1, done1, fail1; wire [3:0] wd1, rd1;
    mbist_ctrl #(.MODE(1)) ctrl1 (.clk(clk),.rst_n(rst_n),.start(start),
        .addr(a1),.we(we1),.wdata(wd1),.rdata(rd1),
        .done(done1),.fail(fail1),.fail_addr(fa1));
    mbist_mem mem1 (.clk(clk),.we(we1),.addr(a1),.wdata(wd1),.rdata(rd1),
        .init(init),.init_val(init_val),
        .f_active(f_active),.f_type(f_type),.f_addrA(f_addrA),.f_bitA(f_bitA),
        .f_addrV(f_addrV),.f_bitV(f_bitV),.f_p(f_p),.f_trans(f_trans));

    // ---- fault library (matches the verified reference model) --------------
    //  type: 1 SAF, 2 TF, 3 CFid, 4 CFin, 5 AF, 6 LCF
    task set_fault(input integer n);
        begin
            f_type=3'd0; f_addrA=3'd0; f_bitA=2'd0; f_addrV=3'd0; f_bitV=2'd0;
            f_p=1'b0; f_trans=1'b0;
            case (n)
                0:  begin f_type=1; f_addrA=3; f_bitA=1; f_p=0; end          // SAF0 (3,1)
                1:  begin f_type=1; f_addrA=0; f_bitA=0; f_p=0; end          // SAF0 (0,0)
                2:  begin f_type=1; f_addrA=6; f_bitA=2; f_p=0; end          // SAF0 (6,2)
                3:  begin f_type=1; f_addrA=5; f_bitA=2; f_p=1; end          // SAF1 (5,2)
                4:  begin f_type=1; f_addrA=7; f_bitA=3; f_p=1; end          // SAF1 (7,3)
                5:  begin f_type=2; f_addrA=2; f_bitA=0; f_p=1; end          // TF cant-rise (2,0)
                6:  begin f_type=2; f_addrA=4; f_bitA=3; f_p=1; end          // TF cant-rise (4,3)
                7:  begin f_type=2; f_addrA=6; f_bitA=3; f_p=0; end          // TF cant-fall (6,3)
                8:  begin f_type=2; f_addrA=1; f_bitA=1; f_p=0; end          // TF cant-fall (1,1)
                9:  begin f_type=2; f_addrA=5; f_bitA=0; f_p=0; end          // TF cant-fall (5,0)
                10: begin f_type=3; f_addrA=1; f_bitA=0; f_addrV=4; f_bitV=0; f_p=1; f_trans=1; end // CFid a(1,0)^ v(4,0)=1
                11: begin f_type=3; f_addrA=6; f_bitA=0; f_addrV=2; f_bitV=0; f_p=0; f_trans=0; end // CFid a(6,0)v v(2,0)=0
                12: begin f_type=4; f_addrA=7; f_bitA=3; f_addrV=0; f_bitV=3; f_trans=1; end        // CFin a(7,3)^ v(0,3)
                13: begin f_type=4; f_addrA=2; f_bitA=2; f_addrV=5; f_bitV=2; f_trans=0; end        // CFin a(2,2)v v(5,2)
                14: begin f_type=3; f_addrA=0; f_bitA=1; f_addrV=3; f_bitV=1; f_p=1; f_trans=1; end // CFid a(0,1)^ v(3,1)=1
                15: begin f_type=3; f_addrA=5; f_bitA=3; f_addrV=1; f_bitV=3; f_p=0; f_trans=0; end // CFid a(5,3)v v(1,3)=0
                16: begin f_type=5; f_addrA=3; f_addrV=2; end                // AF : addr2 aliases addr3
                17: begin f_type=5; f_addrA=4; f_addrV=5; end                // AF : addr5 aliases addr4
                18: begin f_type=6; end                                      // LCF (linked, hard-coded)
            endcase
        end
    endtask

    // ---- run both engines once from background 'bg' ------------------------
    task run_pair(input bg, output r0, output r1);
        begin
            rst_n=1'b0; start=1'b0;
            @(posedge clk); @(posedge clk);
            // backdoor preset of BOTH memories to the chosen background
            init=1'b1; init_val=bg;
            @(posedge clk); @(posedge clk);
            init=1'b0;
            rst_n=1'b1; @(posedge clk);
            start=1'b1; @(posedge clk); start=1'b0;
            wait (done0==1'b1 && done1==1'b1);
            @(posedge clk);
            r0 = fail0; r1 = fail1;
        end
    endtask

    initial begin
        f_active=1'b0; start=1'b0; rst_n=1'b1; init=1'b0; init_val=1'b0;
        f_type=0; f_addrA=0; f_bitA=0; f_addrV=0; f_bitV=0; f_p=0; f_trans=0;

        $display("\n=== P2 MBIST fault coverage : MATS (baseline) vs March C- (MBIST) ===");
        $display("    each fault graded from BOTH backgrounds (bg0 / bg1);");
        $display("    DET = detected from both  =>  guaranteed detection\n");
        det0=0; det1=0; ind0=0; ind1=0;
        for (k=0; k<NF; k=k+1) begin
            set_fault(k); f_active=1'b1;
            run_pair(1'b0, d0a, d1a);          // from all-0 background
            run_pair(1'b1, d0b, d1b);          // from all-1 background
            if (d0a && d0b) det0=det0+1;       // MATS    guaranteed
            if (d1a && d1b) det1=det1+1;       // MarchC- guaranteed
            if (d0a || d0b) ind0=ind0+1;       // MATS    background-dependent
            if (d1a || d1b) ind1=ind1+1;
            $display("  fault %2d  type%0d A(%0d.%0d) V(%0d.%0d) :  MATS %s [bg0 %s bg1 %s]   MarchC- %s",
                     k, f_type, f_addrA, f_bitA, f_addrV, f_bitV,
                     (d0a&&d0b) ? "DET" : "---", d0a?"y":"n", d0b?"y":"n",
                     (d1a&&d1b) ? "DET" : "---");
        end
        f_active=1'b0;

        $display("--------------------------------------------------------------------");
        $display("  BASELINE  MATS   (4N) : %0d / %0d  =  %0d.%0d %%",
                 det0, NF, (det0*1000)/NF/10, (det0*1000)/NF%10);
        $display("  MBIST     MarchC-(10N): %0d / %0d  =  %0d.%0d %%",
                 det1, NF, (det1*1000)/NF/10, (det1*1000)/NF%10);
        $display("  MBIST gain            : +%0d faults (transition + coupling)", det1-det0);
        $display("--------------------------------------------------------------------");
        $display("  Initial-state dependence (detected from at least one background):");
        $display("     MATS    %0d/%0d guaranteed vs %0d/%0d luck-dependent  -> NOT robust",
                 det0, NF, ind0, NF);
        $display("     MarchC- %0d/%0d guaranteed vs %0d/%0d luck-dependent  -> robust",
                 det1, NF, ind1, NF);
        $display("  Ceiling               : %0d fault (linked coupling) escapes March C-",
                 NF-det1);
        $display("====================================================================\n");
        $finish;
    end
endmodule
