// ============================================================================
//  P1 : Full-Scan DFT + Single Stuck-at Fault Coverage
//  FILE 1/2 :  DESIGN UNDER TEST (synthesizable)
// ----------------------------------------------------------------------------
//  A small datapath:  4-bit accumulator ALU (ADD/SUB/AND/OR) + a 2-bit
//  operation counter + a 6-bit INTERNAL STATUS register.
//
//  * Only  acc_out[3:0]  is a primary (pin) output  -> the datapath is
//    functionally observable.
//  * The 6-bit status register drives NOTHING functionally: its bits are
//    "buried" nodes, observable ONLY by scanning them out.  This is the
//    classic observability problem that scan design exists to solve.
//
//  parameter SCAN :
//      0 -> BASELINE   : plain D flip-flops, no scan chain  ("before DFT")
//      1 -> FULL-SCAN  : every FF is a muxed-D scan cell on one scan chain
//                        ("after DFT")   scan order (scan_in -> scan_out):
//                        acc0,acc1,acc2,acc3, opcnt0,opcnt1, st0..st5
//
//  FAULT INJECTION ("saboteur" technique, for simulation only):
//      f_active=1 forces the single net selected by f_site[5:0] to the
//      constant f_value (0 = stuck-at-0, 1 = stuck-at-1).  29 fault sites,
//      SA0+SA1 => 58 single stuck-at faults.  f_active=0 = fault-free.
// ============================================================================
module dft_dut #(parameter SCAN = 0) (
    input             clk,
    input             rst_n,
    // functional primary inputs
    input      [1:0]  opcode,     // 00=ADD 01=SUB 10=AND 11=OR
    input      [3:0]  data_in,
    // functional primary output
    output     [3:0]  acc_out,
    // scan interface (used only when SCAN==1)
    input             scan_en,    // 1 = shift, 0 = normal/capture
    input             scan_in,
    output            scan_out,
    // fault-injection interface (simulation DFT experiment only)
    input             f_active,
    input      [5:0]  f_site,
    input             f_value
);
    // --- saboteur helper : force net ID to f_value when selected ------------
    `define SAB(ID,RAW) ((f_active && (f_site == (ID))) ? f_value : (RAW))

    // 12 state bits : [3:0]=acc  [5:4]=opcnt  [11:6]=status
    reg  [11:0] state;
    wire [3:0]  acc_q  = state[3:0];
    wire [1:0]  opc_q  = state[5:4];

    // ---- faulted reads of primary inputs (sites 0..5) ----------------------
    wire [3:0] din_f;
    assign din_f[0] = `SAB(0, data_in[0]);
    assign din_f[1] = `SAB(1, data_in[1]);
    assign din_f[2] = `SAB(2, data_in[2]);
    assign din_f[3] = `SAB(3, data_in[3]);
    wire [1:0] op_f;
    assign op_f[0]  = `SAB(4, opcode[0]);
    assign op_f[1]  = `SAB(5, opcode[1]);

    // ---- faulted reads of accumulator / opcnt Q nets (sites 20..25) --------
    wire [3:0] acc_qf;
    assign acc_qf[0] = `SAB(20, acc_q[0]);
    assign acc_qf[1] = `SAB(21, acc_q[1]);
    assign acc_qf[2] = `SAB(22, acc_q[2]);
    assign acc_qf[3] = `SAB(23, acc_q[3]);
    wire [1:0] opc_qf;
    assign opc_qf[0] = `SAB(24, opc_q[0]);
    assign opc_qf[1] = `SAB(25, opc_q[1]);

    // ---- ALU ---------------------------------------------------------------
    wire [4:0] add5 = acc_qf + din_f;          // 5-bit : bit4 = carry-out
    wire [4:0] sub5 = acc_qf - din_f;          // 5-bit : bit4 = borrow
    reg  [3:0] base;
    reg        cout_raw;
    always @* begin
        case (op_f)
            2'b00: begin base = add5[3:0];        cout_raw = add5[4]; end
            2'b01: begin base = sub5[3:0];        cout_raw = sub5[4]; end
            2'b10: begin base = acc_qf & din_f;   cout_raw = 1'b0;    end
            default:begin base = acc_qf | din_f;  cout_raw = 1'b0;    end
        endcase
    end

    // ---- "special" every-4th-op +1 (opcnt reaches 3) -----------------------
    wire       special  = `SAB(12, &opc_qf);
    wire [3:0] plus_raw  = base + 4'd1;
    wire       plus0     = `SAB(13, plus_raw[0]);
    wire [3:0] plus      = {plus_raw[3:1], plus0};
    wire [3:0] sel_pre   = special ? plus : base;
    wire       sel3      = `SAB(27, sel_pre[3]);
    wire [3:0] sel       = {sel3, sel_pre[2:0]};

    // ---- REDUNDANT reconvergent cone on acc_d[0] ---------------------------
    //   rr = (s0 & g) | (s0 & ~g) == s0  for all g, so a stuck-at on g
    //   (site 28) can NEVER change rr -> provably UNTESTABLE (redundant) fault.
    wire s0 = sel[0];
    wire g  = `SAB(28, opc_qf[0]);
    wire rr = (s0 & g) | (s0 & ~g);

    // ---- next-state (D) nets, with saboteurs (sites 6..11, 14..19, 26) -----
    wire [3:0] acc_d;
    assign acc_d[0] = `SAB(6, rr);
    assign acc_d[1] = `SAB(7, sel[1]);
    assign acc_d[2] = `SAB(8, sel[2]);
    assign acc_d[3] = `SAB(9, sel[3]);

    wire [1:0] opcn = opc_qf + 2'd1;
    wire [1:0] opc_d;
    assign opc_d[0] = `SAB(10, opcn[0]);
    assign opc_d[1] = `SAB(11, opcn[1]);

    wire cout = `SAB(26, cout_raw);

    // buried status conditions
    wire st0 = `SAB(14, (sel == 4'd0));   // result is zero
    wire st1 = `SAB(15, sel[3]);          // result MSB
    wire st2 = `SAB(16, ^sel);            // result parity
    wire st3 = `SAB(17, cout);            // carry / borrow
    wire st4 = `SAB(18, sel[0]);          // result LSB
    wire st5 = `SAB(19, op_f[1]);         // opcode high bit latched

    // functional next-state vector, matching scan order
    wire [11:0] d_func =
        { st5, st4, st3, st2, st1, st0, opc_d[1], opc_d[0],
          acc_d[3], acc_d[2], acc_d[1], acc_d[0] };

    // ---- the flip-flops : baseline vs full-scan ----------------------------
    generate
    if (SCAN == 1) begin : g_scan
        always @(posedge clk or negedge rst_n)
            if (!rst_n)        state <= 12'd0;
            else if (scan_en)  state <= {state[10:0], scan_in}; // shift, in->bit0
            else               state <= d_func;                 // capture
    end
    else begin : g_base
        always @(posedge clk or negedge rst_n)
            if (!rst_n) state <= 12'd0;
            else        state <= d_func;                        // scan_* ignored
    end
    endgenerate

    // ---- outputs -----------------------------------------------------------
    assign acc_out  = acc_qf;      // faulted acc Q net drives the pins
    assign scan_out = state[11];   // top of scan chain (status bit 5)

    `undef SAB
endmodule
