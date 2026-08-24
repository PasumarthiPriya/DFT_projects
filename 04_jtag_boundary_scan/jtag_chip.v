// ============================================================================
//  P4 : IEEE 1149.1 Boundary Scan (JTAG)   -   FILE 1/2 : one chip
// ----------------------------------------------------------------------------
//  A complete 1149.1-style Test Access Port:
//
//    * TAP CONTROLLER : the standard 16-state FSM, navigated only by TMS.
//        TEST_LOGIC_RESET RUN_TEST_IDLE
//        SELECT_DR CAPTURE_DR SHIFT_DR EXIT1_DR PAUSE_DR EXIT2_DR UPDATE_DR
//        SELECT_IR CAPTURE_IR SHIFT_IR EXIT1_IR PAUSE_IR EXIT2_IR UPDATE_IR
//    * INSTRUCTION REGISTER (4 bit), captures 4'b0001 as the standard requires
//    * DATA REGISTERS : 32-bit IDCODE, 1-bit BYPASS, 16-bit BOUNDARY SCAN
//    * BOUNDARY SCAN REGISTER : one cell per pin, each with a capture stage
//      (the shift register) and an update stage (the parallel output latch)
//          bsr[7:0]   = OUTPUT cells, cell i drives pin_out[i]
//          bsr[15:8]  = INPUT  cells, cell 8+i observes pin_in[i]
//
//  INSTRUCTIONS
//    EXTEST (0000) : pins driven from the update latches, input cells capture
//                    the pin values -> tests the BOARD WIRING between chips.
//                    Note it deliberately DISCONNECTS the core, so EXTEST is
//                    blind to internal faults - that is what INTEST is for.
//    SAMPLE/PRELOAD (0001) : normal operation continues; snapshot the pins, or
//                    preload the update latches before entering EXTEST.
//    INTEST (0010) : the core is driven FROM the input cells and its response
//                    captured INTO the output cells -> tests the CORE LOGIC.
//    IDCODE (1110) : 32-bit device identification, the reset default.
//    BYPASS (1111) : a single flip-flop, so an uninteresting chip costs 1 bit
//                    instead of its whole boundary register.
//
//  Shift convention: LSB first. TDI enters at the MSB end, TDO leaves from
//  bit 0, so the first bit shifted in ends up as the LSB.
// ============================================================================
module jtag_chip #(
    parameter [31:0] IDCODE_VAL = 32'h1234_5673      // LSB must be 1 per 1149.1
)(
    input             tck,
    input             tms,
    input             tdi,
    output            tdo,
    input             trst_n,
    // functional pins
    input      [7:0]  pin_in,
    output     [7:0]  pin_out,
    // simulation-only internal core fault
    input             cf_active
);
    // ---- TAP states ---------------------------------------------------------
    localparam TLR=4'd0,  RTI=4'd1,  SELDR=4'd2, CAPDR=4'd3,
               SHDR=4'd4, EX1DR=4'd5,PAUDR=4'd6, EX2DR=4'd7, UPDDR=4'd8,
               SELIR=4'd9,CAPIR=4'd10,SHIR=4'd11,EX1IR=4'd12,
               PAUIR=4'd13,EX2IR=4'd14,UPDIR=4'd15;

    // ---- instructions -------------------------------------------------------
    localparam [3:0] I_EXTEST=4'h0, I_SAMPLE=4'h1, I_INTEST=4'h2,
                     I_IDCODE=4'hE, I_BYPASS=4'hF;

    reg  [3:0]  state;
    reg  [3:0]  ir, irs;
    reg  [15:0] bsr, upd;
    reg  [31:0] idr;
    reg         byp;

    wire bsr_sel = (ir==I_EXTEST) || (ir==I_SAMPLE) || (ir==I_INTEST);

    // ---- the core : 8 in -> 8 out, purely combinational ---------------------
    //   core_out[3:0] = lo + hi ,  core_out[7:4] = lo ^ hi
    wire [7:0] core_in_raw = (ir==I_INTEST) ? upd[15:8] : pin_in;
    wire [7:0] core_in     = cf_active ? (core_in_raw & 8'hFE) : core_in_raw;
    wire [3:0] lo = core_in[3:0];
    wire [3:0] hi = core_in[7:4];
    wire [7:0] core_out = {(lo ^ hi), (lo + hi)};

    // ---- pin drive : EXTEST drives from the update latches -------------------
    assign pin_out = (ir==I_EXTEST) ? upd[7:0] : core_out;

    // ---- TDO : IR chain while shifting IR, else the selected DR --------------
    wire dr_tdo = bsr_sel     ? bsr[0] :
                  (ir==I_IDCODE) ? idr[0] : byp;
    assign tdo = (state==SHIR) ? irs[0] : dr_tdo;

    // ---- next-state logic : the classic 16-state TAP diagram -----------------
    reg [3:0] ns;
    always @* begin
        case (state)
            TLR  : ns = tms ? TLR   : RTI;
            RTI  : ns = tms ? SELDR : RTI;
            SELDR: ns = tms ? SELIR : CAPDR;
            CAPDR: ns = tms ? EX1DR : SHDR;
            SHDR : ns = tms ? EX1DR : SHDR;
            EX1DR: ns = tms ? UPDDR : PAUDR;
            PAUDR: ns = tms ? EX2DR : PAUDR;
            EX2DR: ns = tms ? UPDDR : SHDR;
            UPDDR: ns = tms ? SELDR : RTI;
            SELIR: ns = tms ? TLR   : CAPIR;
            CAPIR: ns = tms ? EX1IR : SHIR;
            SHIR : ns = tms ? EX1IR : SHIR;
            EX1IR: ns = tms ? UPDIR : PAUIR;
            PAUIR: ns = tms ? EX2IR : PAUIR;
            EX2IR: ns = tms ? UPDIR : SHIR;
            UPDIR: ns = tms ? SELDR : RTI;
            default: ns = TLR;
        endcase
    end

    // ---- register actions happen in the state, then the state advances -------
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            state <= TLR;
            ir    <= I_IDCODE;
            irs   <= 4'b0001;
            bsr   <= 16'd0;
            upd   <= 16'd0;
            idr   <= IDCODE_VAL;
            byp   <= 1'b0;
        end else begin
            case (state)
                CAPIR: irs <= 4'b0001;                    // mandated capture value
                SHIR : irs <= {tdi, irs[3:1]};
                UPDIR: ir  <= irs;
                CAPDR: begin
                    if (bsr_sel)            bsr <= {pin_in, core_out};
                    else if (ir==I_IDCODE)  idr <= IDCODE_VAL;
                    else                    byp <= 1'b0;
                end
                SHDR : begin
                    if (bsr_sel)            bsr <= {tdi, bsr[15:1]};
                    else if (ir==I_IDCODE)  idr <= {tdi, idr[31:1]};
                    else                    byp <= tdi;
                end
                UPDDR: if (bsr_sel)         upd <= bsr;
                default: ;
            endcase
            if (state==TLR) ir <= I_IDCODE;               // reset default
            state <= ns;
        end
    end
endmodule
