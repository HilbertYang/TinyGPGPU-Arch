// tb_alu_i16x4.v  -- Testbench for 4-lane 16-bit integer ALU
`timescale 1ns/1ps
module tb_alu_i16x4;

    reg  [63:0] a, b;
    reg  [4:0]  op;
    wire [63:0] y;
    wire        pred_out;

    localparam OP_ADD_I16  = 5'd0;
    localparam OP_SUB_I16  = 5'd1;
    localparam OP_MAX_I16  = 5'd2;
    localparam OP_ADD64    = 5'd3;
    localparam OP_SETP_GE  = 5'd4;
    localparam OP_SHIFTL16 = 5'd5;
    localparam OP_SHIFTR16 = 5'd6;

    integer pass_cnt = 0, fail_cnt = 0;

    alu_i16x4 dut (.a(a),.b(b),.op(op),.y(y),.pred_out(pred_out));

    task check_y;
        input [63:0] expected;
        input [255:0] label;
        begin
            #1;
            if (y === expected) begin
                $display("PASS  [%-30s]  y=%h", label, y);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  [%-30s]  y=%h  exp=%h", label, y, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task check_pred;
        input exp_pred;
        input [255:0] label;
        begin
            #1;
            if (pred_out === exp_pred) begin
                $display("PASS  [%-30s]  pred=%b", label, pred_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  [%-30s]  pred=%b  exp=%b", label, pred_out, exp_pred);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_alu_i16x4.vcd");
        $dumpvars(0, tb_alu_i16x4);

        // ---- OP_ADD_I16 ----
        op = OP_ADD_I16;
        a = {16'd1,16'd2,16'd3,16'd4};       b = {16'd10,16'd20,16'd30,16'd40};
        check_y({16'd11,16'd22,16'd33,16'd44}, "ADD_I16 basic");

        a = {16'hFFFF,16'd100,16'hFF00,16'd1}; b = {16'd1,16'd200,16'd256,16'd2};
        check_y({16'd0,16'd300,16'd0,16'd3},   "ADD_I16 mixed sign");

        a = {48'd0,16'h7FFF}; b = {48'd0,16'd1};
        check_y({48'd0,16'h8000},              "ADD_I16 overflow wrap");

        a = 64'd0; b = 64'd0;
        check_y(64'd0,                         "ADD_I16 all zero");

        // ---- OP_SUB_I16 ----
        op = OP_SUB_I16;
        a = {16'd50,16'd40,16'd30,16'd20};   b = {16'd10,16'd10,16'd10,16'd10};
        check_y({16'd40,16'd30,16'd20,16'd10}, "SUB_I16 basic");

        a = {16'd5,16'd5,16'd5,16'd5};       b = {16'd10,16'd10,16'd10,16'd10};
        check_y({4{16'hFFFB}},               "SUB_I16 neg result");

        a = {48'd0,16'h8000}; b = {48'd0,16'd1};
        check_y({48'd0,16'h7FFF},            "SUB_I16 underflow wrap");

        // ---- OP_MAX_I16 (ReLU) ----
        op = OP_MAX_I16;
        a = {16'd100,16'd5,16'hFFFF,16'd50}; b = {16'd50,16'd10,16'd0,16'd60};
        check_y({16'd100,16'd10,16'd0,16'd60}, "MAX_I16 basic");

        a = {16'hFFFF,16'hFFFE,16'hFF00,16'h8001}; b = 64'd0;
        check_y(64'd0,                         "MAX_I16 relu all neg");

        a = {16'd100,16'hFFFF,16'd200,16'hFF00}; b = 64'd0;
        check_y({16'd100,16'd0,16'd200,16'd0}, "MAX_I16 relu mixed");

        // ---- OP_ADD64 ----
        op = OP_ADD64;
        a = 64'h0000_0000_0000_1000; b = 64'h0000_0000_0000_0010;
        check_y(64'h0000_0000_0000_1010, "ADD64 basic");

        a = 64'h0000_0000_FFFF_FFFF; b = 64'h0000_0000_0000_0001;
        check_y(64'h0000_0001_0000_0000, "ADD64 carry across 32b");

        // ---- OP_SHIFTL16 ----
        op = OP_SHIFTL16;
        a = 64'h8004_0003_0002_0001; b = 64'd0;
        check_y(64'h0003_0002_0001_0000, "SHIFTL16 lane shift");

        a = 64'd0; b = 64'd0;
        check_y(64'd0, "SHIFTL16 zero");

        // ---- OP_SHIFTR16 ----
        op = OP_SHIFTR16;
        a = 64'h8004_0003_0002_0001; b = 64'd0;
        check_y(64'h0000_8004_0003_0002, "SHIFTR16 lane shift");

        a = 64'hFFFF_0000_0000_0000; b = 64'd0;
        check_y(64'h0000_FFFF_0000_0000, "SHIFTR16 logical zero fill");

        // ---- OP_SETP_GE ----
        op = OP_SETP_GE;
        a = 64'h64; b = 64'h50; check_pred(1'b1, "SETP_GE a>b");
        a = 64'h20; b = 64'h20; check_pred(1'b1, "SETP_GE a==b");
        a = 64'h10; b = 64'h20; check_pred(1'b0, "SETP_GE a<b");
        a = {32'd0,32'hFFFF_FFFF}; b = {32'd0,32'h0000_0001}; check_pred(1'b0, "SETP_GE -1<1");
        a = {32'd0,32'h0000_0001}; b = {32'd0,32'hFFFF_FFFF}; check_pred(1'b1, "SETP_GE 1>-1");
        a = {32'd0,32'hFFFF_FFFF}; b = {32'd0,32'hFFFF_FFFE}; check_pred(1'b1, "SETP_GE -1>=-2");

        // ---- default ----
        op = 5'b11111;
        a = 64'hCAFE_BABE_1234_5678; b = 64'd0;
        check_y(64'hCAFE_BABE_1234_5678, "DEFAULT passthrough");

        #5;
        $display("\n=== alu_i16x4: PASS=%0d  FAIL=%0d ===\n", pass_cnt, fail_cnt);
        $finish;
    end
endmodule
