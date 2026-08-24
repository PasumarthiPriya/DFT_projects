// ============================================================================
//  P2 : Memory BIST (MBIST)   -   FILE 1/3 : SRAM with fault injection
// ----------------------------------------------------------------------------
//  8 words x 4 bits synchronous-write / combinational-read SRAM.
//  A single memory fault is injected via the f_* ports (simulation only), so
//  the testbench can grade a March algorithm against the classic memory fault
//  models:
//     SAF  stuck-at            TF   transition (can't rise / can't fall)
//     CFid idempotent coupling CFin inversion coupling
//     AF   address-decoder     LCF  linked coupling (hard-coded ceiling fault)
//
//  init / init_val : simulation-only "backdoor" preset of the whole array.
//     A real SRAM powers up in an ARBITRARY state, and a March test must work
//     regardless of it.  The testbench uses this to start every grading run
//     from a KNOWN background (all-0 and all-1) so results are reproducible
//     and initial-state dependence can be measured.  Fault effects are bypassed
//     during init (it models power-on content, not a write operation).
//
//  Cell = (address, bit).  Coupling faults assume victim address != aggressor.
// ============================================================================
module mbist_mem (
    input             clk,
    input             we,
    input      [2:0]  addr,
    input      [3:0]  wdata,
    output     [3:0]  rdata,
    // ---- simulation-only array preset ----
    input             init,
    input             init_val,
    // ---- fault injection ----
    input             f_active,
    input      [2:0]  f_type,     // 1 SAF, 2 TF, 3 CFid, 4 CFin, 5 AF, 6 LCF
    input      [2:0]  f_addrA,    // primary/aggressor address (AF: alias target 'a')
    input      [1:0]  f_bitA,     // primary/aggressor bit
    input      [2:0]  f_addrV,    // victim address           (AF: aliasing addr 'b')
    input      [1:0]  f_bitV,     // victim bit
    input             f_p,        // SAF value / TF dir(1=cant-rise) / CFid force
    input             f_trans     // aggressor transition: 1=rising(0->1), 0=falling
);
    localparam SAF=3'd1, TF=3'd2, CFID=3'd3, CFIN=3'd4, AF=3'd5, LCF=3'd6;

    reg  [3:0] mem [0:7];
    integer    i;
    reg  [3:0] nw;
    reg        oldb, newb;

    // ---------- combinational read (with AF decode + SAF override) ----------
    wire [2:0] r_pa = (f_active && f_type==AF && addr==f_addrV) ? f_addrA : addr;
    reg  [3:0] rmux;
    always @* begin
        rmux = mem[r_pa];
        if (f_active && f_type==SAF && r_pa==f_addrA) rmux[f_bitA] = f_p;
    end
    assign rdata = rmux;

    // ---------- array preset / synchronous write ----------------------------
    wire [2:0] w_pa = (f_active && f_type==AF && addr==f_addrV) ? f_addrA : addr;

    always @(posedge clk) begin
        if (init) begin
            // backdoor power-on preset : fault effects deliberately bypassed
            for (i = 0; i < 8; i = i + 1) mem[i] <= {4{init_val}};
        end
        else if (we) begin
            nw = wdata;
            // per-bit stuck-at / transition faults
            for (i = 0; i < 4; i = i + 1) begin
                if (f_active && f_type==SAF && w_pa==f_addrA && i==f_bitA)
                    nw[i] = f_p;                                   // stuck: write ignored
                else if (f_active && f_type==TF && w_pa==f_addrA && i==f_bitA) begin
                    if (f_p==1'b1 && mem[w_pa][i]==1'b0 && wdata[i]==1'b1) nw[i]=1'b0; // no rise
                    if (f_p==1'b0 && mem[w_pa][i]==1'b1 && wdata[i]==1'b0) nw[i]=1'b1; // no fall
                end
            end
            mem[w_pa] <= nw;

            // coupling fault : aggressor transition disturbs the victim cell
            if (f_active && (f_type==CFID || f_type==CFIN) && w_pa==f_addrA) begin
                oldb = mem[f_addrA][f_bitA];
                newb = nw[f_bitA];
                if ( (f_trans==1'b1 && oldb==1'b0 && newb==1'b1) ||
                     (f_trans==1'b0 && oldb==1'b1 && newb==1'b0) ) begin
                    if (f_type==CFID) mem[f_addrV][f_bitV] <= f_p;
                    else              mem[f_addrV][f_bitV] <= ~mem[f_addrV][f_bitV];
                end
            end

            // linked coupling (ceiling): aggressors (1,1) and (2,1) rising both
            // invert victim (4,1) -> the two sensitisations cancel -> undetectable.
            if (f_active && f_type==LCF) begin
                if (w_pa==3'd1 && mem[1][1]==1'b0 && nw[1]==1'b1) mem[4][1] <= ~mem[4][1];
                if (w_pa==3'd2 && mem[2][1]==1'b0 && nw[1]==1'b1) mem[4][1] <= ~mem[4][1];
            end
        end
    end
endmodule
