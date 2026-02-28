// gpu_core.v
// 5-Stage Pipelined GPU Core
//
// Pipeline: IF -> ID -> EX -> MEM -> WB
//
// Instruction Memory: I_M_32bit_512depth (32-bit wide, 512 deep)
// Data Memory:        D_M_64bit_256      (64-bit wide, 256 deep)
//
// Thread Model:
//   - TID register starts at 0, increments by 4 each iteration
//   - 4 lanes of 16-bit data packed in one 64-bit register
//   - byte_offset for one i16 element = TID * 2
//   - 64-bit load/store address uses word offset = TID/4
//     (since each 64-bit word contains 4 × i16 elements)
//
// ISA (5-bit opcode, 32-bit instruction):
//   [31:27]=OPCODE [26:23]=RD [22:19]=RS1 [18:15]=RS2 [14:0]=IMM15
//
// Opcodes:
//   NOP      = 5'h00
//   LD64     = 5'h01  RD = DMEM[RS1 + imm15]
//   ST64     = 5'h02  DMEM[RS1 + imm15] = RD
//   MOV      = 5'h03  RD = {imm15, ...}  (uses full lower 15 bits as imm)
//   ADD_I16  = 5'h04  RD[4xi16] = RS1[4xi16] + RS2[4xi16]
//   SUB_I16  = 5'h05  RD[4xi16] = RS1[4xi16] - RS2[4xi16]
//   MAX_I16  = 5'h06  RD[4xi16] = max(RS1[4xi16], RS2[4xi16])
//   MUL_BF16 = 5'h07  RD[4xbf16] = RS1 * RS2
//   MAC_BF16 = 5'h08  RD[4xbf16] = RS1 * RS2 + RS3(=RD)
//   ADD64    = 5'h09  RD = RS1 + RS2 (64-bit)
//   ADDI64   = 5'h0A  RD = RS1 + sign_ext(imm15)
//   BRA      = 5'h0B  if PRED: PC += sign_ext(imm15)
//   SETP_GE  = 5'h0C  PRED = (RS1[31:0] >= RS2[31:0])
//   MOV_TID  = 5'h0D  RD[31:0] = TID
//   RET      = 5'h0E  halt
//   LD_PARAM = 5'h0F  RD = PARAM[imm3]
//   MUL_WIDE = 5'h10  RD(64) = RS1(32,signed) * RS2(32,signed)

