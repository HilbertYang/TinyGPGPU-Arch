// tb_tensor_core_bf16x4.v
// Testbench for tensor_core_bf16x4 (purely combinational)
// Compatible with ISim / Verilog-2001: no reg declarations inside unnamed blocks

`timescale 1ns/1ps

module tensor_core_bf16x4_tb;

    // ----------------------------------------------------------------
    // BF16 encoding:  [15]=sign  [14:7]=exp(biased127)  [6:0]=mantissa
    // ----------------------------------------------------------------
    localparam BF16_0P0  = 16'h0000; //  0.0
    localparam BF16_0P25 = 16'h3E80; //  0.25
    localparam BF16_0P5  = 16'h3F00; //  0.5
    localparam BF16_0P75 = 16'h3F40; //  0.75
    localparam BF16_1P0  = 16'h3F80; //  1.0
    localparam BF16_2P0  = 16'h4000; //  2.0
    localparam BF16_3P0  = 16'h4040; //  3.0
    localparam BF16_4P0  = 16'h4080; //  4.0
    localparam BF16_6P0  = 16'h40C0; //  6.0
    localparam BF16_7P0  = 16'h40E0; //  7.0
    localparam BF16_N1P0 = 16'hBF80; // -1.0
    localparam BF16_N2P0 = 16'hC000; // -2.0
    localparam BF16_N3P0 = 16'hC040; // -3.0
    localparam BF16_N4P0 = 16'hC080; // -4.0

    // DUT signals
    reg         op_mac;
    reg  [63:0] A, B, C;
    wire [63:0] Y;

    // All reg declarations at module scope (ISim / Verilog-2001 requirement)
    integer pass_cnt;
    integer fail_cnt;
    integer t;
    reg [63:0] prev_y;
    reg [63:0] exp_y;
    reg [15:0] got_lane;
    reg [15:0] exp_lane;
    reg [15:0] diff;
    reg        all_ok;

    // ---- DUT ----
    tensor_core_bf16x4 DUT (
        .op_mac (op_mac),
        .A      (A),
        .B      (B),
        .C      (C),
        .Y      (Y)
    );

    // ---- pack helper (function, not task, so can be used in expressions) ----
    function [63:0] p4;
        input [15:0] l0, l1, l2, l3;
        begin
            p4 = {l3, l2, l1, l0};
        end
    endfunction

    // ---- check task: exact match ----
    task chk;
        input [63:0] a_in, b_in, c_in;
        input        mac;
        input [63:0] expected;
        input [8*32-1:0] lbl;
        begin
            A = a_in; B = b_in; C = c_in; op_mac = mac;
            #10;
            $write("  [%0s] Y=%h  exp=%h  ", lbl, Y, expected);
            if (Y === expected) begin
                $display("PASS");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL *** got %h exp %h ***", Y, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ---- check task: per-lane 1-ULP tolerance ----
    task chk_approx;
        input [63:0] a_in, b_in, c_in;
        input        mac;
        input [63:0] expected;
        input [8*32-1:0] lbl;
        begin
            A = a_in; B = b_in; C = c_in; op_mac = mac;
            #10;
            all_ok = 1'b1;
            for (t = 0; t < 4; t = t + 1) begin
                got_lane = Y[t*16 +: 16];
                exp_lane = expected[t*16 +: 16];
                diff = (got_lane > exp_lane) ? (got_lane - exp_lane)
                                             : (exp_lane - got_lane);
                if (diff > 1) all_ok = 1'b0;
            end
            $write("  [%0s] Y=%h  exp=%h  ", lbl, Y, expected);
            if (all_ok) begin
                $display("PASS");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL *** >1 ULP diff ***");
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ================================================================
    initial begin
        op_mac = 0; A = 0; B = 0; C = 0;
        pass_cnt = 0; fail_cnt = 0;
        #5;

        $display("================================================");
        $display("  tensor_core_bf16x4  Combinational Testbench");
        $display("================================================");

        // ------------------------------------------------------------
        // MUL mode: op_mac=0, Y[i] = A[i]*B[i]
        // ------------------------------------------------------------
        $display("\n--- MUL (op_mac=0) ---");

        // T1: all 1.0 * 1.0 = 1.0
        chk( p4(BF16_1P0, BF16_1P0, BF16_1P0, BF16_1P0),
             p4(BF16_1P0, BF16_1P0, BF16_1P0, BF16_1P0),
             64'h0, 1'b0,
             p4(BF16_1P0, BF16_1P0, BF16_1P0, BF16_1P0),
             "MUL 1*1=1       " );

        // T2: all 2.0 * 3.0 = 6.0
        chk( p4(BF16_2P0, BF16_2P0, BF16_2P0, BF16_2P0),
             p4(BF16_3P0, BF16_3P0, BF16_3P0, BF16_3P0),
             64'h0, 1'b0,
             p4(BF16_6P0, BF16_6P0, BF16_6P0, BF16_6P0),
             "MUL 2*3=6       " );

        // T3: all 0.0 * 3.0 = 0.0
        chk( p4(BF16_0P0, BF16_0P0, BF16_0P0, BF16_0P0),
             p4(BF16_3P0, BF16_3P0, BF16_3P0, BF16_3P0),
             64'h0, 1'b0,
             p4(BF16_0P0, BF16_0P0, BF16_0P0, BF16_0P0),
             "MUL 0*3=0       " );

        // T4: all -1.0 * 2.0 = -2.0
        chk( p4(BF16_N1P0, BF16_N1P0, BF16_N1P0, BF16_N1P0),
             p4(BF16_2P0,  BF16_2P0,  BF16_2P0,  BF16_2P0),
             64'h0, 1'b0,
             p4(BF16_N2P0, BF16_N2P0, BF16_N2P0, BF16_N2P0),
             "MUL -1*2=-2     " );

        // T5: all 0.5 * 0.5 = 0.25
        chk( p4(BF16_0P5, BF16_0P5, BF16_0P5, BF16_0P5),
             p4(BF16_0P5, BF16_0P5, BF16_0P5, BF16_0P5),
             64'h0, 1'b0,
             p4(BF16_0P25, BF16_0P25, BF16_0P25, BF16_0P25),
             "MUL 0.5*0.5=0.25" );

        // T6: mixed lanes: [1,2,0.5,0] * [1,3,0.5,4] = [1,6,0.25,0]
        chk( p4(BF16_1P0, BF16_2P0, BF16_0P5, BF16_0P0),
             p4(BF16_1P0, BF16_3P0, BF16_0P5, BF16_4P0),
             64'h0, 1'b0,
             p4(BF16_1P0, BF16_6P0, BF16_0P25, BF16_0P0),
             "MUL mixed lanes " );

        // T7: overflow lanes - MAX_NORMAL * MAX_NORMAL → exponent overflows → inf
        begin
            A = p4(16'h7F7F, 16'h7F7F, 16'h7F7F, 16'h7F7F);
            B = p4(16'h7F7F, 16'h7F7F, 16'h7F7F, 16'h7F7F);
            C = 64'h0; op_mac = 1'b0;
            #10;
            $write("  [MUL MAX*MAX~inf] Y=%h  ", Y);
            // all 4 lanes should be inf (exp=FF, frac=0) or FF-exp
            if (Y[14:7]  == 8'hFF &&
                Y[30:23] == 8'hFF &&
                Y[46:39] == 8'hFF &&
                Y[62:55] == 8'hFF) begin
                $display("PASS (all lanes inf)");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL *** lanes not inf: %h ***", Y);
                fail_cnt = fail_cnt + 1;
            end
        end

        // ------------------------------------------------------------
        // MAC mode: op_mac=1, Y[i] = C[i] + A[i]*B[i]
        // ------------------------------------------------------------
        $display("\n--- MAC (op_mac=1) ---");

        // T8: all: 1.0 + 2.0*3.0 = 7.0
        chk( p4(BF16_2P0, BF16_2P0, BF16_2P0, BF16_2P0),
             p4(BF16_3P0, BF16_3P0, BF16_3P0, BF16_3P0),
             p4(BF16_1P0, BF16_1P0, BF16_1P0, BF16_1P0),
             1'b1,
             p4(BF16_7P0, BF16_7P0, BF16_7P0, BF16_7P0),
             "MAC 1+2*3=7     " );

        // T9: all: 0.5 + 0.5*0.5 = 0.75
        chk( p4(BF16_0P5, BF16_0P5, BF16_0P5, BF16_0P5),
             p4(BF16_0P5, BF16_0P5, BF16_0P5, BF16_0P5),
             p4(BF16_0P5, BF16_0P5, BF16_0P5, BF16_0P5),
             1'b1,
             p4(BF16_0P75, BF16_0P75, BF16_0P75, BF16_0P75),
             "MAC 0.5+.5*.5   " );

        // T10: all: -4.0 + 2.0*3.0 = 2.0
        chk( p4(BF16_2P0,  BF16_2P0,  BF16_2P0,  BF16_2P0),
             p4(BF16_3P0,  BF16_3P0,  BF16_3P0,  BF16_3P0),
             p4(BF16_N4P0, BF16_N4P0, BF16_N4P0, BF16_N4P0),
             1'b1,
             p4(BF16_2P0, BF16_2P0, BF16_2P0, BF16_2P0),
             "MAC -4+2*3=2    " );

        // T11: all: 0.0 + 1.0*1.0 = 1.0  (C=0 passthrough)
        chk( p4(BF16_1P0, BF16_1P0, BF16_1P0, BF16_1P0),
             p4(BF16_1P0, BF16_1P0, BF16_1P0, BF16_1P0),
             p4(BF16_0P0, BF16_0P0, BF16_0P0, BF16_0P0),
             1'b1,
             p4(BF16_1P0, BF16_1P0, BF16_1P0, BF16_1P0),
             "MAC 0+1*1=1     " );

        // T12: all: 3.0 + 0.0*n = 3.0  (A=0, prod=0, Y=C)
        chk( p4(BF16_0P0, BF16_0P0, BF16_0P0, BF16_0P0),
             p4(BF16_3P0, BF16_3P0, BF16_3P0, BF16_3P0),
             p4(BF16_3P0, BF16_3P0, BF16_3P0, BF16_3P0),
             1'b1,
             p4(BF16_3P0, BF16_3P0, BF16_3P0, BF16_3P0),
             "MAC 3+0*n=3     " );

        // T13: all: 1.0 + (-1.0)*1.0 = 0.0
        chk( p4(BF16_N1P0, BF16_N1P0, BF16_N1P0, BF16_N1P0),
             p4(BF16_1P0,  BF16_1P0,  BF16_1P0,  BF16_1P0),
             p4(BF16_1P0,  BF16_1P0,  BF16_1P0,  BF16_1P0),
             1'b1,
             p4(BF16_0P0, BF16_0P0, BF16_0P0, BF16_0P0),
             "MAC 1+(-1)*1=0  " );

        // T14: mixed: lane0:0+1*1=1, lane1:1+2*3=7, lane2:-4+2*3=2, lane3:.5+.5*.5=.75
        chk( p4(BF16_1P0, BF16_2P0, BF16_2P0,  BF16_0P5),
             p4(BF16_1P0, BF16_3P0, BF16_3P0,  BF16_0P5),
             p4(BF16_0P0, BF16_1P0, BF16_N4P0, BF16_0P5),
             1'b1,
             p4(BF16_1P0, BF16_7P0, BF16_2P0, BF16_0P75),
             "MAC mixed lanes " );

        // ------------------------------------------------------------
        // op_mac switching (same A/B/C, toggle op_mac)
        // ------------------------------------------------------------
        $display("\n--- op_mac dynamic switch ---");

        // T15a: op_mac=0 → prod only
        A = p4(BF16_2P0, BF16_2P0, BF16_2P0, BF16_2P0);
        B = p4(BF16_3P0, BF16_3P0, BF16_3P0, BF16_3P0);
        C = p4(BF16_1P0, BF16_1P0, BF16_1P0, BF16_1P0);
        op_mac = 1'b0; #10;
        $write("  [switch MUL 2*3=6]: Y=%h  exp=%h  ",
               Y, p4(BF16_6P0,BF16_6P0,BF16_6P0,BF16_6P0));
        if (Y === p4(BF16_6P0,BF16_6P0,BF16_6P0,BF16_6P0)) begin
            $display("PASS"); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL"); fail_cnt = fail_cnt + 1;
        end

        // T15b: same signals, op_mac=1 → 1+6=7
        op_mac = 1'b1; #10;
        $write("  [switch MAC 1+2*3=7]: Y=%h  exp=%h  ",
               Y, p4(BF16_7P0,BF16_7P0,BF16_7P0,BF16_7P0));
        if (Y === p4(BF16_7P0,BF16_7P0,BF16_7P0,BF16_7P0)) begin
            $display("PASS"); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL"); fail_cnt = fail_cnt + 1;
        end

        // ------------------------------------------------------------
        // C is ignored in MUL mode
        // ------------------------------------------------------------
        $display("\n--- C ignored in MUL mode ---");
        // T16: A=2, B=3, C=99 (large), op_mac=0 → Y must be 6, not C+6
        A = p4(BF16_2P0, BF16_2P0, BF16_2P0, BF16_2P0);
        B = p4(BF16_3P0, BF16_3P0, BF16_3P0, BF16_3P0);
        C = p4(16'h4780, 16'h4780, 16'h4780, 16'h4780); // 256.0, large
        op_mac = 1'b0; #10;
        $write("  [MUL C ignored]: Y=%h  exp=%h  ",
               Y, p4(BF16_6P0,BF16_6P0,BF16_6P0,BF16_6P0));
        if (Y === p4(BF16_6P0,BF16_6P0,BF16_6P0,BF16_6P0)) begin
            $display("PASS"); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL *** C leaked into MUL result ***"); fail_cnt = fail_cnt + 1;
        end

        // ------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------
        $display("\n================================================");
        $display("  RESULT: %0d PASS  %0d FAIL  (total %0d)",
                  pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        $display("================================================");
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED - review above");

        $finish;
    end

endmodule