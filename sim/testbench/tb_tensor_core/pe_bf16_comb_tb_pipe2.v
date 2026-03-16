// pe_bf16_comb_tb.v
// Testbench for pe_bf16_comb (and sub-modules bf16_mul, bf16_add)
//
// BFloat16 format: [15]=sign, [14:7]=exponent(biased-127), [6:0]=fraction
// Helper: bf16(sign, exp, frac)
//
// Test cases:
//  1. MUL: 1.0 * 1.0 = 1.0
//  2. MUL: 2.0 * 3.0 = 6.0
//  3. MUL: -1.5 * 2.0 = -3.0
//  4. MUL: 0.0 * 5.0 = 0.0
//  5. MAC: 1.0 + 2.0*3.0 = 7.0   (C=1.0, A=2.0, B=3.0)
//  6. MAC: 0.5 + 0.5*0.5 = 0.75  (C=0.5, A=0.5, B=0.5)
//  7. MUL: large * large Ã¢ÂÂ inf clamp
//  8. MAC: negative accumulator: -4.0 + 2.0*3.0 = 2.0

`timescale 1ns/1ps

module pe_bf16_comb_tb_pipe2;

    // ---- BF16 encoding constants ----
    // 1.0  = 0_01111111_0000000 = 16'h3F80
    // 2.0  = 0_10000000_0000000 = 16'h4000
    // 3.0  = 0_10000000_1000000 = 16'h4040
    // 6.0  = 0_10000001_1000000 = 16'h40C0
    // -1.5 = 1_01111111_1000000 = 16'hBFC0
    // -3.0 = 1_10000000_1000000 = 16'hC040
    // 0.0  = 16'h0000
    // 5.0  = 0_10000001_0100000 = 16'h40A0
    // 7.0  = 0_10000001_1100000 = 16'h40E0
    // 0.5  = 0_01111110_0000000 = 16'h3F00
    // 0.75 = 0_01111110_1000000 = 16'h3F40
    // -4.0 = 1_10000001_0000000 = 16'hC080
    // 127.0= 0_10000101_1111110 = 16'h42FE
    // large= 0_11111110_1111111 = 16'h7F7F  (max normal)
    // inf  = 0_11111111_0000000 = 16'h7F80

    localparam BF16_1P0  = 16'h3F80;
    localparam BF16_2P0  = 16'h4000;
    localparam BF16_3P0  = 16'h4040;
    localparam BF16_6P0  = 16'h40C0;
    localparam BF16_N1P5 = 16'hBFC0;
    localparam BF16_N3P0 = 16'hC040;
    localparam BF16_0P0  = 16'h0000;
    localparam BF16_5P0  = 16'h40A0;
    localparam BF16_7P0  = 16'h40E0;
    localparam BF16_0P5  = 16'h3F00;
    localparam BF16_0P75 = 16'h3F40;
    localparam BF16_N4P0 = 16'hC080;
    localparam BF16_MAX  = 16'h7F7F;
    localparam BF16_INF  = 16'h7F80;

    // DUT signals
    reg         op_mac;
    reg  [15:0] A, B, C;
    wire [15:0] Y;
	 reg clk;
	 reg reset;
	 reg pc_reset;
	 reg advance;
		 
    integer pass_cnt, fail_cnt, test_num;

    // Instantiate DUT
    tensor16_pipe2 DUT (
        .op_mac (op_mac),
        .fb16_A      (A),
        .fb16_B    (B),
        .fb16_C      (C),
		  .clk(clk),
		  .reset(reset),
		  .pc_reset(pc_reset),
		  .advance(advance),
        .result      (Y)
    );
	 
    initial clk = 0;
    always  #5 clk = ~clk;
	 
    // Helper task: apply inputs, wait, check
    task run_test;
        input [63:0]  tnum;
        input         mac;
        input [15:0]  a_in, b_in, c_in;
        input [15:0]  expected;
        input [127:0] desc;
        begin
		  		reset = 1'b0;
				pc_reset = 1'b0;
				advance = 1'b1;
            op_mac = mac;
            A = a_in; B = b_in; C = c_in;
            #42;
            $write("Test %0d [%s]: A=%h B=%h C=%h op_mac=%b => Y=%h  expected=%h  ",
                    tnum, desc, a_in, b_in, c_in, mac, Y, expected);
            if (Y === expected) begin
                $display("PASS");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL *** got %h expected %h ***", Y, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ---- Helper: check with tolerance (for cases where rounding may differ by 1 ULP) ----
    task run_test_approx;
        input [63:0]  tnum;
        input         mac;
        input [15:0]  a_in, b_in, c_in;
        input [15:0]  expected;
        input [127:0] desc;
        reg [15:0] diff;
        begin
		  		reset = 1'b0;
				pc_reset = 1'b0;
				advance = 1'b1;
            op_mac = mac;
            A = a_in; B = b_in; C = c_in;
            #42;
            diff = (Y > expected) ? (Y - expected) : (expected - Y);
            $write("Test %0d [%s]: A=%h B=%h C=%h op_mac=%b => Y=%h  expected=%h  ",
                    tnum, desc, a_in, b_in, c_in, mac, Y, expected);
            if (diff <= 1) begin
                $display("PASS (diff=%0d ULP)", diff);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL *** got %h expected %h (diff=%0d ULP) ***", Y, expected, diff);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        op_mac = 0; A = 0; B = 0; C = 0;
        #5;

        $display("=======================================================");
        $display(" pe_bf16_comb Testbench");
        $display("=======================================================");

        // ---- MUL tests (op_mac=0) ----
        $display("\n--- MUL mode (op_mac=0) ---");

        // T1: 1.0 * 1.0 = 1.0
        run_test(1, 1'b0, BF16_1P0, BF16_1P0, BF16_0P0, BF16_1P0, "1.0*1.0=1.0 ");
//$stop;
        // T2: 2.0 * 3.0 = 6.0
        run_test(2, 1'b0, BF16_2P0, BF16_3P0, BF16_0P0, BF16_6P0, "2.0*3.0=6.0 ");

        // T3: -1.5 * 2.0 = -3.0
        run_test(3, 1'b0, BF16_N1P5, BF16_2P0, BF16_0P0, BF16_N3P0, "-1.5*2=-3.0 ");

        // T4: 0.0 * 5.0 = 0.0
        run_test(4, 1'b0, BF16_0P0, BF16_5P0, BF16_0P0, BF16_0P0, "0.0*5.0=0.0 ");

        // T5: 1.0 * 0.0 = 0.0
        run_test(5, 1'b0, BF16_1P0, BF16_0P0, BF16_0P0, BF16_0P0, "1.0*0.0=0.0 ");

        // T6: 0.5 * 0.5 = 0.25  (0.25 = 0_01111101_0000000 = 3E80)
        run_test(6, 1'b0, BF16_0P5, BF16_0P5, BF16_0P0, 16'h3E80, "0.5*0.5=0.25");

        // T7: MAX * MAX Ã¢ÂÂ should clamp to INF or large
        begin
            op_mac = 1'b0; A = BF16_MAX; B = BF16_MAX; C = 16'h0;
            #10;
            $write("Test 7 [MAX*MAX~INF]: Y=%h  ", Y);
            // exponent will overflow Ã¢ÂÂ INF = 7F80
            if (Y[14:7] == 8'hFF) begin
                $display("PASS (overflowÃ¢ÂÂinf/nan exp=FF)");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL *** exp=%h, expected FF ***", Y[14:7]);
                fail_cnt = fail_cnt + 1;
            end
        end

        // ---- MAC tests (op_mac=1) ----
        $display("\n--- MAC mode (op_mac=1) ---");
	//	 $stop;
        // T8: 1.0 + 2.0*3.0 = 7.0
        run_test(8, 1'b1, BF16_2P0, BF16_3P0, BF16_1P0, BF16_7P0, "1+2*3=7     ");

        // T9: 0.5 + 0.5*0.5 = 0.75
        run_test(9, 1'b1, BF16_0P5, BF16_0P5, BF16_0P5, BF16_0P75, "0.5+0.5*0.5 ");

        // T10: -4.0 + 2.0*3.0 = 2.0
        run_test(10, 1'b1, BF16_2P0, BF16_3P0, BF16_N4P0, BF16_2P0, "-4+2*3=2    ");

        // T11: 0.0 + 1.0*1.0 = 1.0  (C=zero passthrough test)
        run_test(11, 1'b1, BF16_1P0, BF16_1P0, BF16_0P0, BF16_1P0, "0+1*1=1     ");

        // T12: 3.0 + 0.0*5.0 = 3.0  (A=0 gives prod=0, add C)
        run_test(12, 1'b1, BF16_0P0, BF16_5P0, BF16_3P0, BF16_3P0, "3+0*5=3     ");

        // T13: MAC C=0, A=0.5, B=0.5 Ã¢ÂÂ 0.25
        run_test(13, 1'b1, BF16_0P5, BF16_0P5, BF16_0P0, 16'h3E80, "0+.5*.5=0.25");

        // T14: 1.0 + (-1.0)*1.0 = 0.0
        // -1.0 = BF80
        run_test(14, 1'b1, 16'hBF80, BF16_1P0, BF16_1P0, BF16_0P0, "1+(-1)*1=0  ");

        // ---- op_mac switching test ----
        $display("\n--- op_mac switching ---");
        // T15: Same A,B,C with op_mac=0 gives prod, op_mac=1 gives C+prod
        begin
            A = BF16_2P0; B = BF16_3P0; C = BF16_1P0;
            op_mac = 1'b0; #32;
            $write("Test 15a [switch MUL]: Y=%h expected=%h  ", Y, BF16_6P0);
            if (Y === BF16_6P0) begin $display("PASS"); pass_cnt=pass_cnt+1; end
            else begin $display("FAIL"); fail_cnt=fail_cnt+1; end

            op_mac = 1'b1; #32;
            $write("Test 15b [switch MAC]: Y=%h expected=%h  ", Y, BF16_7P0);
            if (Y === BF16_7P0) begin $display("PASS"); pass_cnt=pass_cnt+1; end
            else begin $display("FAIL"); fail_cnt=fail_cnt+1; end
        end

        // ---- Summary ----
        $display("\n=======================================================");
        $display(" RESULTS: %0d PASS, %0d FAIL out of %0d tests",
                  pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        $display("=======================================================");

        if (fail_cnt == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" SOME TESTS FAILED - check above");

        $finish;
    end

endmodule
