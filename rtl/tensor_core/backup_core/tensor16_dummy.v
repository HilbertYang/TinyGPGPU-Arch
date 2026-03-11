`timescale 1ns / 1ps

module tensor16_dummy (
       input [15:0] fb16_A,
       input [15:0] fb16_B,
       input [15:0] fb16_C,
       input        op_mac,
       input        clk,
       input        reset,
       input        pc_reset,
       input        advance,

       output reg [15:0] result
);

always @(posedge clk) begin
    if (reset || pc_reset) begin
        result <= 16'b0;
    end
    else begin
        result <= op_mac ? fb16_C : fb16_A;
    end
end

endmodule