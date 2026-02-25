// tensor_core_bf16x4.v
// 4-lane BFloat16 Tensor Core
// Instantiates 4× pe_bf16_comb to process a full 64-bit register (4×bf16) in parallel
// op_mac=0: Y[i] = A[i] * B[i]          (vec_mul_bf16)
// op_mac=1: Y[i] = C[i] + A[i] * B[i]   (fma_bf16)

module tensor_core_bf16x4(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        op_mac,     // 0=MUL, 1=MAC
    input  wire [63:0] A,          // 4 × bf16 packed
    input  wire [63:0] B,          // 4 × bf16 packed
    input  wire [63:0] C,          // 4 × bf16 accumulator (for MAC)
    output wire        valid_out,
    output wire [63:0] Y           // 4 × bf16 result packed
);

    // Lane 0: bits [15:0]
    wire [15:0] y0;
    pe_bf16_comb PE0(
        .valid_in  (valid_in),
        .op_mac    (op_mac),
        .A         (A[15:0]),
        .B         (B[15:0]),
        .C         (C[15:0]),
        .valid_out (valid_out),   // all valid_out are same signal
        .Y         (y0)
    );

    // Lane 1: bits [31:16]
    wire [15:0] y1;
    wire        vo1;
    pe_bf16_comb PE1(
        .valid_in  (valid_in),
        .op_mac    (op_mac),
        .A         (A[31:16]),
        .B         (B[31:16]),
        .C         (C[31:16]),
        .valid_out (vo1),
        .Y         (y1)
    );

    // Lane 2: bits [47:32]
    wire [15:0] y2;
    wire        vo2;
    pe_bf16_comb PE2(
        .valid_in  (valid_in),
        .op_mac    (op_mac),
        .A         (A[47:32]),
        .B         (B[47:32]),
        .C         (C[47:32]),
        .valid_out (vo2),
        .Y         (y2)
    );

    // Lane 3: bits [63:48]
    wire [15:0] y3;
    wire        vo3;
    pe_bf16_comb PE3(
        .valid_in  (valid_in),
        .op_mac    (op_mac),
        .A         (A[63:48]),
        .B         (B[63:48]),
        .C         (C[63:48]),
        .valid_out (vo3),
        .Y         (y3)
    );

    assign Y = {y3, y2, y1, y0};

endmodule
