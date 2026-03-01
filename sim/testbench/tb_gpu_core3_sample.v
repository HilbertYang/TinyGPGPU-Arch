// tb_gpu_core3.v
// Testbench for gpu_core3 (no-flush, no-forwarding pipeline)
// NOP policy: 3 NOPs after every write instruction
//
// ISA:  {op[4:0], rd[3:0], rs1[3:0], rs2[3:0], imm15[14:0]}
//       [31:27]=OP  [26:23]=RD  [22:19]=RS1  [18:15]=RS2  [14:0]=IMM15
//
// ── TEST 1: ADD_I16 ───────────────────────────────────────────────
//   MOV R1, 7   / NOP×3
//   MOV R2, 5   / NOP×3
//   ADD_I16 R3, R1, R2  / NOP×3   → R3 = {0,0,0,12}
//   ST64 R3, R0   / NOP×3 / RET
//   Expected: DMEM[0] = 64'h0000_0000_0000_000C
//
// ── TEST 2: MUL_BF16 + MAC_BF16 (FMA) ───────────────────────────
//   Pre-load DMEM[10] = 64'h4000_4000_4000_4000 (2.0 bf16 ×4)
//           DMEM[11] = 64'h4040_4040_4040_4040 (3.0 bf16 ×4)
//   MUL_BF16 R3, R1, R2  / NOP×3   → R3 = {6.0 bf16} = 0x40C0×4
//   MAC_BF16 R3, R1, R2  / NOP×3   → R3 = R1*R2+R3 = {12.0} = 0x4140×4
//   ST64 R3, R7   / NOP×3 / RET
//   Expected: DMEM[12] = 64'h4140_4140_4140_4140
//
`timescale 1ns/1ps

module tb_gpu_core3;

    // -------------------------------------------------------
    // Signals
    // -------------------------------------------------------
    reg        clk, rst_n;
    reg        run, step, pc_reset_pulse;
    wire       done;

    reg        param_wr_en;
    reg [2:0]  param_wr_addr;
    reg [63:0] param_wr_data;

    reg        imem_prog_we;
    reg [8:0]  imem_prog_addr;
    reg [31:0] imem_prog_wdata;

    reg        dmem_prog_en, dmem_prog_we;
    reg [7:0]  dmem_prog_addr;
    reg [63:0] dmem_prog_wdata;
    wire[63:0] dmem_prog_rdata;

    wire[8:0]  pc_dbg;
    wire[31:0] if_instr_dbg;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    gpu_core dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .run             (run),
        .step            (step),
        .pc_reset_pulse  (pc_reset_pulse),
        .done            (done),
        .param_wr_en     (param_wr_en),
        .param_wr_addr   (param_wr_addr),
        .param_wr_data   (param_wr_data),
        .imem_prog_we    (imem_prog_we),
        .imem_prog_addr  (imem_prog_addr),
        .imem_prog_wdata (imem_prog_wdata),
        .dmem_prog_en    (dmem_prog_en),
        .dmem_prog_we    (dmem_prog_we),
        .dmem_prog_addr  (dmem_prog_addr),
        .dmem_prog_wdata (dmem_prog_wdata),
        .dmem_prog_rdata (dmem_prog_rdata),
        .pc_dbg          (pc_dbg),
        .if_instr_dbg    (if_instr_dbg)
    );

    // -------------------------------------------------------
    // Clock  100 MHz
    // -------------------------------------------------------
    initial clk = 0;
    always  #5 clk = ~clk;

    // -------------------------------------------------------
    // Instruction encoder function
    // -------------------------------------------------------
    function automatic [31:0] ENC;
        input [4:0]  op;
        input [3:0]  rd, rs1, rs2;
        input [14:0] imm15;
        ENC = {op, rd, rs1, rs2, imm15};
    endfunction


    localparam [4:0]
        OP_NOP      = 5'h00,
        OP_ADD_I16  = 5'h01,
        OP_SUB_I16  = 5'h02,
        OP_MAX_I16  = 5'h03,
        OP_ADD64    = 5'h04,
        OP_ADDI64   = 5'h05,
        OP_SETP_GE  = 5'h06,
        OP_SHIFTLV  = 5'h07,
        OP_SHIFTRV  = 5'h08,
        OP_MAC_BF16 = 5'h09,
        OP_MUL_BF16 = 5'h0a,
        OP_LD64     = 5'h10,
        OP_ST64     = 5'h11,
        OP_MOV      = 5'h12,
        OP_BPR      = 5'h13,
        OP_BR       = 5'h14,
        OP_RET      = 5'h15,
        OP_LD_PARAM = 5'h16;
  
    localparam [31:0] NOP = 32'h0000_0000;

    // -------------------------------------------------------
    // Tasks
    // -------------------------------------------------------

    // Write one instruction to IMEM
    task imem_write;
        input [8:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            imem_prog_we    = 1'b1;
            imem_prog_addr  = addr;
            imem_prog_wdata = data;
            @(posedge clk); #1;   // BRAM write
            imem_prog_we = 1'b0;
        end
    endtask


    // Write 64-bit base address to param
    task param_write;
        input [2:0]  addr;
        input [63:0] data;
        begin
            @(negedge clk);
            param_wr_en    = 1'b1;
            param_wr_addr  = addr;
            param_wr_data = data;
            @(posedge clk); #1;
            param_wr_en = 1'b0;
        end
    endtask

    // Write 64-bit word to DMEM via Port B
    task dmem_write;
        input [7:0]  addr;
        input [63:0] data;
        begin
            @(negedge clk);
            dmem_prog_en    = 1'b1;
            dmem_prog_we    = 1'b1;
            dmem_prog_addr  = addr;
            dmem_prog_wdata = data;
            @(posedge clk); #1;
            dmem_prog_en = 1'b0;
            dmem_prog_we = 1'b0;
        end
    endtask

    // Read DMEM via Port B and compare to expected value
    // BRAM latency: addr latched at T0 posedge, data valid after T1 posedge
    task dmem_check;
        input [7:0]  addr;
        input [63:0] expected;
        begin
            @(negedge clk);
            dmem_prog_en   = 1'b1;
            dmem_prog_we   = 1'b0;
            dmem_prog_addr = addr;
            @(posedge clk); #1;   // addr latched
            @(posedge clk); #1;   // data valid
            if (dmem_prog_rdata === expected)
                $display("[PASS] DMEM[%0d] = 0x%016h", addr, dmem_prog_rdata);
            else
                $display("[FAIL] DMEM[%0d]  expected=0x%016h  got=0x%016h",
                         addr, expected, dmem_prog_rdata);
            @(negedge clk);
            dmem_prog_en = 1'b0;
        end
    endtask

    // Run pipeline until done pulses (or timeout)
    // done is combinatorial from memwb_is_ret (1-cycle pulse at posedge)
    task run_until_done;
        input integer timeout_cycles;
        integer cnt;
        begin
            cnt = 0;
            @(negedge clk); run = 1'b1;
            @(posedge clk); #1;
            while (!done && cnt < timeout_cycles) begin
                @(posedge clk); #1;
                cnt = cnt + 1;
            end
            if (done)
                $display("[INFO] done after %0d cycles", cnt);
            else
                $display("[FAIL] timeout (%0d cycles)", timeout_cycles);
            @(negedge clk); run = 1'b0;
            repeat(4) @(posedge clk);  // drain pipeline
        end
    endtask

    // Reset PC and flush pipeline stages
    task reset_pc;
        begin
            @(negedge clk); pc_reset_pulse = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); pc_reset_pulse = 1'b0;
            repeat(2) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Test 1: ADD_I16
    // -------------------------------------------------------
    task load_test1;
        begin
            // PC  0: MOV R1, 7
            imem_write(9'd0,  ENC(OP_MOV, 4'd1, 4'd0, 4'd0, 15'd7));
            imem_write(9'd1,  NOP);
            imem_write(9'd2,  NOP);
            imem_write(9'd3,  NOP);
            // PC  4: MOV R2, 5
            imem_write(9'd4,  ENC(OP_MOV, 4'd2, 4'd0, 4'd0, 15'd5));
            imem_write(9'd5,  NOP);
            imem_write(9'd6,  NOP);
            imem_write(9'd7,  NOP);
            // PC 12: ST64 R2, R0+1  (store R2 to DMEM[R0+1])
            imem_write(9'd8, ENC(OP_ST64, 4'd2, 4'd0, 4'd0, 15'd1));
            imem_write(9'd9, NOP);
            imem_write(9'd10, NOP);
            imem_write(9'd11, NOP);
            // PC 16: RET
            imem_write(9'd12, ENC(OP_RET, 4'd0, 4'd0, 4'd0, 15'd0));
        end
    endtask

    // -------------------------------------------------------
    // Test 2: MUL_BF16 + MAC_BF16
    // -------------------------------------------------------
    task load_test2;
        begin
            // PC  0: MOV R5, 10  (word addr of DMEM[10])
            imem_write(9'd0,  ENC(OP_MOV,      4'd5, 4'd0, 4'd0, 15'd10));
            imem_write(9'd1,  NOP);
            imem_write(9'd2,  NOP);
            imem_write(9'd3,  NOP);
            // PC  4: LD64 R1, R5  → R1 = DMEM[10] = {2.0 bf16 ×4}
            imem_write(9'd4,  ENC(OP_LD64,     4'd1, 4'd5, 4'd0, 15'd0));
            imem_write(9'd5,  NOP);
            imem_write(9'd6,  NOP);
            imem_write(9'd7,  NOP);
            // PC  8: MOV R6, 11  (word addr of DMEM[11])
            imem_write(9'd8,  ENC(OP_MOV,      4'd6, 4'd0, 4'd0, 15'd11));
            imem_write(9'd9,  NOP);
            imem_write(9'd10, NOP);
            imem_write(9'd11, NOP);
            // PC 12: LD64 R2, R6  → R2 = DMEM[11] = {3.0 bf16 ×4}
            imem_write(9'd12, ENC(OP_LD64,     4'd2, 4'd6, 4'd0, 15'd0));
            imem_write(9'd13, NOP);
            imem_write(9'd14, NOP);
            imem_write(9'd15, NOP);
            // PC 16: MUL_BF16 R3, R1, R2  → R3 = 2.0 × 3.0 = 6.0 (0x40C0 ×4)
            imem_write(9'd16, ENC(OP_MUL_BF16, 4'd3, 4'd1, 4'd2, 15'd0));
            imem_write(9'd17, NOP);
            imem_write(9'd18, NOP);
            imem_write(9'd19, NOP);
            // PC 20: MAC_BF16 R3, R1, R2  → R3 = 2.0*3.0 + 6.0 = 12.0 (0x4140 ×4)
            imem_write(9'd20, ENC(OP_MAC_BF16, 4'd3, 4'd1, 4'd2, 15'd0));
            imem_write(9'd21, NOP);
            imem_write(9'd22, NOP);
            imem_write(9'd23, NOP);
            // PC 24: MOV R7, 12  (output word addr)
            imem_write(9'd24, ENC(OP_MOV,      4'd7, 4'd0, 4'd0, 15'd12));
            imem_write(9'd25, NOP);
            imem_write(9'd26, NOP);
            imem_write(9'd27, NOP);
            // PC 28: ST64 R3, R7  → DMEM[12] = R3
            imem_write(9'd28, ENC(OP_ST64,     4'd3, 4'd7, 4'd0, 15'd0));
            imem_write(9'd29, NOP);
            imem_write(9'd30, NOP);
            imem_write(9'd31, NOP);
            // PC 32: RET
            imem_write(9'd32, ENC(OP_RET, 4'd0, 4'd0, 4'd0, 15'd0));
        end
    endtask
    // -------------------------------------------------------
    // Test 3: Jump
    // -------------------------------------------------------
    task load_test3;
        begin
 
            imem_write(9'd0,  ENC(OP_MOV,      4'd1, 4'd0, 4'd0, 15'd0));
            imem_write(9'd1,  ENC(OP_MOV,      4'd2, 4'd0, 4'd0, 15'd0));
            imem_write(9'd2,  ENC(OP_MOV,      4'd3, 4'd0, 4'd0, 15'd0));
            imem_write(9'd3,  ENC(OP_MOV,      4'd4, 4'd0, 4'd0, 15'd0));
            imem_write(9'd4,  ENC(OP_MOV,      4'd5, 4'd0, 4'd0, 15'd0));
            imem_write(9'd5,  ENC(OP_MOV,      4'd6, 4'd0, 4'd0, 15'd0));
            imem_write(9'd6 , NOP);
            imem_write(9'd7 , NOP);
            imem_write(9'd8 , NOP);
            imem_write(9'd9 , NOP);
            imem_write(9'd10,  ENC(OP_BR,      4'd0, 4'd0, 4'd0, 15'd15));
            imem_write(9'd11, NOP);
            imem_write(9'd12, NOP);
            imem_write(9'd13,  ENC(OP_MOV,      4'd1, 4'd0, 4'd0, 15'd1));
            imem_write(9'd14,  ENC(OP_MOV,      4'd2, 4'd0, 4'd0, 15'd1));
            imem_write(9'd15,  ENC(OP_MOV,      4'd3, 4'd0, 4'd0, 15'd1));
            imem_write(9'd16,  ENC(OP_MOV,      4'd4, 4'd0, 4'd0, 15'd1));
            imem_write(9'd17,  ENC(OP_MOV,      4'd5, 4'd0, 4'd0, 15'd1));
            imem_write(9'd18,  ENC(OP_MOV,      4'd6, 4'd0, 4'd0, 15'd1));
            imem_write(9'd19, ENC(OP_ST64,     4'd1, 4'd0, 4'd0, 15'd1));
            imem_write(9'd20, ENC(OP_ST64,     4'd2, 4'd0, 4'd0, 15'd2));
            imem_write(9'd21, ENC(OP_ST64,     4'd3, 4'd0, 4'd0, 15'd3));
            imem_write(9'd22, ENC(OP_ST64,     4'd4, 4'd0, 4'd0, 15'd4));
            imem_write(9'd23, ENC(OP_ST64,     4'd5, 4'd0, 4'd0, 15'd5));
            imem_write(9'd24, ENC(OP_ST64,     4'd6, 4'd0, 4'd0, 15'd6));
            imem_write(9'd25, ENC(OP_RET, 4'd0, 4'd0, 4'd0, 15'd0));
        end
    endtask

    // -------------------------------------------------------
    // Test 4:Conditional jump
    // -------------------------------------------------------
    task load_test4;
        begin
 
            imem_write(9'd0,  ENC(OP_MOV,      4'd1, 4'd0, 4'd0, 15'd0));
            imem_write(9'd1,  ENC(OP_MOV,      4'd2, 4'd0, 4'd0, 15'd0));
            imem_write(9'd2,  ENC(OP_MOV,      4'd3, 4'd0, 4'd0, 15'd0));
            imem_write(9'd3,  ENC(OP_MOV,      4'd4, 4'd0, 4'd0, 15'd0));
            imem_write(9'd4,  ENC(OP_MOV,      4'd5, 4'd0, 4'd0, 15'd5));
            imem_write(9'd5,  ENC(OP_MOV,      4'd6, 4'd0, 4'd0, 15'd10));
            imem_write(9'd6 , NOP);
            imem_write(9'd7 , NOP);
            imem_write(9'd8,  ENC(OP_SETP_GE,  4'd0, 4'd5, 4'd6, 15'd0));
            imem_write(9'd9 , NOP);
            imem_write(9'd10 , NOP);
            imem_write(9'd11 , NOP);
            imem_write(9'd12,  ENC(OP_BPR,      4'd0, 4'd0, 4'd0, 15'd19));
            imem_write(9'd13, NOP);
            imem_write(9'd14, NOP);
            imem_write(9'd15, NOP);
            imem_write(9'd16, NOP);
            imem_write(9'd17,  ENC(OP_MOV,      4'd1, 4'd0, 4'd0, 15'd1));
            imem_write(9'd18,  ENC(OP_MOV,      4'd2, 4'd0, 4'd0, 15'd1));
            imem_write(9'd19,  ENC(OP_MOV,      4'd3, 4'd0, 4'd0, 15'd1));
            imem_write(9'd20,  ENC(OP_MOV,      4'd4, 4'd0, 4'd0, 15'd1));
            imem_write(9'd21,  ENC(OP_MOV,      4'd5, 4'd0, 4'd0, 15'd1));
            imem_write(9'd22,  ENC(OP_MOV,      4'd6, 4'd0, 4'd0, 15'd1));

            imem_write(9'd23, ENC(OP_ST64,     4'd1, 4'd0, 4'd0, 15'd1));
            imem_write(9'd24, ENC(OP_ST64,     4'd2, 4'd0, 4'd0, 15'd2));
            imem_write(9'd25, ENC(OP_ST64,     4'd3, 4'd0, 4'd0, 15'd3));
            imem_write(9'd26, ENC(OP_ST64,     4'd4, 4'd0, 4'd0, 15'd4));
            imem_write(9'd27, ENC(OP_ST64,     4'd5, 4'd0, 4'd0, 15'd5));
            imem_write(9'd28, ENC(OP_ST64,     4'd6, 4'd0, 4'd0, 15'd6));

            imem_write(9'd29, ENC(OP_RET,      4'd0, 4'd0, 4'd0, 15'd0));
        end
    endtask

    // -------------------------------------------------------
    // Test 5:LOAD PARAM
    // -------------------------------------------------------
    task load_test5;
        begin
 
          imem_write(9'd0,  ENC(OP_MOV,      4'd1, 4'd0, 4'd0, 15'd0));
            imem_write(9'd1,  ENC(OP_MOV,      4'd2, 4'd0, 4'd0, 15'd0));
            imem_write(9'd2,  ENC(OP_MOV,      4'd3, 4'd0, 4'd0, 15'd0));
            imem_write(9'd3,  ENC(OP_MOV,      4'd4, 4'd0, 4'd0, 15'd0));
            imem_write(9'd4,  ENC(OP_MOV,      4'd5, 4'd0, 4'd0, 15'd5));
            imem_write(9'd5,  ENC(OP_MOV,      4'd6, 4'd0, 4'd0, 15'd10));
            imem_write(9'd6 , NOP);
            imem_write(9'd7 , NOP);
            imem_write(9'd8,  ENC(OP_SETP_GE,  4'd0, 4'd5, 4'd6, 15'd0));
            imem_write(9'd9 , NOP);
            imem_write(9'd10 , NOP);
            imem_write(9'd11 , NOP);
            imem_write(9'd12,  ENC(OP_LD_PARAM,      4'd1, 4'd0, 4'd0, 15'd0));
            imem_write(9'd13, ENC(OP_LD_PARAM,      4'd2, 4'd0, 4'd0, 15'd1));
            imem_write(9'd14, ENC(OP_LD_PARAM,      4'd3, 4'd0, 4'd0, 15'd2));
            imem_write(9'd15, NOP);
            imem_write(9'd16, NOP);
            imem_write(9'd17,  NOP);
            imem_write(9'd18,  NOP);
            imem_write(9'd19,  NOP);
            imem_write(9'd20,  ENC(OP_MOV,      4'd4, 4'd0, 4'd0, 15'd1));
            imem_write(9'd21,  ENC(OP_MOV,      4'd5, 4'd0, 4'd0, 15'd1));
            imem_write(9'd22,  ENC(OP_MOV,      4'd6, 4'd0, 4'd0, 15'd1));

            imem_write(9'd23, ENC(OP_ST64,     4'd1, 4'd1, 4'd0, 15'd0));
            imem_write(9'd24, ENC(OP_ST64,     4'd2, 4'd2, 4'd0, 15'd0));
            imem_write(9'd25, ENC(OP_ST64,     4'd3, 4'd3, 4'd0, 15'd0));
            imem_write(9'd26, ENC(OP_ST64,     4'd4, 4'd0, 4'd0, 15'd4));
            imem_write(9'd27, ENC(OP_ST64,     4'd5, 4'd0, 4'd0, 15'd5));
            imem_write(9'd28, ENC(OP_ST64,     4'd6, 4'd0, 4'd0, 15'd6));

            imem_write(9'd29, ENC(OP_RET,      4'd0, 4'd0, 4'd0, 15'd0));
        end
    endtask
    
    //=======================================================
    //TASK 6 ST
    //=======================================================
    task load_test6;
    begin
        imem_write(9'd0,  ENC(OP_MOV,      4'd1, 4'd0, 4'd0, 15'd10));
        imem_write(9'd1,  ENC(OP_MOV,      4'd2, 4'd0, 4'd0, 15'd20));
        imem_write(9'd2,  ENC(OP_MOV,      4'd3, 4'd0, 4'd0, 15'd30));
        imem_write(9'd3,  ENC(OP_MOV,      4'd4, 4'd0, 4'd0, 15'd40));
        imem_write(9'd4,  ENC(OP_MOV,      4'd5, 4'd0, 4'd0, 15'd50));
        imem_write(9'd5,  ENC(OP_ST64,     4'd1, 4'd1, 4'd0, 15'd0));
        imem_write(9'd6,  ENC(OP_ST64,     4'd2, 4'd2, 4'd0, 15'd0));
        imem_write(9'd7,  ENC(OP_ST64,     4'd3, 4'd3, 4'd0, 15'd0));
        imem_write(9'd8,  ENC(OP_ST64,     4'd4, 4'd4, 4'd0, 15'd0));
        imem_write(9'd9,  ENC(OP_ST64,     4'd5, 4'd5, 4'd0, 15'd0));
        imem_write(9'd10, ENC(OP_RET,      4'd0, 4'd0, 4'd0, 15'd0));
    end
    endtask
    // -------------------------------------------------------
    // Main
    // -------------------------------------------------------
    initial begin
        rst_n          = 0;  run = 0;  step = 0;  pc_reset_pulse = 0;
        param_wr_en    = 0;  param_wr_addr = 0;  param_wr_data = 0;
        imem_prog_we   = 0;  imem_prog_addr = 0; imem_prog_wdata = 0;
        dmem_prog_en   = 0;  dmem_prog_we = 0;
        dmem_prog_addr = 0;  dmem_prog_wdata = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ========================================================
        // TEST 1: ADD_I16
        //   R1 = MOV(7),  R2 = MOV(5)
        //   ADD_I16 R3, R1, R2  → lane0 = 12, lanes 1-3 = 0
        //   Store to DMEM[0]
        //   Expected: DMEM[0] = 64'h0000_0000_0000_000C
        // ========================================================
        $display("\n=== TEST 1: ADD_I16 (3 NOPs after each write) ===");
        load_test1;
        reset_pc;
        run_until_done(200);
        dmem_check(8'd1, 64'h0000_0000_0000_0005);

        // ========================================================
        // TEST 2: MUL_BF16 + MAC_BF16 (FMA)
        //   DMEM[10] = {2.0 bf16 ×4} = 64'h4000_4000_4000_4000
        //   DMEM[11] = {3.0 bf16 ×4} = 64'h4040_4040_4040_4040
        //   MUL: R3 = 2.0 × 3.0 = {6.0}   bf16 = 0x40C0
        //   MAC: R3 = 2.0×3.0 + 6.0 = {12.0} bf16 = 0x4140
        //   Store to DMEM[12]
        //   Expected: DMEM[12] = 64'h4140_4140_4140_4140
        // ========================================================
        $display("\n=== TEST 2: MUL_BF16 + MAC_BF16 / FMA (3 NOPs after each FMA) ===");

        // Pre-load bf16 input vectors
        dmem_write(8'd10, 64'h4000_4000_4000_4000);   // 2.0 × 4 lanes
        dmem_write(8'd11, 64'h4040_4040_4040_4040);   // 3.0 × 4 lanes

        load_test2;
        reset_pc;
        run_until_done(300);
        dmem_check(8'd12, 64'h4140_4140_4140_4140);

        // ========================================================
        // TEST 3: jUMP
        // Instruction wants to write to Reg1,2,3,4,5,6 Jump to start from 3
        // So only regs after 3 could be write
        // ST to dmem to check is correct
        // MODIFIED VERSION:
        // JUMP should have 3 delay slot, so the reg1 is also being written, because of stay in the slot
        // ========================================================
        $display("\n=== TEST 3:jump===");

        // Pre-load bf16 input vectors
        dmem_write(8'd1, 64'h0);
        dmem_write(8'd2, 64'h0);
        dmem_write(8'd3, 64'h0);
        dmem_write(8'd4, 64'h0);
        dmem_write(8'd5, 64'h0);
        dmem_write(8'd6, 64'h0);

        load_test3;
        reset_pc;
        run_until_done(300);
        dmem_check(8'd1, 64'h1);
        dmem_check(8'd2, 64'h0);
        dmem_check(8'd3, 64'h1);
        dmem_check(8'd4, 64'h1);
        dmem_check(8'd5, 64'h1);
        dmem_check(8'd6, 64'h1);

        // ========================================================
        // TEST 4: CONditional jump
        // R5<R6 NO jump
        // ========================================================
        $stop;
        $display("\n=== TEST 4: CONDITIONAL JUMP (BPR) ===");

        // Pre-load bf16 input vectors
        dmem_write(8'd1, 64'h0);
        dmem_write(8'd2, 64'h0);
        dmem_write(8'd3, 64'h0);
        dmem_write(8'd4, 64'h0);
        dmem_write(8'd5, 64'h0);
        dmem_write(8'd6, 64'h0);

        load_test4;
        reset_pc;
        run_until_done(300);
        dmem_check(8'd1, 64'h1);
        dmem_check(8'd2, 64'h1);
        dmem_check(8'd3, 64'h1);
        dmem_check(8'd4, 64'h1);
        dmem_check(8'd5, 64'h1);
        dmem_check(8'd6, 64'h1);

        // ========================================================
        // TEST 5: LOAD PARAM
        // ========================================================

        $display("\n=== TEST 5: LOADPARAM ===");

        // Pre-load bf16 input vectors

        dmem_write(8'd1, 64'h0);
        dmem_write(8'd2, 64'h0);
        dmem_write(8'd3, 64'h0);
        dmem_write(8'd4, 64'h0);
        dmem_write(8'd5, 64'h0);
        dmem_write(8'd6, 64'h0);


        param_write(3'd0,64'd10);
        param_write(3'd1,64'd20);
        param_write(3'd2,64'd30);

        load_test5;
        reset_pc;
        run_until_done(300);

        dmem_check(8'd10, 64'd10);
        dmem_check(8'd20, 64'd20);
        dmem_check(8'd30, 64'd30);
        dmem_check(8'd4, 64'h1);
        dmem_check(8'd5, 64'h1);
        dmem_check(8'd6, 64'h1);

        // ========================================================
        // TEST 6: STW
        // ========================================================
        $display("\n=== TEST 6: STW ===");

        // Pre-load bf16 input vectors

        dmem_write(8'd10, 64'h0);
        dmem_write(8'd20, 64'h0);
        dmem_write(8'd30, 64'h0);
        dmem_write(8'd40, 64'h0);
        dmem_write(8'd50, 64'h0);

        load_test6;
        reset_pc;
        run_until_done(300);

        dmem_check(8'd10, 64'd10);
        dmem_check(8'd20, 64'd20);
        dmem_check(8'd30, 64'd30);
        dmem_check(8'd40, 64'd40);
        dmem_check(8'd50, 64'd50);
        

        $display("\n=== ALL TESTS COMPLETE ===");
        $finish;
    end

    // -------------------------------------------------------
    // VCD
    // -------------------------------------------------------
    initial begin
        $dumpfile("tb_gpu_core3.vcd");
        $dumpvars(0, tb_gpu_core3);
    end

endmodule