`timescale 1ns/1ps

module gpu_core(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,       // pulse to begin kernel execution
    output reg         done,        // asserted when RET reached

    // Kernel parameters (set by host before start)
    input  wire        param_wr_en,
    input  wire [2:0]  param_wr_addr,
    input  wire [63:0] param_wr_data,

    // Data memory interface (to D_M_64bit_256)
    output reg  [7:0]  dmem_addr_a,
    output reg  [63:0] dmem_din_a,
    output reg         dmem_we_a,
    output reg         dmem_en_a,
    input  wire [63:0] dmem_dout_a,

    // Instruction memory interface (to I_M_32bit_512depth)
    output wire  [8:0]  imem_addr,
    output wire         imem_en,
    input  wire [31:0] imem_dout
);

    //=========================================================
    // Opcode definitions
    //=========================================================
    localparam OP_NOP      = 5'h00;
    localparam OP_ADD_I16  = 5'h01;
    localparam OP_SUB_I16  = 5'h02;
    localparam OP_MAX_I16  = 5'h03;
    localparam OP_ADD64    = 5'h04;
    localparam OP_ADDI64   = 5'h05;
    localparam OP_SETP_GE  = 5'h06;
    localparam OP_MUL_WIDE = 5'h07;
    localparam OP_MUL_BF16 = 5'h08;
    localparam OP_MAC_BF16 = 5'h09;
    localparam OP_LD64     = 5'h10;
    localparam OP_ST64     = 5'h11;
    localparam OP_MOV      = 5'h12;
    localparam OP_BRA      = 5'h13;
    localparam OP_MOV_TID  = 5'h14;
    localparam OP_RET      = 5'h15;
    localparam OP_LD_PARAM = 5'h16;


    //=========================================================
    // Special registers
    //=========================================================
    reg [31:0] tid_reg;    // Thread ID, increments by 4 per iteration
    reg        pred_reg;   // Predicate register (1-bit)
    reg [8:0]  pc;         // Program counter (word address into I_M)
    reg [8:0]  pc_d;
    reg        run;    // Kernel is executing

    //=========================================================
    // Register file instantiation
    //=========================================================
    // Read ports (combinational / async)
    wire [63:0] rf_rs1_data;   // RS1 read result
    wire [63:0] rf_rs2_data;   // RS2 read result
    wire [63:0] rf_rs3_data;   // RS3 read result (RD for MAC accumulator)

    // Write port (driven from WB stage)
    wire        rf_wr_en  = wb_wr;
    wire [3:0]  rf_wr_addr = wb_addr[3:0];
    wire [63:0] rf_wr_data = wb_data;

    // Read addresses come from IF/ID instruction register (decoded in ID stage)
    wire [3:0]  rf_rs3_addr = ifid_instr[26:23]; // RD field (used as RS3 for MAC)
    wire [3:0]  rf_rs1_addr = ifid_instr[22:19]; // RS1 field
    wire [3:0]  rf_rs2_addr = ifid_instr[18:15]; // RS2 field
    

    regfile RF(
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rf_rs1_addr),
        .rs1_data (rf_rs1_data),
        .rs2_addr (rf_rs2_addr),
        .rs2_data (rf_rs2_data),
        .rs3_addr (rf_rs3_addr),
        .rs3_data (rf_rs3_data),
        .wr_en    (rf_wr_en),
        .wr_addr  (rf_wr_addr),
        .wr_data  (rf_wr_data)
    );

    //=========================================================
    // Parameter registers instantiation
    //=========================================================
    wire [63:0] param_rd_data;   // read result

    // Read address driven by ID stage (from imm field of LD_PARAM instruction)
    wire [2:0]  param_rd_addr = ifid_instr[2:0];

    param_regs PARAMS(
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (param_wr_en),
        .wr_addr  (param_wr_addr),
        .wr_data  (param_wr_data),
        .rd_addr  (param_rd_addr),
        .rd_data  (param_rd_data)
    );

    //=========================================================
    // ALU instantiation (combinational)
    //=========================================================
    reg  [63:0] alu_a, alu_b;
    reg  [4:0]  alu_op;
    wire [63:0] alu_y;
    wire        alu_pred;

    alu_i16x4 ALU(
        .a        (alu_a),
        .b        (alu_b),
        .op       (alu_op),
        .y        (alu_y),
        .pred_out (alu_pred)
    );

    //=========================================================
    // Tensor Core instantiation (combinational, valid always 1)
    //=========================================================
    reg  [63:0] tc_a, tc_b, tc_c;
    reg         tc_op_mac;
    wire [63:0] tc_y;

    tensor_core_bf16x4 TC(
        .op_mac    (tc_op_mac),
        .A         (tc_a),
        .B         (tc_b),
        .C         (tc_c),
        .Y         (tc_y)
    );

    //=========================================================
    // Pipeline Registers
    //=========================================================

    // --- IF/ID Pipeline Register ---
    reg [31:0] ifid_instr;
    reg [8:0]  ifid_pc;
    reg        ifid_valid;

    // --- ID/EX Pipeline Register ---
    reg [4:0]  idex_op;
    reg [3:0]  idex_rd;
    reg [63:0] idex_rs1_val, idex_rs2_val, idex_rs3_val;
    reg [11:0] idex_imm12;
    reg [16:0] idex_imm17;       // for MOV
    reg [63:0] idex_param_val;   // latched param value (from param_regs read in ID)
    reg [8:0]  idex_pc;
    reg        idex_valid;
    reg        idex_use_pred;

    // --- EX/MEM Pipeline Register ---
    reg [4:0]  exmem_op;
    reg [3:0]  exmem_rd;
    reg [63:0] exmem_alu_result;
    reg [63:0] exmem_rs3_val;   // store data
    reg [8:0]  exmem_pc_branch; // branch target
    reg        exmem_branch_taken;
    reg        exmem_valid;
    reg        exmem_pred_update;
    reg        exmem_pred_val;
    reg        exmem_halt;

    // --- MEM/WB Pipeline Register ---
    reg [4:0]  memwb_op;
    reg [3:0]  memwb_rd;
    reg [63:0] memwb_result;
    reg        memwb_valid;
    reg        memwb_halt;

    //=========================================================
    // Forwarding / stall signals
    //=========================================================
    // Simple: stall one cycle for LD64 → dependent instruction
    reg stall_if_id; // insert bubble after LD64

    //=========================================================
    // WB 
    //=========================================================
    wire [63:0] wb_data = memwb_result;
    wire [3:0]  wb_addr = memwb_rd;
    wire        wb_wr   = memwb_valid && (
                    memwb_op != OP_ST64 &&
                    memwb_op != OP_BRA  &&
                    memwb_op != OP_RET  &&
                    memwb_op != OP_NOP  &&
                    memwb_op != OP_SETP_GE
                  );
        
    //=========================================================
    // ID
    //=========================================================
    assign imem_en      = 1'b1;
    assign imem_addr    = pc;

    //=========================================================
    // Pipeline control
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc         <= 9'd0;
            tid_reg    <= 32'd0;
            pred_reg   <= 1'b0;
            run    <= 1'b0;
            done       <= 1'b0;
            stall_if_id <= 1'b0;

            ifid_valid  <= 1'b0;
            idex_valid  <= 1'b0;
            exmem_valid <= 1'b0;
            memwb_valid <= 1'b0;

            imem_we  <= 1'b0;
            imem_din <= 32'd0;
            dmem_we_a <= 1'b0;
            dmem_en_a <= 1'b0;
            dmem_din_a <= 64'd0;
            dmem_addr_a <= 8'd0;

        end else begin

            // Default memory control
            dmem_we_a   <= 1'b0;
            dmem_en_a   <= 1'b0;
            imem_we     <= 1'b0;

            //=====================================================
            // Start signal: reset PC and thread state
            //=====================================================
            if (start && !run) begin
                run   <= 1'b1;
                done      <= 1'b0;
                pc        <= 9'd0;
                tid_reg   <= 32'd0;
                pred_reg  <= 1'b0;
                ifid_valid  <= 1'b0;
                idex_valid  <= 1'b0;
                exmem_valid <= 1'b0;
                memwb_valid <= 1'b0;
            end

            //=====================================================
            // WB Stage
            //=====================================================
            if (memwb_valid) begin
                if (memwb_halt) begin
                    run     <= 1'b0;
                    done        <= 1'b1;
                    memwb_valid <= 1'b0;
                end
            end

            //=====================================================
            // MEM Stage → WB
            //=====================================================
            memwb_valid <= exmem_valid;
            memwb_halt  <= exmem_halt;
            memwb_op    <= exmem_op;
            memwb_rd    <= exmem_rd;

            if (exmem_valid) begin
                case (exmem_op)
                    OP_LD64: begin
                        // Address computed in EX, fire memory read
                        dmem_addr_a <= exmem_alu_result[9:2]; // word address (8-byte aligned)
                        dmem_en_a   <= 1'b1;
                        memwb_result <= dmem_dout_a; // will be ready next cycle (0 pipe stages)
                    end
                    OP_ST64: begin
                        dmem_addr_a <= exmem_alu_result[9:2];
                        dmem_din_a  <= exmem_rs2_val;
                        dmem_we_a   <= 1'b1;
                        dmem_en_a   <= 1'b1;
                        memwb_result <= 64'd0;
                    end
                    default: begin
                        memwb_result <= exmem_alu_result;
                    end
                endcase

                // Predicate update in MEM stage (was computed in EX)
                if (exmem_pred_update)
                    pred_reg <= exmem_pred_val;
            end else begin
                memwb_result <= 64'd0;
            end

            //=====================================================
            // EX Stage → EX/MEM
            //=====================================================
            exmem_valid        <= idex_valid && !stall_if_id;
            exmem_halt         <= 1'b0;
            exmem_branch_taken <= 1'b0;
            exmem_pred_update  <= 1'b0;

            if (idex_valid && !stall_if_id) begin
                exmem_op   <= idex_op;
                exmem_rd   <= idex_rd;
                exmem_rs2_val <= idex_rs2_val;

                // Setup ALU inputs (drive combinational ALU)
                alu_op <= idex_op;
                alu_a  <= idex_rs1_val;
                alu_b  <= idex_rs2_val;

                // Setup Tensor Core inputs
                tc_a      <= idex_rs1_val;
                tc_b      <= idex_rs2_val;
                tc_c      <= idex_rs3_val;
                tc_op_mac <= (idex_op == OP_MAC_BF16) ? 1'b1 : 1'b0;

                case (idex_op)
                    OP_NOP: begin
                        exmem_alu_result <= 64'd0;
                    end

                    OP_ADD_I16, OP_SUB_I16, OP_MAX_I16,
                    OP_ADD64, OP_MUL_WIDE: begin
                        exmem_alu_result <= alu_y;
                    end

                    OP_ADDI64: begin
                        // RS1 + sign_extended imm12
                        exmem_alu_result <= idex_rs1_val +
                            {{52{idex_imm12[11]}}, idex_imm12};
                    end

                    OP_LD64: begin
                        // Compute memory address: RS1 + imm12
                        exmem_alu_result <= idex_rs1_val +
                            {{52{idex_imm12[11]}}, idex_imm12};
                    end

                    OP_ST64: begin
                        // Compute memory address: RS1 + imm12
                        exmem_alu_result <= idex_rs1_val +
                            {{52{idex_imm12[11]}}, idex_imm12};
                    end

                    OP_MOV: begin
                        // RD = zero_ext(imm17)
                        exmem_alu_result <= {47'd0, idex_imm17};
                    end

                    OP_MOV_TID: begin
                        exmem_alu_result <= {32'd0, tid_reg};
                    end

                    OP_LD_PARAM: begin
                        exmem_alu_result <= idex_param_val;
                    end

                    OP_SETP_GE: begin
                        exmem_alu_result <= 64'd0;
                        exmem_pred_update <= 1'b1;
                        exmem_pred_val    <= alu_pred;
                    end

                    OP_BRA: begin
                        if (pred_reg) begin
                            // branch taken: target = idex_pc + sign_ext(imm12)
                            exmem_branch_taken <= 1'b1;
                            exmem_pc_branch    <= idex_pc +
                                {{3{idex_imm12[11]}}, idex_imm12} - 9'd2;
                                // -2 because IF already incremented
                        end
                        exmem_alu_result <= 64'd0;
                    end

                    OP_MUL_BF16: begin
                        exmem_alu_result <= tc_y;
                    end

                    OP_MAC_BF16: begin
                        exmem_alu_result <= tc_y;
                    end

                    OP_RET: begin
                        exmem_halt       <= 1'b1;
                        exmem_alu_result <= 64'd0;
                    end

                    default: begin
                        exmem_alu_result <= 64'd0;
                    end
                endcase

            end else begin
                exmem_op  <= OP_NOP;
                exmem_rd  <= 4'd0;
                exmem_alu_result <= 64'd0;
            end

            // Handle branch: flush IF and ID, redirect PC
            if (exmem_branch_taken) begin
                pc          <= exmem_pc_branch;
                ifid_valid  <= 1'b0;
                idex_valid  <= 1'b0;
            end

            //=====================================================
            // ID Stage → ID/EX
            //=====================================================
            idex_valid <= ifid_valid && !stall_if_id;

            if (ifid_valid && !stall_if_id) begin
                // Decode
                idex_op       <= ifid_instr[31:27];
                idex_rd       <= ifid_instr[26:23];
                idex_imm15    <= ifid_instr[14:0];
                idex_pc       <= ifid_pc;

                idex_param_val <= param_rd_data; 
                
                idex_rs1_val  <= rf_rs1_data;
                idex_rs2_val  <= rf_rs2_data;
                idex_rs3_val  <= rf_rs3_data; 

                //Stall
                if (exmem_valid && exmem_op == OP_LD64 &&
                    (exmem_rd == ifid_instr[21:18] ||
                     exmem_rd == ifid_instr[16:13])) begin
                    stall_if_id <= 1'b1;
                    idex_valid  <= 1'b0;
                end else begin
                    stall_if_id <= 1'b0;
                end

            end else if (!stall_if_id) begin
                idex_op  <= OP_NOP;
                idex_rd  <= 4'd0;
                idex_valid <= 1'b0;
            end

            //=====================================================
            // IF Stage → IF/ID
            //=====================================================
            if (run && !stall_if_id && !exmem_branch_taken && !done) begin
                ifid_instr <= imem_dout;
                pc_d       <=pc;
                ifid_pc    <= pc_d;
                ifid_valid <= 1'b1;

                if (!exmem_branch_taken)begin
                    pc <= pc + 9'd1;
                end else begin
                    pc <= branch_addr;
                end
            end else if (stall_if_id) begin
                // Hold IF/ID, replay
            end else begin
                ifid_valid <= 1'b0;
            end

        end // else rst
    end // always

endmodule
