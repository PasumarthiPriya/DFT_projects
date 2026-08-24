// ============================================================================
//  P3 : Logic BIST (STUMPS)   -   FILE 2/3 : on-chip BIST engine
// ----------------------------------------------------------------------------
//  This is the self-test hardware.  No ATE, no stored patterns:
//
//    PRPG  : 16-bit maximal-length LFSR (x^16+x^14+x^13+x^11+1) generating
//            pseudo-random test data on chip.
//    PHASE : XOR phase shifter taps the LFSR at different points to produce
//            SHIFTER  decorrelated fill bits for the two scan chains
//            (adjacent LFSR bits are shifted copies of each other, which would
//             otherwise make the two chains highly correlated).
//    MISR  : Multiple-Input Signature Register - compacts the whole response
//            stream into one signature word.  A faulty chip yields a different
//            signature.  Width is a parameter so the testbench can show
//            SIGNATURE ALIASING (a narrow MISR can collide a faulty signature
//            back onto the good one, hiding a fault).
//    FSM   : per test pattern -> 6 SHIFT cycles (fill chains / unload previous
//            response into the MISR), then 1 CAPTURE cycle (functional clock).
//
//  pat_tick pulses for one cycle each time a pattern completes, so the
//  testbench can sample the signature at chosen pattern counts.
// ============================================================================
module lbist_engine #(
    parameter MISR_W  = 16,
    parameter [15:0] SEED = 16'hACE1
)(
    input                    clk,
    input                    rst_n,
    input                    start,
    // to / from the CUT
    output reg               scan_en,
    output reg               cap_en,
    output                   sa_in,
    output                   sb_in,
    input                    sa_out,
    input                    sb_out,
    output     [1:0]         pi_op,
    output     [3:0]         pi_din,
    input      [3:0]         acc_out,
    // status
    output reg [MISR_W-1:0]  sig,
    output reg               pat_tick
);
    localparam S_IDLE=2'd0, S_SHIFT=2'd1, S_CAP=2'd2;
    localparam CHAIN_LEN = 6;

    reg  [1:0]  state;
    reg  [2:0]  scnt;          // shift counter 0..5
    reg  [15:0] lfsr;

    // ---- PRPG next state (used combinationally, latched at the clock edge) --
    wire [15:0] lfsr_n = {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};

    // ---- phase shifter : decorrelated fill bits for the two chains ---------
    assign sa_in  = lfsr_n[0] ^ lfsr_n[7];
    assign sb_in  = lfsr_n[3] ^ lfsr_n[11];

    // ---- primary inputs during capture, also from the PRPG -----------------
    assign pi_op  = lfsr_n[1:0];
    assign pi_din = lfsr_n[5:2];

    // ---- MISR ---------------------------------------------------------------
    localparam [15:0] POLY16 = 16'h8005;
    localparam [15:0] POLY8  = 16'h001D;
    wire [MISR_W-1:0] poly = (MISR_W == 16) ? POLY16[MISR_W-1:0] : POLY8[MISR_W-1:0];

    // shifted-with-feedback version of the current signature
    wire [MISR_W-1:0] sig_sh = {sig[MISR_W-2:0], 1'b0} ^
                               (sig[MISR_W-1] ? poly : {MISR_W{1'b0}});

    // parallel input to the MISR this cycle
    wire [MISR_W-1:0] misr_in = (state == S_SHIFT) ? { {(MISR_W-2){1'b0}}, sb_out, sa_out }
                                                   : { {(MISR_W-4){1'b0}}, acc_out };

    // ---- control -----------------------------------------------------------
    always @* begin
        scan_en = (state == S_SHIFT);
        cap_en  = (state == S_CAP);     // CUT holds while the engine is idle
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            scnt     <= 3'd0;
            lfsr     <= SEED;
            sig      <= {MISR_W{1'b1}};
            pat_tick <= 1'b0;
        end else begin
            pat_tick <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_SHIFT;
                        scnt  <= 3'd0;
                    end
                end
                S_SHIFT: begin
                    lfsr <= lfsr_n;                 // PRPG advances every shift
                    sig  <= sig_sh ^ misr_in;       // MISR absorbs both chain ends
                    if (scnt == CHAIN_LEN-1) begin
                        scnt  <= 3'd0;
                        state <= S_CAP;
                    end else begin
                        scnt <= scnt + 3'd1;
                    end
                end
                S_CAP: begin
                    lfsr     <= lfsr_n;             // PRPG supplies the PIs
                    sig      <= sig_sh ^ misr_in;   // MISR absorbs the PO
                    pat_tick <= 1'b1;               // one pattern finished
                    state    <= S_SHIFT;            // next pattern
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
