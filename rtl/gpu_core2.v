// gpu_core.v
// 5-Stage Pipelined GPU Core
//
// Pipeline: IF -> ID -> EX -> MEM -> WB
//
// Instruction Memory: I_M_32bit_512depth (32-bit wide, 512 deep)
// Data Memory:        D_M_64bit_256      (64-bit wide, 256 deep)
// Regfile    :        regfile            (64-bit wide, 16 deep )
// Paramreg    :       param_regs         (64-bit wide, 8 deep  )
//
// Thread Model:
//   - TID register starts at 0, increments by 4 each iteration
//   - 4 lanes of 16-bit data packed in one 64-bit register
//   - 64-bit load/store address uses word offset = TID/4
//     (since each 64-bit word contains 4 × i16 elements)
//
// ISA (5-bit opcode, 32-bit instruction):
//   [31:27]=OPCODE [26:23]=RD [22:19]=RS1 [18:15]=RS2 [14:0]=IMM15
//
// Opcodes:
//   NOP      = 5'h00
//   ADD_I16  = 5'h01  RD[4xi16] = RS1[4xi16] + RS2[4xi16]
//   SUB_I16  = 5'h02  RD[4xi16] = RS1[4xi16] - RS2[4xi16]
//   MAX_I16  = 5'h03  RD[4xi16] = max(RS1[4xi16], RS2[4xi16])
//   ADD64    = 5'h04  RD = RS1 + RS2 (64-bit)
//   ADDI64   = 5'h05  RD = RS1 + sign_ext(imm15)
//   SETP_GE  = 5'h06  PRED = (RS1[31:0] >= RS2[31:0])
//   SHIFTLV  = 5'h07  RD = RS1  <<< imm15;
//   SHIFTRV  = 5'h08. RD = RS1  >>> imm15;
//   MAC_BF16 = 5'h09  RD[4xbf16] = RS1 * RS2 + RS3(=RD)
//   MUL_BF16 = 5'h0a  RD[4xbf16] = RS1 * RS2
//   LD64     = 5'h10  RD = DMEM[RS1 + imm15]
//   ST64     = 5'h11  DMEM[RS1 + imm15] = RD
//   MOV      = 5'h12  RD = signed extend(imm15)
//   BPR      = 5'h13  if PRED: PC = imm15[8:0]
//   BR       = 5‘h14  Directly jump to pc = imm15[8:0]
//   RET      = 5'h15  halt
//   LD_PARAM = 5'h16  RD = PARAM[imm3]
`timescale 1ns/1ps
module gpu_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start, 
    output wire         done, 

    input  wire        param_wr_en,
    input  wire [2:0]  param_wr_addr,
    input  wire [63:0] param_wr_data,


    output wire  [7:0]  dmem_addr_a,
    output wire  [63:0] dmem_din_a,
    output wire         dmem_we_a,
    output wire         dmem_en_a,
    input  wire [63:0] dmem_dout_a,


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
    localparam OP_SHIFTLV  = 5'h07;
    localparam OP_SHIFTRV  = 5'h08;
    localparam OP_MAC_BF16 = 5'h09;
    localparam OP_MUL_BF16 = 5'h0a;
    localparam OP_LD64     = 5'h10;
    localparam OP_ST64     = 5'h11;
    localparam OP_MOV      = 5'h12;
    localparam OP_BPR      = 5'h13;
    localparam OP_BR       = 5'h14;
    localparam OP_RET      = 5'h15;
    localparam OP_LD_PARAM = 5'h16;

    //==========================================================
    // Pipeline control signal
    //==========================================================
    reg     run;
    reg     done_r;
    reg     start_d;
    wire    start_pulse = start & ~start_d;
    wire    ret_in_wb = memwb_is_ret;
    assign  done = done_r; 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run     <= 1'b0;
            done_r  <= 1'b0;
            start_d <= 1'b0;
        end else begin
            start_d <= start;
            done_r <= 1'b0;
            if (start_pulse && !run) begin
                run    <= 1'b1;
                done_r <= 1'b0;
            end
            if (run && ret_in_wb) begin
                run    <= 1'b0;
                done_r <= 1'b1; 
            end
        end
    end
    //==========================================================
    // IF stage
    //==========================================================
    reg [8:0]  pc; 

    //pc update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc   <= 9'd0;
        end else if (start_pulse) begin
            pc   <= 9'd0;
        end else if (run) begin
            if (branch_taken) begin
                pc   <= branch_target;
            end else begin
                pc   <= pc + 9'd1;
            end
        end
    end

    //connect to Imem
    assign imem_addr = pc;
    assign imem_en = run;

    // --- IF/ID Pipeline Register ---
    reg [31:0] ifid_instr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || branch_taken) begin
            ifid_instr <= 32'd0;   // NOP on reset or branch flush
        end else if(run) begin
            ifid_instr <= imem_dout;
        end
    end

    //==========================================================
    // ID stage
    //==========================================================
    wire [4:0]  id_op  = ifid_instr[31:27];

    //control unit
    wire [3:0]  id_rd_addr;
    wire [3:0]  id_rs1_addr_cu;
    wire [3:0]  id_rs2_addr_cu;
    wire [14:0] id_imm15_cu;
    wire [2:0]  id_param_addr;

    wire [4:0]  id_op_alu;
    wire        id_use_tc;
    wire        id_op_tc;
    wire        id_use_imm;
    wire        id_mem_rd_en;
    wire        id_mem_wr_en;
    wire        id_rf_wr_en;
    wire [1:0]  id_wb_sel;
    wire        id_pred_wr_en;
    wire        id_is_bpr;
    wire        id_is_branch;
    wire        id_is_ret;

    control_unit CU(
        .instr      (ifid_instr),
        // Decoded register addresses
        .rd_addr    (id_rd_addr),
        .rs1_addr   (id_rs1_addr_cu),
        .rs2_addr   (id_rs2_addr_cu),
        .imm15      (id_imm15_cu),
        .param_addr (id_param_addr),
        // EX stage control
        .op_alu     (id_op_alu),
        .use_tc     (id_use_tc),
        .op_tc      (id_op_tc),
        .use_imm    (id_use_imm),
        // MEM stage control
        .mem_rd_en  (id_mem_rd_en),
        .mem_wr_en  (id_mem_wr_en),
        // WB stage control
        .rf_wr_en   (id_rf_wr_en),
        .wb_sel     (id_wb_sel),
        // Special / branch control
        .pred_wr_en (id_pred_wr_en),
        .is_bpr     (id_is_bpr),
        .is_branch  (id_is_branch),
        .is_ret     (id_is_ret)
    );

    //RF
    wire [63:0] wb_data;
    wire [3:0]  wb_addr;
    wire        wb_wr_en;

    wire [63:0] id_rs1_data;   // RS1 read result
    wire [63:0] id_rs2_data;   // RS2 read result
    wire [63:0] id_rs3_data;   // RS3 read result (RD)

    wire [3:0]  id_rs1_addr = id_rs1_addr_cu; 
    wire [3:0]  id_rs2_addr = id_rs2_addr_cu; 
    wire [3:0]  id_rs3_addr = id_rd_addr;

    regfile RF(
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs1_data (id_rs1_data),
        .rs2_addr (id_rs2_addr),
        .rs2_data (id_rs2_data),
        .rs3_addr (id_rs3_addr),
        .rs3_data (id_rs3_data),
        .wr_en    (wb_wr_en),
        .wr_addr  (wb_addr),
        .wr_data  (wb_data)
    );

    //Param RF
    wire [63:0] id_param_rd_data;   // param read result

    param_regs PARAMS(
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (param_wr_en),
        .wr_addr  (param_wr_addr),
        .wr_data  (param_wr_data),
        .rd_addr  (id_param_addr),
        .rd_data  (id_param_rd_data)
    );

    // --- ID/EX Pipeline Register ---
    reg [4:0]  idex_op;
    reg [3:0]  idex_rd_addr;
    reg [14:0] idex_imm15;
    reg [63:0] idex_rs1_val, idex_rs2_val, idex_rs3_val;
    reg [63:0] idex_param_val;
    // Control signals from CU
    reg [4:0]  idex_op_alu;
    reg        idex_use_tc;
    reg        idex_op_tc;
    reg        idex_use_imm;
    reg        idex_mem_rd_en;
    reg        idex_mem_wr_en;
    reg        idex_rf_wr_en;
    reg [1:0]  idex_wb_sel;
    reg        idex_pred_wr_en;
    reg        idex_is_bpr;
    reg        idex_is_branch;
    reg        idex_is_ret;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || branch_taken) begin   // flush on branch
            idex_op         <= 5'd0;
            idex_rd_addr    <= 4'd0;
            idex_imm15      <= 15'd0;
            idex_rs1_val    <= 64'd0;
            idex_rs2_val    <= 64'd0;
            idex_rs3_val    <= 64'd0;
            idex_param_val  <= 64'd0;
            idex_op_alu     <= 5'd0;
            idex_use_tc     <= 1'b0;
            idex_op_tc      <= 1'b0;
            idex_use_imm    <= 1'b0;
            idex_mem_rd_en  <= 1'b0;
            idex_mem_wr_en  <= 1'b0;
            idex_rf_wr_en   <= 1'b0;
            idex_wb_sel     <= 2'd0;
            idex_pred_wr_en <= 1'b0;
            idex_is_bpr     <= 1'b0;
            idex_is_branch  <= 1'b0;
            idex_is_ret     <= 1'b0;
        end else if (run) begin
            idex_op         <= id_op;
            idex_rd_addr    <= id_rd_addr;
            idex_imm15      <= id_imm15_cu;
            idex_rs1_val    <= id_rs1_data;
            idex_rs2_val    <= id_rs2_data;
            idex_rs3_val    <= id_rs3_data;
            idex_param_val  <= id_param_rd_data;
            idex_op_alu     <= id_op_alu;
            idex_use_tc     <= id_use_tc;
            idex_op_tc      <= id_op_tc;
            idex_use_imm    <= id_use_imm;
            idex_mem_rd_en  <= id_mem_rd_en;
            idex_mem_wr_en  <= id_mem_wr_en;
            idex_rf_wr_en   <= id_rf_wr_en;
            idex_wb_sel     <= id_wb_sel;
            idex_pred_wr_en <= id_pred_wr_en;
            idex_is_bpr     <= id_is_bpr;
            idex_is_branch  <= id_is_branch;
            idex_is_ret     <= id_is_ret;
        end
    end
    //==========================================================
    // EX stage
    //==========================================================
    // sign-extend imm15 to 64 bits for ADDI64/SHIFTLV/SHIFTRV
    wire [63:0] ex_imm64 = {{49{idex_imm15[14]}}, idex_imm15};

    //tensor core x4
    wire [63:0] tc_a    = idex_rs1_val;
    wire [63:0] tc_b    = idex_rs2_val;
    wire [63:0] tc_c    = idex_rs3_val;   // RD for MAC accumulation
    wire        tc_op_mac = idex_op_tc;
    wire [63:0] tc_y;
    tensor_core_bf16x4 TC(
        .op_mac    (tc_op_mac),
        .A         (tc_a),
        .B         (tc_b),
        .C         (tc_c),
        .Y         (tc_y)
    );

    //alu x4
    wire [63:0] alu_a  = idex_rs1_val;
    wire [63:0] alu_b  = idex_use_imm ? ex_imm64 : idex_rs2_val;
    wire [4:0]  alu_op = idex_op_alu;
    wire [63:0] alu_y;
    wire        alu_pred;

    alu_i16x4 ALU(
        .a        (alu_a),
        .b        (alu_b),
        .op       (alu_op),
        .y        (alu_y),
        .pred_out (alu_pred)
    );

    // Predicate register (written at end of EX stage)
    reg pred_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pred_reg <= 1'b0;
        else if (idex_pred_wr_en)
            pred_reg <= alu_pred;
    end

    // Branch decision (resolved in EX stage)
    wire        branch_taken  = idex_is_branch || (idex_is_bpr && pred_reg);
    wire [8:0]  branch_target = idex_imm15[8:0];

    // --- EX/MEM Pipeline Register ---
    reg [3:0]  exmem_rd_addr;
    reg [63:0] exmem_alu_y;
    reg [63:0] exmem_tc_y;
    reg [63:0] exmem_rs3_val;   // ST64 store data (RD field)
    reg [63:0] exmem_imm_or_param; // MOV / LD_PARAM writeback data
    reg        exmem_pred;
    reg        exmem_mem_rd_en;
    reg        exmem_mem_wr_en;
    reg        exmem_rf_wr_en;
    reg [1:0]  exmem_wb_sel;
    reg        exmem_pred_wr_en;
    reg        exmem_is_ret;

    // IMM/PARAM mux: MOV uses sign-ext imm15, LD_PARAM uses param value
    wire [63:0] ex_imm_or_param = idex_use_imm ? ex_imm64 : idex_param_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_rd_addr      <= 4'd0;
            exmem_alu_y        <= 64'd0;
            exmem_tc_y         <= 64'd0;
            exmem_rs3_val      <= 64'd0;
            exmem_imm_or_param <= 64'd0;
            exmem_pred         <= 1'b0;
            exmem_mem_rd_en    <= 1'b0;
            exmem_mem_wr_en    <= 1'b0;
            exmem_rf_wr_en     <= 1'b0;
            exmem_wb_sel       <= 2'd0;
            exmem_pred_wr_en   <= 1'b0;
            exmem_is_ret       <= 1'b0;
        end else if (run) begin
            exmem_rd_addr      <= idex_rd_addr;
            exmem_alu_y        <= alu_y;
            exmem_tc_y         <= tc_y;
            exmem_rs3_val      <= idex_rs3_val;   // RD value for ST64
            exmem_imm_or_param <= ex_imm_or_param;
            exmem_pred         <= alu_pred;
            exmem_mem_rd_en    <= idex_mem_rd_en;
            exmem_mem_wr_en    <= idex_mem_wr_en;
            exmem_rf_wr_en     <= idex_rf_wr_en;
            exmem_wb_sel       <= idex_wb_sel;
            exmem_pred_wr_en   <= idex_pred_wr_en;
            exmem_is_ret       <= idex_is_ret;
        end
    end

    //==========================================================
    // MEM stage
    //==========================================================
    // DMEM address comes from ALU (RS1 + imm15 already computed in EX)
    assign dmem_addr_a = exmem_alu_y[7:0];
    assign dmem_din_a  = exmem_rs3_val;
    assign dmem_we_a   = exmem_mem_wr_en;
    assign dmem_en_a   = exmem_mem_rd_en | exmem_mem_wr_en;

    // --- MEM/WB Pipeline Register ---
    reg [3:0]  memwb_rd_addr;
    reg [63:0] memwb_alu_y;
    reg [63:0] memwb_tc_y;
    reg [63:0] memwb_imm_or_param;
    reg        memwb_rf_wr_en;
    reg [1:0]  memwb_wb_sel;
    reg        memwb_is_ret;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_rd_addr      <= 4'd0;
            memwb_alu_y        <= 64'd0;
            memwb_tc_y         <= 64'd0;
            memwb_imm_or_param <= 64'd0;
            memwb_rf_wr_en     <= 1'b0;
            memwb_wb_sel       <= 2'd0;
            memwb_is_ret <= 1'b0;
        end else if (run) begin
            memwb_rd_addr      <= exmem_rd_addr;
            memwb_alu_y        <= exmem_alu_y;
            memwb_tc_y         <= exmem_tc_y;
            memwb_imm_or_param <= exmem_imm_or_param;
            memwb_rf_wr_en     <= exmem_rf_wr_en;
            memwb_wb_sel       <= exmem_wb_sel;
            memwb_is_ret       <= exmem_is_ret;
        end
    end

    //==========================================================
    // WB stage
    //==========================================================
    localparam WB_ALU = 2'd0;
    localparam WB_TC  = 2'd1;
    localparam WB_MEM = 2'd2;
    localparam WB_IMM = 2'd3;

    reg [63:0] wb_data_mux;
    always @(*) begin
        case (memwb_wb_sel)
            WB_ALU:  wb_data_mux = memwb_alu_y;
            WB_TC:   wb_data_mux = memwb_tc_y;
            WB_MEM:  wb_data_mux = dmem_dout_a;
            WB_IMM:  wb_data_mux = memwb_imm_or_param;
            default: wb_data_mux = memwb_alu_y;
        endcase
    end

    assign wb_data  = wb_data_mux;
    assign wb_addr  = memwb_rd_addr;
    assign wb_wr_en = memwb_rf_wr_en;

endmodule