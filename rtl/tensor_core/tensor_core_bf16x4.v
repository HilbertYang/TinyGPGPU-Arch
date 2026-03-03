// tensor_core_bf16x4.v
// 4-lane BFloat16 Tensor Core - purely combinational
// op_mac=0 : Y[i] = A[i] * B[i]
// op_mac=1 : Y[i] = C[i] + A[i] * B[i]

module tensor_core_bf16x4(
    input  wire        op_mac,     // 0=MUL, 1=MAC
    input  wire [63:0] A,          // 4 × bf16 packed [lane3|lane2|lane1|lane0]
    input  wire [63:0] B,          // 4 × bf16 packed
    input  wire [63:0] C,          // 4 × bf16 accumulator (used when op_mac=1)
    output wire [63:0] Y           // 4 × bf16 result packed
);

    wire [15:0] y0, y1, y2, y3;

    tensor16 PE0 (
        .op_mac      (op_mac),
        .fb16_A      (A[15:0]),
        .fb16_B      (B[15:0]),
        .fb16_C      (C[15:0]),
        .result      (y0)
    );

       
    tensor16 PE1 (
        .op_mac (op_mac),
        .fb16_A      (A[31:16]),
        .fb16_B      (B[31:16]),
        .fb16_C      (C[31:16]),
        .result      (y1)
    );

    tensor16 PE2 (
        .op_mac (op_mac),
        .fb16_A      (A[47:32]),
        .fb16_B      (B[47:32]),
        .fb16_C      (C[47:32]),
        .result      (y2)
    );

    tensor16 PE3 (
        .op_mac (op_mac),
        .fb16_A      (A[63:48]),
        .fb16_B      (B[63:48]),
        .fb16_C      (C[63:48]),
        .result      (y3)
    );

    assign Y = {y3, y2, y1, y0};

endmodule