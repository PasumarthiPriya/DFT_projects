`timescale 1ns / 1ps


//======================================================================
//  s27_scan_fi.v  -  ISCAS-89 s27, full scan, fault injectable
//
//  Muxed-D scan chain :  scan_in -> SFF0(G5) -> SFF1(G6) -> SFF2(G7)
//                                                        -> scan_out
//
//  A saboteur sits on every one of the 26 line indices used by the
//  ATPG engine, so fault_net here means exactly what FAULT_NET means
//  in the testbench.  Numbering :
//     0 G0   1 G1   2 G2   3 G3   4 G5   5 G6   6 G7
//     7 G14  8 G14_b1  9 G14_b2
//    10 G8  11 G8_b1  12 G8_b2
//    13 G12 14 G12_b1 15 G12_b2
//    16 G13 17 G15 18 G16 19 G9
//    20 G11 21 G11_b1 22 G11_b2 23 G11_b3
//    24 G10 25 G17
//
//  The shift path is taken from the RAW cell outputs, so a fault on
//  G5/G6/G7 corrupts the combinational logic (which is what the fault
//  model says) without corrupting scan load or unload.
//======================================================================

module s27_scan_fi (
    input        clk,
    input        scan_en,
    input        scan_in,
    input        G0,
    input        G1,
    input        G2,
    input        G3,
    input        fault_en,
    input  [4:0] fault_net,
    input        fault_val,
    output       G17,
    output       scan_out
);

    reg q0, q1, q2;                 // G5, G6, G7  (raw cell outputs)

    //  Saboteur.  This MUST be a macro, not a function: a continuous
    //  assignment is only sensitive to a function's arguments, so a
    //  function reading fault_en/fault_net/fault_val as module signals
    //  would never re-evaluate when the injected fault changes.
    `define INJ(IDX, EXPR) \
        ((fault_en && (fault_net == 5'd``IDX)) ? fault_val : (EXPR))

    wire n0  = `INJ(0, G0);
    wire n1  = `INJ(1, G1);
    wire n2  = `INJ(2, G2);
    wire n3  = `INJ(3, G3);
    wire n4  = `INJ(4, q0);                  // G5
    wire n5  = `INJ(5, q1);                  // G6
    wire n6  = `INJ(6, q2);                  // G7

    wire n7  = `INJ(7, ~n0);                 // G14  = NOT G0
    wire n8  = `INJ(8, n7);                  // G14_b1
    wire n9  = `INJ(9, n7);                  // G14_b2

    wire n10 = `INJ(10, n8 & n5);             // G8   = AND(G14_b1,G6)
    wire n11 = `INJ(11, n10);                 // G8_b1
    wire n12 = `INJ(12, n10);                 // G8_b2

    wire n13 = `INJ(13, ~(n1 | n6));          // G12  = NOR(G1,G7)
    wire n14 = `INJ(14, n13);                 // G12_b1
    wire n15 = `INJ(15, n13);                 // G12_b2

    wire n16 = `INJ(16, ~(n2 | n15));         // G13  = NOR(G2,G12_b2)
    wire n17 = `INJ(17, n14 | n11);           // G15  = OR(G12_b1,G8_b1)
    wire n18 = `INJ(18, n3  | n12);           // G16  = OR(G3,G8_b2)
    wire n19 = `INJ(19, ~(n18 & n17));        // G9   = NAND(G16,G15)

    wire n20 = `INJ(20, ~(n4 | n19));         // G11  = NOR(G5,G9)
    wire n21 = `INJ(21, n20);                 // G11_b1
    wire n22 = `INJ(22, n20);                 // G11_b2
    wire n23 = `INJ(23, n20);                 // G11_b3

    wire n24 = `INJ(24, ~(n9 | n21));         // G10  = NOR(G14_b2,G11_b1)
    wire n25 = `INJ(25, ~n22);                // G17  = NOT G11_b2

    //  muxed-D scan cells.  scan path uses q0/q1 raw, not n4/n5.
    always @(posedge clk) begin
        q0 <= scan_en ? scan_in : n24;          // G5 <= G10
        q1 <= scan_en ? q0      : n23;          // G6 <= G11
        q2 <= scan_en ? q1      : n16;          // G7 <= G13
    end

    assign scan_out = q2;
    assign G17      = n25;

`undef INJ

endmodule
