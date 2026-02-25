// param_regs.v
// Kernel parameter registers
// Stores up to 8 × 64-bit parameters loaded before kernel launch
// Maps to PTX: ld.param.u64 %rd1, [kernel_param_0]
//              ld.param.u32 %r2,  [kernel_param_3]

module param_regs(
    input  wire        clk,
    input  wire        rst_n,
    // Write interface (from host/ARM before kernel launch)
    input  wire        wr_en,
    input  wire [2:0]  wr_addr,   // param index 0-7
    input  wire [63:0] wr_data,
    // Read interface (from GPU decode stage)
    input  wire [2:0]  rd_addr,
    output wire [63:0] rd_data
);

    reg [63:0] params [0:7];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1)
                params[i] <= 64'd0;
        end else if (wr_en) begin
            params[wr_addr] <= wr_data;
        end
    end

    assign rd_data = params[rd_addr];

endmodule
