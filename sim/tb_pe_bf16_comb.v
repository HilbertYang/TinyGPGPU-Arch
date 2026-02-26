// tb_pe_bf16_comb.v  — Testbench for BFloat16 Processing Element
//
// BF16 format: 1b sign | 8b exp (bias 127) | 7b mantissa
//   1.0  = 16'h3F80    (0 01111111 0000000)
//   2.0  = 16'h4000    (0 10000000 0000000)
//   0.5  = 16'h3F00    (0 01111110 0000000)
//  -1.0  = 16'hBF80    (1 01111111 0000000)
//   3.0  = 16'h4040    (0 10000000 1000000)
//   4.0  = 16'h4080    (0 10000001 0000000)
//   0.0  = 16'h0000
//  -0.0  = 16'h8000
`timescale 1ns/1ps
module tb_pe_bf16_comb;

    reg         valid_in, op_mac;
    reg  [15:0] A, B, C;
    wire        valid_out;
    wire [15:0] Y;

    integer pass_cnt = 0, fail_cnt = 0;

    pe_bf16_comb dut (
        .valid_in(valid_in),.op_mac(op_mac),
        .A(A),.B(B),.C(C),
        .valid_out(valid_out),.Y(Y)
    );

    // BF16 constants
    localparam BF16_0   = 16'h0000;
    localparam BF16_N0  = 16'h8000;
    localparam BF16_1   = 16'h3F80;
    localparam BF16_N1  = 16'hBF80;
    localparam BF16_2   = 16'h4000;
    localparam BF16_N2  = 16'hC000;
    localparam BF16_3   = 16'h4040;
    localparam BF16_4   = 16'h4080;
    localparam BF16_05  = 16'h3F00;  // 0.5
    localparam BF16_6   = 16'h40C0;
    localparam BF16_8   = 16'h4100;
    localparam BF16_INF = 16'h7F80;

    task check_y;
        input [15:0] expected;
        input [255:0] label;
        begin
            #1;
            if (Y === expected) begin
                $display("PASS  [%-45s]  Y=%h", label, Y);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  [%-45s]  Y=%h  exp=%h", label, Y, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task check_valid;
        input exp_v;
        begin
            #1;
            if (valid_out === exp_v) begin
                $display("PASS  [valid_out=%b]", valid_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  [valid_out=%b exp=%b]", valid_out, exp_v);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_pe_bf16_comb.vcd");
        $dumpvars(0, tb_pe_bf16_comb);
        valid_in = 1; C = BF16_0;

        // =============================================
        // op_mac = 0 : Y = A * B
        // =============================================
        op_mac = 0;

        // 1.0 * 1.0 = 1.0
        A = BF16_1; B = BF16_1;
        check_y(BF16_1, "MUL 1.0*1.0=1.0");

        // 2.0 * 3.0 = 6.0
        A = BF16_2; B = BF16_3;
        check_y(BF16_6, "MUL 2.0*3.0=6.0");

        // -1.0 * 2.0 = -2.0
        A = BF16_N1; B = BF16_2;
        check_y(BF16_N2, "MUL -1.0*2.0=-2.0");

        // -1.0 * -1.0 = 1.0
        A = BF16_N1; B = BF16_N1;
        check_y(BF16_1, "MUL -1*-1=1.0");

        // 0.0 * anything = 0.0
        A = BF16_0; B = BF16_4;
        check_y(BF16_0, "MUL 0.0*4.0=0.0");

        // anything * 0.0 = 0.0
        A = BF16_3; B = BF16_0;
        check_y(BF16_0, "MUL 3.0*0.0=0.0");

        // 0.5 * 2.0 = 1.0
        A = BF16_05; B = BF16_2;
        check_y(BF16_1, "MUL 0.5*2.0=1.0");

        // 2.0 * 4.0 = 8.0
        A = BF16_2; B = BF16_4;
        check_y(BF16_8, "MUL 2.0*4.0=8.0");

        // =============================================
        // op_mac = 1 : Y = C + A * B
        // =============================================
        op_mac = 1;

        // C=0, 2.0*3.0 = 6.0
        A = BF16_2; B = BF16_3; C = BF16_0;
        check_y(BF16_6, "MAC 0+2*3=6.0");

        // C=1.0, 1.0*1.0: 1+1=2
        A = BF16_1; B = BF16_1; C = BF16_1;
        check_y(BF16_2, "MAC 1.0+1*1=2.0");

        // C=2.0, 2.0*3.0: 2+6=8
        A = BF16_2; B = BF16_3; C = BF16_2;
        check_y(BF16_8, "MAC 2.0+2*3=8.0");

        // C=4.0, -1*2=-2, 4+(-2)=2
        A = BF16_N1; B = BF16_2; C = BF16_4;
        check_y(BF16_2, "MAC 4.0+(-1*2)=2.0");

        // C=1.0, 0*anything=0, 1+0=1
        A = BF16_0; B = BF16_8; C = BF16_1;
        check_y(BF16_1, "MAC C+0*B = C");

        // C=-1.0, 1*1=1, -1+1=0
        A = BF16_1; B = BF16_1; C = BF16_N1;
        check_y(BF16_0, "MAC -1+1*1=0");

        // =============================================
        // valid_in passthrough
        // =============================================
        valid_in = 1; A = BF16_1; B = BF16_1; C = BF16_0; op_mac = 0;
        check_valid(1'b1);

        valid_in = 0;
        check_valid(1'b0);

        valid_in = 1;
        check_valid(1'b1);

        #5;
        $display("\n=== pe_bf16_comb: PASS=%0d  FAIL=%0d ===\n", pass_cnt, fail_cnt);
        $finish;
    end
endmodule