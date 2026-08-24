// ============================================================================
//  P3 : Logic BIST (STUMPS)   -   FILE 1/3 : Circuit Under Test
// ----------------------------------------------------------------------------
//  The same style of datapath as P1, but re-organised for STUMPS:
//  the 12 flip-flops are split into TWO parallel scan chains of 6 cells each
//  (STUMPS = Self-Test Using MISR and Parallel Shift-register sequence
//   generator), so the PRPG fills both chains at once and the MISR compacts
//   both chain outputs at once.
//
//      chain A (6) : acc[0..3] , opcnt[0..1]      <- functional datapath
//      chain B (6) : status[0..5]                 <- internal status bits
//
//  Deliberately embedded, so LBIST behaviour is realistic:
//   * FOUR "rarely asserted" nodes  rA (1/64), rB (1/256), rC (1/1024),
//     rD (1/4096).  A stuck-at-0 on such a node is only sensitised when the
//     node should be 1 -> RANDOM-PATTERN-RESISTANT: pseudo-random patterns
//     need thousands of vectors to catch it.  This creates LBIST's classic
//     long coverage tail.
//   * ONE structurally REDUNDANT reconvergent cone (site 29):
//     rr = (s0 & g) | (s0 & ~g) == s0, so a fault on g is UNTESTABLE by any
//     pattern -> the hard coverage ceiling.
//
//  Fault injection: saboteur macro, 32 sites x SA0/SA1 = 64 single stuck-at
//  faults.  f_active=0 gives the fault-free circuit.
// ============================================================================
module lbist_cut (
    input             clk,
    input             rst_n,
    // scan / test interface
    input             scan_en,      // 1 = shift both chains
    input             cap_en,       // 1 = functional capture (ignored if scan_en)
    input             sa_in,        // chain A serial input  (from PRPG)
    input             sb_in,        // chain B serial input  (from PRPG)
    output            sa_out,       // chain A serial output (to MISR)
    output            sb_out,       // chain B serial output (to MISR)
    // functional primary inputs, driven by the PRPG during capture
    input      [1:0]  pi_op,
    input      [3:0]  pi_din,
    // functional primary output
    output     [3:0]  acc_out,
    // fault injection (simulation only)
    input             f_active,
    input      [5:0]  f_site,
    input             f_value
);
    `define SAB(ID,RAW) ((f_active && (f_site == (ID))) ? f_value : (RAW))

    // ---- the two scan chains ----------------------------------------------
    //  index 0 = serial input end , index 5 = serial output end
    reg [5:0] chainA;   // {opc1,opc0,acc3,acc2,acc1,acc0}
    reg [5:0] chainB;   // {st5,st4,st3,st2,st1,st0}

    assign sa_out = chainA[5];
    assign sb_out = chainB[5];

    // ---- faulted reads of primary inputs (sites 0..5) ----------------------
    wire [3:0] din_f;
    assign din_f[0] = `SAB(0, pi_din[0]);
    assign din_f[1] = `SAB(1, pi_din[1]);
    assign din_f[2] = `SAB(2, pi_din[2]);
    assign din_f[3] = `SAB(3, pi_din[3]);
    wire [1:0] op_f;
    assign op_f[0]  = `SAB(4, pi_op[0]);
    assign op_f[1]  = `SAB(5, pi_op[1]);

    // ---- faulted reads of state (sites 18..23) -----------------------------
    wire [3:0] acc_qf;
    assign acc_qf[0] = `SAB(18, chainA[0]);
    assign acc_qf[1] = `SAB(19, chainA[1]);
    assign acc_qf[2] = `SAB(20, chainA[2]);
    assign acc_qf[3] = `SAB(21, chainA[3]);
    wire [1:0] opc_qf;
    assign opc_qf[0] = `SAB(22, chainA[4]);
    assign opc_qf[1] = `SAB(23, chainA[5]);

    // ---- ALU ---------------------------------------------------------------
    wire [4:0] add5 = acc_qf + din_f;
    reg  [3:0] base;
    reg        cout_raw;
    always @* begin
        case (op_f)
            2'b00: begin base = add5[3:0];            cout_raw = add5[4];              end
            2'b01: begin base = acc_qf - din_f;       cout_raw = (acc_qf < din_f);     end
            2'b10: begin base = acc_qf & din_f;       cout_raw = 1'b0;                 end
            default:begin base = acc_qf | din_f;      cout_raw = 1'b0;                 end
        endcase
    end
    wire cout = `SAB(24, cout_raw);

    // ---- rarely-asserted nodes -> random-pattern-resistant faults ----------
    wire hi = (acc_qf == 4'hF) && (opc_qf == 2'b11);              // 1/64
    wire rA = `SAB(25, hi);                                       // 1/64
    wire rB = `SAB(26, hi && (din_f[1:0] == 2'b11));              // 1/256
    wire rC = `SAB(27, hi && (din_f == 4'hF));                    // 1/1024
    wire rD = `SAB(30, hi && (din_f == 4'hF) && chainB[0] && chainB[1]); // 1/4096

    // ---- result select -----------------------------------------------------
    wire       special = `SAB(28, &opc_qf);
    wire [3:0] plus    = base + 4'd1;
    wire [3:0] pre     = special ? plus : base;

    wire s0 = pre[0];
    wire s1 = pre[1] ^ rA;
    wire s2 = pre[2] ^ rB;
    wire s3 = `SAB(31, pre[3] ^ rD);

    // ---- REDUNDANT reconvergent cone (site 29) : rr == s0 always -----------
    wire g  = `SAB(29, opc_qf[0]);
    wire rr = (s0 & g) | (s0 & ~g);

    wire [3:0] acc_d;
    assign acc_d[0] = `SAB(6, rr);
    assign acc_d[1] = `SAB(7, s1);
    assign acc_d[2] = `SAB(8, s2);
    assign acc_d[3] = `SAB(9, s3);

    wire [1:0] opcn = opc_qf + 2'd1;
    wire [1:0] opc_d;
    assign opc_d[0] = `SAB(10, opcn[0]);
    assign opc_d[1] = `SAB(11, opcn[1]);

    wire [3:0] sel = {s3, s2, s1, s0};

    // ---- status (chain B) next state (sites 12..17) ------------------------
    wire st_d0 = `SAB(12, (sel == 4'd0));
    wire st_d1 = `SAB(13, s3 ^ rC);
    wire st_d2 = `SAB(14, ^sel);
    wire st_d3 = `SAB(15, cout);
    wire st_d4 = `SAB(16, s0);
    wire st_d5 = `SAB(17, op_f[1]);

    // ---- flip-flops : shift (scan) or capture ------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chainA <= 6'd0;
            chainB <= 6'd0;
        end else if (scan_en) begin
            chainA <= {chainA[4:0], sa_in};      // new bit enters at index 0
            chainB <= {chainB[4:0], sb_in};
        end else if (cap_en) begin
            chainA <= {opc_d[1], opc_d[0], acc_d[3], acc_d[2], acc_d[1], acc_d[0]};
            chainB <= {st_d5, st_d4, st_d3, st_d2, st_d1, st_d0};
        end
        // else: hold (engine idle) - no spurious captures before the test starts
    end

    // faulted accumulator drives the primary output
    assign acc_out = acc_qf;

    `undef SAB
endmodule
