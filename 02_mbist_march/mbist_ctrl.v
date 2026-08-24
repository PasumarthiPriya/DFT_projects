// ============================================================================
//  P2 : Memory BIST (MBIST)   -   FILE 2/3 : microcoded March controller
// ----------------------------------------------------------------------------
//  A March test = a list of ELEMENTS; each element sweeps all addresses in a
//  direction and applies a short list of read/write operations per cell.
//  This one controller runs either algorithm, selected by parameter MODE:
//     MODE=0  MATS   (4N) : {^(w0); ^(r0,w1); ^(r1)}          <- weak baseline
//     MODE=1  MarchC-(10N): {^(w0); ^(r0,w1); ^(r1,w0);
//                            v(r0,w1); v(r1,w0); ^(r0)}        <- MBIST
//  Background data 0 = 0x0, 1 = 0xF.  On any read mismatch it latches
//  fail=1 and fail_addr, then keeps running to completion (done=1).
// ============================================================================
module mbist_ctrl #(parameter MODE = 1) (
    input             clk,
    input             rst_n,
    input             start,
    output reg [2:0]  addr,
    output reg        we,
    output reg [3:0]  wdata,
    input      [3:0]  rdata,
    output reg        done,
    output reg        fail,
    output reg [2:0]  fail_addr
);
    localparam NW = 8;
    localparam S_IDLE=2'd0, S_ELEM=2'd1, S_OP=2'd2, S_DONE=2'd3;

    reg [1:0] state;
    reg [2:0] e;         // element index
    reg       oi;        // op index within element (0/1)
    reg [2:0] caddr;     // current address

    // ---- element decode : dir, has-2nd-op, op0(rw,data), op1(rw,data) ------
    reg       dir, nop2, o0rw, o0d, o1rw, o1d;
    reg [2:0] nelem;
    always @* begin
        dir=1'b0; nop2=1'b0; o0rw=1'b0; o0d=1'b0; o1rw=1'b0; o1d=1'b0;
        if (MODE==1) begin
            nelem = 3'd6;
            case (e)
                3'd0: begin dir=0; nop2=0; o0rw=1; o0d=0;                     end // ^ w0
                3'd1: begin dir=0; nop2=1; o0rw=0; o0d=0; o1rw=1; o1d=1;      end // ^ r0,w1
                3'd2: begin dir=0; nop2=1; o0rw=0; o0d=1; o1rw=1; o1d=0;      end // ^ r1,w0
                3'd3: begin dir=1; nop2=1; o0rw=0; o0d=0; o1rw=1; o1d=1;      end // v r0,w1
                3'd4: begin dir=1; nop2=1; o0rw=0; o0d=1; o1rw=1; o1d=0;      end // v r1,w0
                default:begin dir=0; nop2=0; o0rw=0; o0d=0;                   end // ^ r0
            endcase
        end else begin
            nelem = 3'd3;
            case (e)
                3'd0: begin dir=0; nop2=0; o0rw=1; o0d=0;                     end // ^ w0
                3'd1: begin dir=0; nop2=1; o0rw=0; o0d=0; o1rw=1; o1d=1;      end // ^ r0,w1
                default:begin dir=0; nop2=0; o0rw=0; o0d=1;                   end // ^ r1
            endcase
        end
    end

    // current op (op0 when oi==0, else op1)
    reg cur_rw, cur_d;
    always @* begin
        if (oi==1'b0) begin cur_rw=o0rw; cur_d=o0d; end
        else          begin cur_rw=o1rw; cur_d=o1d; end
    end

    // memory drive (combinational)
    always @* begin
        addr  = caddr;
        we    = (state==S_OP) & cur_rw;
        wdata = cur_d ? 4'hF : 4'h0;
    end

    wire [3:0] expected = cur_d ? 4'hF : 4'h0;

    // ---- sequencer ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; done<=1'b0; fail<=1'b0; fail_addr<=3'd0;
            e<=3'd0; oi<=1'b0; caddr<=3'd0;
        end else case (state)
            S_IDLE: begin
                done<=1'b0; fail<=1'b0;
                if (start) begin e<=3'd0; state<=S_ELEM; end
            end
            S_ELEM: begin
                oi<=1'b0;
                caddr <= dir ? (NW-1) : 3'd0;   // start of sweep for this element
                state<=S_OP;
            end
            S_OP: begin
                if (!cur_rw) begin                                  // read -> compare
                    if (rdata !== expected) begin fail<=1'b1; fail_addr<=caddr; end
                end
                if (oi==1'b0 && nop2) begin
                    oi<=1'b1;                                       // 2nd op, same cell
                end else begin
                    oi<=1'b0;
                    if (dir==1'b0) begin                            // ascending
                        if (caddr==NW-1) begin
                            if (e==nelem-1) state<=S_DONE;
                            else begin e<=e+3'd1; state<=S_ELEM; end
                        end else caddr<=caddr+3'd1;
                    end else begin                                  // descending
                        if (caddr==3'd0) begin
                            if (e==nelem-1) state<=S_DONE;
                            else begin e<=e+3'd1; state<=S_ELEM; end
                        end else caddr<=caddr-3'd1;
                    end
                end
            end
            S_DONE: done<=1'b1;
        endcase
    end
endmodule
