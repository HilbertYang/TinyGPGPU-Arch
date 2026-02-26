// alu_i16x4.v
// 4-lane 16-bit integer ALU
// Handles: ADD_I16, SUB_I16, MAX_I16 (ReLU = MAX with 0)
// Also handles 64-bit address arithmetic (ADD64, ADDI64, MUL_WIDE)
// and SETP_GE for predicate generation

module alu_i16x4(
    // 4-lane i16 inputs (packed in 64-bit)
    input  wire [63:0] a,        // RS1
    input  wire [63:0] b,        // RS2
    // 64-bit address/scalar inputs (same regs, full width)
    // func select
    input  wire [4:0]  op,       // ALU opcode

    // 4-lane i16 output
    output reg  [63:0] y,

    // Predicate output (for SETP_GE)
    output reg         pred_out
);

    // Unpack lanes
    wire signed [15:0] a0 = a[15:0];
    wire signed [15:0] a1 = a[31:16];
    wire signed [15:0] a2 = a[47:32];
    wire signed [15:0] a3 = a[63:48];

    wire signed [15:0] b0 = b[15:0];
    wire signed [15:0] b1 = b[31:16];
    wire signed [15:0] b2 = b[47:32];
    wire signed [15:0] b3 = b[63:48];

    // Opcode definitions (match gpu_cpu.v top-level)
    localparam OP_ADD_I16  = 5'b00100;
    localparam OP_SUB_I16  = 5'b00101;
    localparam OP_MAX_I16  = 5'b00110;
    localparam OP_ADD64    = 5'b01001;
    localparam OP_ADDI64   = 5'b01010;
    localparam OP_SETP_GE  = 5'b01100;
    localparam OP_MUL_WIDE = 5'b10000; // a * 2 → 64-bit (mul.wide.s32 %rd, %r, 2)

    reg signed [15:0] r0, r1, r2, r3;

    always @(*) begin
        y        = 64'd0;
        pred_out = 1'b0;
        r0 = 16'd0; r1 = 16'd0; r2 = 16'd0; r3 = 16'd0;

        case (op)
            OP_ADD_I16: begin
                r0 = a0 + b0;
                r1 = a1 + b1;
                r2 = a2 + b2;
                r3 = a3 + b3;
                y = {r3, r2, r1, r0};
            end

            OP_SUB_I16: begin
                r0 = a0 - b0;
                r1 = a1 - b1;
                r2 = a2 - b2;
                r3 = a3 - b3;
                y = {r3, r2, r1, r0};
            end

            OP_MAX_I16: begin
                r0 = (a0 > b0) ? a0 : b0;
                r1 = (a1 > b1) ? a1 : b1;
                r2 = (a2 > b2) ? a2 : b2;
                r3 = (a3 > b3) ? a3 : b3;
                y = {r3, r2, r1, r0};
            end

            OP_ADD64: begin
                // 64-bit address addition
                y = a + b;
            end

            OP_ADDI64: begin
                // 64-bit address + zero-extended b (imm already in b lower 12 bits)
                y = a + b;
            end

            OP_SETP_GE: begin
                // Compare lower 32 bits as signed (thread ID comparison)
                pred_out = ($signed(a[31:0]) >= $signed(b[31:0]));
                y = 64'd0;
            end

            OP_MUL_WIDE: begin
                // mul.wide.s32: rd = rs * 2 (byte offset from tid)
                // a[31:0] = tid, b = 2 (immediate)
                y = {{32{a[31]}}, a[31:0]} * {{32{b[31]}}, b[31:0]};
            end

            default: begin
                y = a;
            end
        endcase
    end

endmodule
