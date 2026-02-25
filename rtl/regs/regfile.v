// regfile.v
// 16 × 64-bit register file for custom GPU
// R0 is hardwired to zero
// Supports synchronous write, asynchronous read
// Each 64-bit register is viewed as 4 × 16-bit lanes for SIMD ops

module regfile(
    input  wire        clk,
    input  wire        rst_n,
    // Read port A
    input  wire [3:0]  rs1_addr,
    output wire [63:0] rs1_data,
    // Read port B
    input  wire [3:0]  rs2_addr,
    output wire [63:0] rs2_data,
    // Read port C (for store source / MAC accumulator)
    input  wire [3:0]  rs3_addr,
    output wire [63:0] rs3_data,
    // Write port
    input  wire        wr_en,
    input  wire [3:0]  wr_addr,
    input  wire [63:0] wr_data
);

    reg [63:0] regs [0:15];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin //write all reg with 0 when reset
            for (i = 0; i < 16; i = i + 1)
                regs[i] <= 64'd0;
        end else if (wr_en && wr_addr != 4'd0) begin
            regs[wr_addr] <= wr_data;
        end
    end

    // Async reads; R0 always 0
    assign rs1_data = (rs1_addr == 4'd0) ? 64'd0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 4'd0) ? 64'd0 : regs[rs2_addr];
    assign rs3_data = (rs3_addr == 4'd0) ? 64'd0 : regs[rs3_addr];

endmodule
