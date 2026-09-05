`timescale 1ns/1ps

//======================================================================
//  D-ALGORITHM ATPG ENGINE  -  ISCAS-89 s27, FULL SCAN
//
//  This is tb_s27_datpg.sv with ONE change:  the behavioural
//  simulate() function is gone.  Every pattern is now applied to a real
//  instance of s27_scan_fi through the scan chain -
//
//      3 shift clocks  ->  apply PIs, strobe G17  ->  capture clock
//                      ->  3 shift clocks to unload G13,G11,G10
//
//  and the faulty response comes from a saboteur inside the DUT, not
//  from a second software model.  The engine itself is untouched.
//
//  compile : iverilog -g2012 -o atpg.out tb_s27_datpg_scan.sv s27_scan_fi.v
//            vvp atpg.out
//======================================================================

module tb_s27_datpg_2phase;

    localparam [2:0] V0 = 3'd0, V1 = 3'd1, VX = 3'd2, VD = 3'd3, VDB = 3'd4;
    localparam GAND = 0, GOR = 1, GNAND = 2, GNOR = 3, GNOT = 4, GBUF = 5;

    localparam NNETS  = 26;
    localparam NGATES = 19;
    localparam NPI    = 7;
    localparam NPO    = 4;

    integer gtype [0:NGATES-1];
    integer gin0  [0:NGATES-1];
    integer gin1  [0:NGATES-1];
    integer gout  [0:NGATES-1];
    integer pi_list [0:NPI-1];
    integer po_list [0:NPO-1];

    reg [2:0] val [0:NNETS-1];

    integer FAULT_NET;
    integer FAULT_SA;

    integer decisions, backtracks;
    integer VERBOSE;

    //==================================================================
    //  DUT + scan protocol  (this is what replaces simulate())
    //==================================================================
    reg  clk = 1'b0;
    reg  scan_en = 1'b0;
    reg  scan_in = 1'b0;
    reg  pG0 = 1'b0, pG1 = 1'b0, pG2 = 1'b0, pG3 = 1'b0;
    reg  fault_en = 1'b0;
    reg  [4:0] fault_net = 5'd0;
    reg  fault_val = 1'b0;
    wire dut_G17, dut_scan_out;

    always #5 clk = ~clk;

    s27_scan_fi dut (
        .clk(clk), .scan_en(scan_en), .scan_in(scan_in),
        .G0(pG0), .G1(pG1), .G2(pG2), .G3(pG3),
        .fault_en(fault_en), .fault_net(fault_net), .fault_val(fault_val),
        .G17(dut_G17), .scan_out(dut_scan_out)
    );

    reg tv [0:NPI-1];

    //  fnet < 0  ->  fault-free run
    task automatic apply_scan(input integer fnet, input integer fsa,
                              output reg [3:0] resp);
        integer i;
        reg g17_obs, g10_cap, g11_cap, g13_cap;
        begin
            if (fnet < 0) begin
                fault_en  = 1'b0;
                fault_net = 5'd0;
                fault_val = 1'b0;
            end
            else begin
                fault_en  = 1'b1;
                fault_net = fnet;
                fault_val = fsa[0];
            end

            // ---- LOAD : chain is scan_in -> SFF0(G5) -> SFF1(G6) -> SFF2(G7)
            //      so the first bit shifted in ends up in G7
            scan_en = 1'b1;
            for (i = 0; i < 3; i = i + 1) begin
                @(negedge clk);
                scan_in = tv[6 - i];        // G7, then G6, then G5
                @(posedge clk);
            end

            // ---- APPLY primary inputs, strobe the true PO
            @(negedge clk);
            scan_en = 1'b0;
            pG0 = tv[0]; pG1 = tv[1]; pG2 = tv[2]; pG3 = tv[3];
            #1;
            g17_obs = dut_G17;

            // ---- CAPTURE : G10->SFF0, G11->SFF1, G13->SFF2
            @(posedge clk);

            // ---- UNLOAD : scan_out is SFF2, so G13 comes out first
            @(negedge clk);
            scan_en = 1'b1;
            g13_cap = dut_scan_out;
            @(posedge clk); @(negedge clk);
            g11_cap = dut_scan_out;
            @(posedge clk); @(negedge clk);
            g10_cap = dut_scan_out;

            resp = {g17_obs, g10_cap, g11_cap, g13_cap};
            fault_en = 1'b0;
        end
    endtask

    //==================================================================
    //  5-valued algebra and the D-algorithm  (unchanged)
    //==================================================================
    function automatic [2:0] not5(input [2:0] a);
        case (a)
            V0:  not5 = V1;
            V1:  not5 = V0;
            VD:  not5 = VDB;
            VDB: not5 = VD;
            default: not5 = VX;
        endcase
    endfunction

    function automatic [2:0] and5(input [2:0] a, input [2:0] b);
        begin
            if (a == V0 || b == V0)      and5 = V0;
            else if (a == VX || b == VX) and5 = VX;
            else if (a == V1)            and5 = b;
            else if (b == V1)            and5 = a;
            else if (a == b)             and5 = a;
            else                         and5 = V0;
        end
    endfunction

    function automatic [2:0] or5(input [2:0] a, input [2:0] b);
        begin
            if (a == V1 || b == V1)      or5 = V1;
            else if (a == VX || b == VX) or5 = VX;
            else if (a == V0)            or5 = b;
            else if (b == V0)            or5 = a;
            else if (a == b)             or5 = a;
            else                         or5 = V1;
        end
    endfunction

    function automatic [2:0] noncrtl_val(input integer t);
        case (t)
            GAND, GNAND: noncrtl_val = V1;
            GOR,  GNOR:  noncrtl_val = V0;
            default:     noncrtl_val = VX;
        endcase
    endfunction

    function automatic [2:0] eval_gate(input integer g);
        reg [2:0] a, b;
        begin
            a = val[gin0[g]];
            b = (gin1[g] >= 0) ? val[gin1[g]] : VX;
            case (gtype[g])
                GAND:  eval_gate = and5(a, b);
                GOR:   eval_gate = or5 (a, b);
                GNAND: eval_gate = not5(and5(a, b));
                GNOR:  eval_gate = not5(or5 (a, b));
                GNOT:  eval_gate = not5(a);
                GBUF:  eval_gate = a;
                default: eval_gate = VX;
            endcase
        end
    endfunction

    function automatic [2:0] apply_fault(input [2:0] v);
        begin
            if (v == VX) apply_fault = VX;
            else if (FAULT_SA == 0) apply_fault = (v == V1) ? VD  : V0;
            else                    apply_fault = (v == V0) ? VDB : V1;
        end
    endfunction

    function automatic integer imply_and_check(input integer dummy);
        integer g, changed, iter, ok;
        reg [2:0] nv;
        begin
            ok = 1; changed = 1; iter = 0;
            while (changed && ok && iter < 64) begin
                changed = 0;
                iter = iter + 1;
                for (g = 0; g < NGATES; g = g + 1) begin
                    if (ok) begin
                        nv = eval_gate(g);
                        if (gout[g] == FAULT_NET) nv = apply_fault(nv);
                        if (nv != VX) begin
                            if (val[gout[g]] == VX) begin
                                val[gout[g]] = nv;
                                changed = 1;
                            end
                            else if (val[gout[g]] != nv) ok = 0;
                        end
                    end
                end
            end
            imply_and_check = ok;
        end
    endfunction

    function automatic integer dfrontier(input integer k);
        integer g, cnt;
        reg has_d;
        reg [2:0] a, b;
        begin
            dfrontier = -1;
            cnt = 0;
            for (g = 0; g < NGATES; g = g + 1) begin
                a = val[gin0[g]];
                b = (gin1[g] >= 0) ? val[gin1[g]] : V0;
                has_d = (a == VD) || (a == VDB) || (b == VD) || (b == VDB);
                if (val[gout[g]] == VX && has_d) begin
                    if (cnt == k) dfrontier = g;
                    cnt = cnt + 1;
                end
            end
        end
    endfunction

    function automatic integer jfrontier(input integer dummy);
        integer g;
        begin
            jfrontier = -1;
            for (g = NGATES - 1; g >= 0; g = g - 1)
                if (val[gout[g]] != VX && eval_gate(g) == VX)
                    jfrontier = g;
        end
    endfunction

    function automatic integer error_at_po(input integer dummy);
        integer i;
        begin
            error_at_po = 0;
            for (i = 0; i < NPO; i = i + 1)
                if (val[po_list[i]] == VD || val[po_list[i]] == VDB)
                    error_at_po = 1;
        end
    endfunction

    function automatic [15:0] vs(input [2:0] v);
        case (v)
            V0:  vs = "0";
            V1:  vs = "1";
            VX:  vs = "X";
            VD:  vs = "D";
            VDB: vs = "D'";
            default: vs = "?";
        endcase
    endfunction

    function automatic [63:0] nname(input integer n);
        case (n)
            0: nname="G0";       1: nname="G1";      2: nname="G2";
            3: nname="G3";       4: nname="G5";      5: nname="G6";
            6: nname="G7";       7: nname="G14";     8: nname="G14_b1";
            9: nname="G14_b2";  10: nname="G8";     11: nname="G8_b1";
           12: nname="G8_b2";   13: nname="G12";    14: nname="G12_b1";
           15: nname="G12_b2";  16: nname="G13";    17: nname="G15";
           18: nname="G16";     19: nname="G9";     20: nname="G11";
           21: nname="G11_b1";  22: nname="G11_b2"; 23: nname="G11_b3";
           24: nname="G10";     25: nname="G17";
           default: nname="?";
        endcase
    endfunction

    function automatic integer dalg(input integer depth);
        integer g, i, k, ok, done, combo, ncombo, res;
        reg [2:0] save [0:NNETS-1];
        reg [2:0] want, va, vb;
        begin
            dalg = 0;
            done = 0;

            if (depth > 60) done = 1;

            if (!done && imply_and_check(0) == 0) begin
                if (VERBOSE) $display("   [d=%0d] implication CONFLICT -> backtrack", depth);
                backtracks = backtracks + 1;
                done = 1;
            end

            if (!done && !error_at_po(0)) begin
                k = 0;
                if (dfrontier(0) == -1) begin
                    if (VERBOSE) $display("   [d=%0d] D-frontier EMPTY -> backtrack", depth);
                    backtracks = backtracks + 1;
                    done = 1;
                end
                while (!done && dfrontier(k) != -1) begin
                    g    = dfrontier(k);
                    want = noncrtl_val(gtype[g]);
                    if (want == VX) begin
                        k = k + 1;
                    end
                    else begin
                        for (i = 0; i < NNETS; i = i + 1) save[i] = val[i];
                        if (VERBOSE)
                            $display("   [d=%0d] D-DRIVE gate %0d (out %0s) side inputs = %0s",
                                     depth, g, nname(gout[g]), vs(want));
                        decisions = decisions + 1;
                        if (val[gin0[g]] == VX) val[gin0[g]] = want;
                        if (gin1[g] >= 0 && val[gin1[g]] == VX) val[gin1[g]] = want;
                        res = dalg(depth + 1);
                        if (res) begin dalg = 1; done = 1; end
                        else begin
                            for (i = 0; i < NNETS; i = i + 1) val[i] = save[i];
                            k = k + 1;
                        end
                    end
                end
                if (!done) done = 1;
            end

            else if (!done) begin
                g = jfrontier(0);
                if (g == -1) begin
                    if (VERBOSE) $display("   [d=%0d] J-frontier empty -> TEST FOUND", depth);
                    dalg = 1;
                    done = 1;
                end
                else begin
                    if (VERBOSE)
                        $display("   [d=%0d] JUSTIFY gate %0d (out %0s = %0s)",
                                 depth, g, nname(gout[g]), vs(val[gout[g]]));
                    ncombo = (gin1[g] >= 0) ? 4 : 2;
                    combo  = 0;
                    while (!done && combo < ncombo) begin
                        for (i = 0; i < NNETS; i = i + 1) save[i] = val[i];
                        va = combo[0] ? V1 : V0;
                        vb = combo[1] ? V1 : V0;
                        ok = 1;
                        if (val[gin0[g]] == VX)          val[gin0[g]] = va;
                        else if (val[gin0[g]] != va)     ok = 0;
                        if (gin1[g] >= 0) begin
                            if (val[gin1[g]] == VX)      val[gin1[g]] = vb;
                            else if (val[gin1[g]] != vb) ok = 0;
                        end
                        if (ok) begin
                            decisions = decisions + 1;
                            res = dalg(depth + 1);
                            if (res) begin dalg = 1; done = 1; end
                        end
                        if (!done) begin
                            for (i = 0; i < NNETS; i = i + 1) val[i] = save[i];
                            combo = combo + 1;
                        end
                    end
                    if (!done) backtracks = backtracks + 1;
                end
            end
        end
    endfunction

    //==================================================================
    integer i, n, sa, ok, ndet, nred, nbad;
    integer tot_dec, tot_bt;
    integer f, nf;
    reg [3:0] rg, rf;

    //  results of PHASE 1, consumed by PHASE 2
    reg [6:0] pat      [0:2*NNETS-1];   // the 7-bit test vector
    reg       testable [0:2*NNETS-1];   // 0 = redundant, no pattern
    integer   dec_of   [0:2*NNETS-1];
    integer   bt_of    [0:2*NNETS-1];

    initial begin
        gtype[ 0]=GNOT;  gin0[ 0]= 0; gin1[ 0]=-1; gout[ 0]= 7;
        gtype[ 1]=GBUF;  gin0[ 1]= 7; gin1[ 1]=-1; gout[ 1]= 8;
        gtype[ 2]=GBUF;  gin0[ 2]= 7; gin1[ 2]=-1; gout[ 2]= 9;
        gtype[ 3]=GAND;  gin0[ 3]= 8; gin1[ 3]= 5; gout[ 3]=10;
        gtype[ 4]=GBUF;  gin0[ 4]=10; gin1[ 4]=-1; gout[ 4]=11;
        gtype[ 5]=GBUF;  gin0[ 5]=10; gin1[ 5]=-1; gout[ 5]=12;
        gtype[ 6]=GNOR;  gin0[ 6]= 1; gin1[ 6]= 6; gout[ 6]=13;
        gtype[ 7]=GBUF;  gin0[ 7]=13; gin1[ 7]=-1; gout[ 7]=14;
        gtype[ 8]=GBUF;  gin0[ 8]=13; gin1[ 8]=-1; gout[ 8]=15;
        gtype[ 9]=GNOR;  gin0[ 9]= 2; gin1[ 9]=15; gout[ 9]=16;
        gtype[10]=GOR;   gin0[10]=14; gin1[10]=11; gout[10]=17;
        gtype[11]=GOR;   gin0[11]= 3; gin1[11]=12; gout[11]=18;
        gtype[12]=GNAND; gin0[12]=18; gin1[12]=17; gout[12]=19;
        gtype[13]=GNOR;  gin0[13]= 4; gin1[13]=19; gout[13]=20;
        gtype[14]=GBUF;  gin0[14]=20; gin1[14]=-1; gout[14]=21;
        gtype[15]=GBUF;  gin0[15]=20; gin1[15]=-1; gout[15]=22;
        gtype[16]=GBUF;  gin0[16]=20; gin1[16]=-1; gout[16]=23;
        gtype[17]=GNOR;  gin0[17]= 9; gin1[17]=21; gout[17]=24;
        gtype[18]=GNOT;  gin0[18]=22; gin1[18]=-1; gout[18]=25;

        pi_list[0]=0; pi_list[1]=1; pi_list[2]=2; pi_list[3]=3;
        pi_list[4]=4; pi_list[5]=5; pi_list[6]=6;

        po_list[0]=25;   // G17  (true PO, strobed combinationally)
        po_list[1]=24;   // G10  (PPO, unloaded from SFF0)
        po_list[2]=23;   // G11  (PPO, unloaded from SFF1)
        po_list[3]=16;   // G13  (PPO, unloaded from SFF2)

        ndet = 0; nred = 0; nbad = 0; tot_dec = 0; tot_bt = 0;

        $display("");
        $display("======================================================================");
        $display("  D-ALGORITHM ATPG  -  s27 full scan  (patterns applied via scan)");
        $display("  PI/PPI order : G0 G1 G2 G3 G5 G6 G7");
        $display("  Observed at  : G17(PO strobe) G10 G11 G13 (scan unload)");
        $display("======================================================================");

        VERBOSE = 1;
        FAULT_NET = 3; FAULT_SA = 0;
        for (i = 0; i < NNETS; i = i + 1) val[i] = VX;
        val[FAULT_NET] = VD;
        decisions = 0; backtracks = 0;
        $display("  search trace for %0s stuck-at-0 :", nname(FAULT_NET));
        ok = dalg(0);
        $display("  -> decisions %0d, backtracks %0d", decisions, backtracks);
        VERBOSE = 0;

        //==============================================================
        //  PHASE 1  -  ATPG only.  D-algorithm for all 52 faults.
        //  No DUT, no clock, no simulation time.  (stages 1-5)
        //==============================================================
        $display("");
        $display("======================================================================");
        $display("  PHASE 1 : D-ALGORITHM  -  test pattern generation");
        $display("  no DUT involved, pure symbolic search in 5-valued logic");
        $display("----------------------------------------------------------------------");
        $display("     fault      G0 G1 G2 G3 G5 G6 G7     decisions/backtracks");
        $display("----------------------------------------------------------------------");

        for (n = 0; n < NNETS; n = n + 1) begin
            for (sa = 0; sa < 2; sa = sa + 1) begin
                f = 2*n + sa;
                FAULT_NET = n;
                FAULT_SA  = sa;
                for (i = 0; i < NNETS; i = i + 1) val[i] = VX;
                val[n] = (sa == 0) ? VD : VDB;
                decisions = 0; backtracks = 0;

                ok = dalg(0);

                dec_of[f] = decisions;
                bt_of [f] = backtracks;

                if (!ok) begin
                    testable[f] = 1'b0;
                    pat[f]      = 7'b0;
                    nred = nred + 1;
                    $display("  %-9s/%0d  UNTESTABLE (redundant)", nname(n), sa);
                end
                else begin
                    testable[f] = 1'b1;
                    for (i = 0; i < NPI; i = i + 1)
                        pat[f][6-i] = (val[pi_list[i]] == V1 || val[pi_list[i]] == VD)
                                      ? 1'b1 : 1'b0;
                    tot_dec = tot_dec + decisions;
                    tot_bt  = tot_bt  + backtracks;
                    $display("  %-9s/%0d  %b  %b  %b  %b  %b  %b  %b       %0d/%0d",
                             nname(n), sa,
                             pat[f][6],pat[f][5],pat[f][4],pat[f][3],
                             pat[f][2],pat[f][1],pat[f][0],
                             decisions, backtracks);
                end
            end
        end

        $display("----------------------------------------------------------------------");
        $display("  patterns generated : %0d of %0d faults   (redundant %0d)",
                 2*NNETS - nred, 2*NNETS, nred);
        $display("  total decisions %0d, total backtracks %0d", tot_dec, tot_bt);
        $display("======================================================================");

        //==============================================================
        //  PHASE 2  -  apply every pattern to the real DUT through the
        //  scan chain.  Golden run first, then saboteur.  (stages 6-8)
        //==============================================================
        $display("");
        $display("======================================================================");
        $display("  PHASE 2 : SCAN APPLICATION  -  golden vs faulty on the DUT");
        $display("  3 shift clocks -> apply PI, strobe G17 -> capture -> 3 shift clocks");
        $display("----------------------------------------------------------------------");
        $display("     fault      pattern    golden   faulty    verdict");
        $display("                          G17/G10/G11/G13");
        $display("----------------------------------------------------------------------");

        for (n = 0; n < NNETS; n = n + 1) begin
            for (sa = 0; sa < 2; sa = sa + 1) begin
                f = 2*n + sa;
                if (testable[f]) begin
                    for (i = 0; i < NPI; i = i + 1) tv[i] = pat[f][6-i];

                    apply_scan(-1, 0,  rg);
                    apply_scan( n, sa, rf);

                    if (rg !== rf) ndet = ndet + 1;
                    else           nbad = nbad + 1;

                    $display("  %-9s/%0d  %b   %b     %b     %-12s",
                             nname(n), sa, pat[f], rg, rf,
                             (rg !== rf) ? "DETECTED" : "*** MISS ***");
                end
            end
        end

        $display("----------------------------------------------------------------------");
        $display("  fault sites  : %0d", NNETS);
        $display("  total faults : %0d", 2*NNETS);
        $display("  patterns app.: %0d", 2*NNETS - nred);
        $display("  detected     : %0d  (measured on the DUT through the scan chain)", ndet);
        $display("  redundant    : %0d", nred);
        $display("  BAD PATTERNS : %0d", nbad);
        $display("  coverage     : %0d.%02d %%",
                 (100*ndet)/(2*NNETS),
                 ((10000*ndet)/(2*NNETS)) % 100);
        $display("======================================================================");
        $display("");
        $finish;
    end

endmodule
