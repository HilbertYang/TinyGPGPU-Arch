// gpu_core_stub.v
// Placeholder gpu_core — satisfies gpu_top port interface
// Real logic TBD; this lets the full system compile & simulate now.

module gpu_core(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    output reg         done,

    // Kernel parameters (write-only from host side)
    input  wire        param_wr_en,
    input  wire [2:0]  param_wr_addr,
    input  wire [63:0] param_wr_data,

    // Data memory Port A (shared with host)
    output wire [7:0]  dmem_addr_a,
    output wire [63:0] dmem_din_a,
    output wire        dmem_we_a,
    output wire        dmem_en_a,
    input  wire [63:0] dmem_dout_a,

    // Instruction memory (read-only for core)
    output wire [8:0]  imem_addr,
    output wire        imem_en,
    input  wire [31:0] imem_dout
);
    // Tie off memory interfaces — no accesses from stub
    assign dmem_addr_a = 8'd0;
    assign dmem_din_a  = 64'd0;
    assign dmem_we_a   = 1'b0;
    assign dmem_en_a   = 1'b0;
    assign imem_addr   = 9'd0;
    assign imem_en     = 1'b0;

    // Minimal FSM: assert done 4 cycles after start
    reg [2:0] cnt;
    always @(posedge clk) begin
        if (reset) begin
            done <= 1'b0;
            cnt  <= 3'd0;
        end else if (done) begin
            // hold done until start de-asserts
            if (!start) begin
                done <= 1'b0;
                cnt  <= 3'd0;
            end
        end else if (start) begin
            if (cnt == 3'd4) begin
                done <= 1'b1;
            end else begin
                cnt <= cnt + 3'd1;
            end
        end
    end
endmodule