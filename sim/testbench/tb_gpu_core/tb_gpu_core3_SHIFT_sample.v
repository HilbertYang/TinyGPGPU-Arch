// tb_gpu_core3_SHIFT_sample.v
// Testbench for SHIFTL16 (5'h07) and SHIFTR16 (5'h08)
// NOP policy: 3 NOPs after every write instruction (no forwarding network)
//
// ISA:  {op[4:0], rd[3:0], rs1[3:0], rs2[3:0], imm15[14:0]}
//       [31:27]=OP  [26:23]=RD  [22:19]=RS1  [18:15]=RS2  [14:0]=IMM15
//
// SHIFTL16: RD = RS1 << 16  (64-bit shift; lane 0 zeroed, lanes 1-3 shift up)
// SHIFTR16: RD = RS1 >> 16  (64-bit logical shift; lane 3 zeroed, lanes 0-2 shift down)
//

`timescale 1ns/1ps

module tb_gpu_core3_SHIFT;

    // -------------------------------------------------------
    // Signals
    // -------------------------------------------------------
    reg        clk, reset;
    reg        run, step, pc_reset;
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
        .reset           (reset),
        .run             (run),
        .step            (step),
        .pc_reset        (pc_reset),
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
    // Instruction encoder
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
        OP_SHIFTL16 = 5'h07,
        OP_SHIFTR16 = 5'h08,
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
    task imem_write;
        input [8:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            imem_prog_we    = 1'b1;
            imem_prog_addr  = addr;
            imem_prog_wdata = data;
            @(posedge clk); #1;
            imem_prog_we = 1'b0;
        end
    endtask

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

    task dmem_check;
        input [7:0]  addr;
        input [63:0] expected;
        begin
            @(negedge clk);
            dmem_prog_en   = 1'b1;
            dmem_prog_we   = 1'b0;
            dmem_prog_addr = addr;
            @(posedge clk); #1;
            @(posedge clk); #1;
            if (dmem_prog_rdata === expected)
                $display("[PASS] DMEM[%0d] = 0x%016h", addr, dmem_prog_rdata);
            else
                $display("[FAIL] DMEM[%0d]  expected=0x%016h  got=0x%016h",
                         addr, expected, dmem_prog_rdata);
            @(negedge clk);
            dmem_prog_en = 1'b0;
        end
    endtask

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
            repeat(4) @(posedge clk);
        end
    endtask

    task reset_pc;
        begin
            @(negedge clk); pc_reset = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); pc_reset = 1'b0;
            repeat(2) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Test kernel:
    //
    //   R0  = 0 (hardwired zero, used as base address)
    //   R1  = scratch load register
    //   R2  = SHIFTL16 result
    //   R3  = SHIFTR16 result
    //
    //   DMEM[0] = input_A  (for SHIFTL16 cases)
    //   DMEM[1] = input_B  (for SHIFTR16 cases)
    //   DMEM[2] = input_C  (edge: all-zero)
    //   DMEM[3] = input_D  (edge: all-ones / 0xFFFF per lane)
    //
    //   Results stored at DMEM[8..15]:
    //     DMEM[8]  = SHIFTL16(input_A)
    //     DMEM[9]  = SHIFTR16(input_B)
    //     DMEM[10] = SHIFTL16(input_C)  -- expect all zeros
    //     DMEM[11] = SHIFTR16(input_D)  -- expect 0x0000_FFFF_FFFF_FFFF
    //
    // NOP schedule: 3 NOPs after every LD64/SHIFTL16/SHIFTR16 before
    //               the next instruction that reads the written register.
    // -------------------------------------------------------
    task load_test_shift;
        begin
            // --- SHIFTL16(input_A) → DMEM[8] ---
            // PC 0
            imem_write(9'd0,  ENC(OP_LD64,    4'd1, 4'd0, 4'd0, 15'd0));  // R1 = DMEM[R0+0] = input_A
            imem_write(9'd1,  NOP);
            imem_write(9'd2,  NOP);
            imem_write(9'd3,  NOP);
            // PC 4: R1 available
            imem_write(9'd4,  ENC(OP_SHIFTL16, 4'd2, 4'd1, 4'd0, 15'd0)); // R2 = R1 << 16
            imem_write(9'd5,  NOP);
            imem_write(9'd6,  NOP);
            imem_write(9'd7,  NOP);
            // PC 8: R2 available
            imem_write(9'd8,  ENC(OP_ST64,    4'd2, 4'd0, 4'd0, 15'd8));  // DMEM[R0+8] = R2
            imem_write(9'd9,  NOP);
            imem_write(9'd10, NOP);
            imem_write(9'd11, NOP);

            // --- SHIFTR16(input_B) → DMEM[9] ---
            // PC 12
            imem_write(9'd12, ENC(OP_LD64,    4'd1, 4'd0, 4'd0, 15'd1));  // R1 = DMEM[R0+1] = input_B
            imem_write(9'd13, NOP);
            imem_write(9'd14, NOP);
            imem_write(9'd15, NOP);
            // PC 16: R1 available
            imem_write(9'd16, ENC(OP_SHIFTR16, 4'd3, 4'd1, 4'd0, 15'd0)); // R3 = R1 >> 16
            imem_write(9'd17, NOP);
            imem_write(9'd18, NOP);
            imem_write(9'd19, NOP);
            // PC 20: R3 available
            imem_write(9'd20, ENC(OP_ST64,    4'd3, 4'd0, 4'd0, 15'd9));  // DMEM[R0+9] = R3
            imem_write(9'd21, NOP);
            imem_write(9'd22, NOP);
            imem_write(9'd23, NOP);

            // --- SHIFTL16(input_C = 0) → DMEM[10], expect all-zero ---
            // PC 24
            imem_write(9'd24, ENC(OP_LD64,    4'd1, 4'd0, 4'd0, 15'd2));  // R1 = DMEM[R0+2] = 0
            imem_write(9'd25, NOP);
            imem_write(9'd26, NOP);
            imem_write(9'd27, NOP);
            imem_write(9'd28, ENC(OP_SHIFTL16, 4'd2, 4'd1, 4'd0, 15'd0)); // R2 = 0 << 16 = 0
            imem_write(9'd29, NOP);
            imem_write(9'd30, NOP);
            imem_write(9'd31, NOP);
            imem_write(9'd32, ENC(OP_ST64,    4'd2, 4'd0, 4'd0, 15'd10)); // DMEM[10] = R2
            imem_write(9'd33, NOP);
            imem_write(9'd34, NOP);
            imem_write(9'd35, NOP);

            // --- SHIFTR16(input_D = 0xFFFF_FFFF_FFFF_FFFF) → DMEM[11] ---
            // expected: 0x0000_FFFF_FFFF_FFFF
            // PC 36
            imem_write(9'd36, ENC(OP_LD64,    4'd1, 4'd0, 4'd0, 15'd3));  // R1 = DMEM[R0+3] = all-ones
            imem_write(9'd37, NOP);
            imem_write(9'd38, NOP);
            imem_write(9'd39, NOP);
            imem_write(9'd40, ENC(OP_SHIFTR16, 4'd3, 4'd1, 4'd0, 15'd0)); // R3 = all-ones >> 16
            imem_write(9'd41, NOP);
            imem_write(9'd42, NOP);
            imem_write(9'd43, NOP);
            imem_write(9'd44, ENC(OP_ST64,    4'd3, 4'd0, 4'd0, 15'd11)); // DMEM[11] = R3
            imem_write(9'd45, NOP);
            imem_write(9'd46, NOP);
            imem_write(9'd47, NOP);

            // PC 48: RET
            imem_write(9'd48, ENC(OP_RET,     4'd0, 4'd0, 4'd0, 15'd0));
            imem_write(9'd49, NOP);
        end
    endtask

    // -------------------------------------------------------
    // Main
    // -------------------------------------------------------
    initial begin
        reset          = 1;  run = 0;  step = 0;  pc_reset = 0;
        param_wr_en    = 0;  param_wr_addr = 0;  param_wr_data = 0;
        imem_prog_we   = 0;  imem_prog_addr = 0; imem_prog_wdata = 0;
        dmem_prog_en   = 0;  dmem_prog_we = 0;
        dmem_prog_addr = 0;  dmem_prog_wdata = 0;

        repeat(5) @(posedge clk);
        reset = 0;
        repeat(2) @(posedge clk);

        // ========================================================
        // TEST : SHIFTL16 / SHIFTR16
        // ========================================================
        $display("\n=== TEST : SHIFTL16 / SHIFTR16 ===");

        // Input vectors (4 x i16 packed in 64 bits)
        //   input_A: lanes = {4, 3, 2, 1}  → 0x0004_0003_0002_0001
        //   input_B: lanes = {4, 3, 2, 1}  → 0x0004_0003_0002_0001  (same, symmetric check)
        //   input_C: all zeros
        //   input_D: all-ones (0xFFFF per lane)
        dmem_write(8'd0,  64'h0004_0003_0002_0001); // input_A
        dmem_write(8'd1,  64'h0004_0003_0002_0001); // input_B
        dmem_write(8'd2,  64'h0000_0000_0000_0000); // input_C
        dmem_write(8'd3,  64'hFFFF_FFFF_FFFF_FFFF); // input_D

        // Clear result area
        dmem_write(8'd8,  64'hDEAD_DEAD_DEAD_DEAD);
        dmem_write(8'd9,  64'hDEAD_DEAD_DEAD_DEAD);
        dmem_write(8'd10, 64'hDEAD_DEAD_DEAD_DEAD);
        dmem_write(8'd11, 64'hDEAD_DEAD_DEAD_DEAD);

        load_test_shift;
        reset_pc;
        run_until_done(300);

        $display("\n--- SHIFTL16 checks ---");
        // input_A << 16: lane 0 becomes 0, lane 1 gets old lane 0, ..., lane 3 gets old lane 2
        //   {0004,0003,0002,0001} << 16 = {0003,0002,0001,0000}
        dmem_check(8'd8,  64'h0003_0002_0001_0000);

        $display("\n--- SHIFTR16 checks ---");
        // input_B >> 16: lane 3 becomes 0, lane 2 gets old lane 3, ..., lane 0 gets old lane 1
        //   {0004,0003,0002,0001} >> 16 = {0000,0004,0003,0002}
        dmem_check(8'd9,  64'h0000_0004_0003_0002);

        $display("\n--- Edge: SHIFTL16(0) ---");
        dmem_check(8'd10, 64'h0000_0000_0000_0000);

        $display("\n--- Edge: SHIFTR16(all-ones) ---");
        // 0xFFFF_FFFF_FFFF_FFFF >> 16 = 0x0000_FFFF_FFFF_FFFF
        dmem_check(8'd11, 64'h0000_FFFF_FFFF_FFFF);

        $display("\n=== ALL TESTS COMPLETE ===");
        $finish;
    end

    // -------------------------------------------------------
    // VCD
    // -------------------------------------------------------
    initial begin
        $dumpfile("tb_gpu_core3_SHIFT.vcd");
        $dumpvars(0, tb_gpu_core3_SHIFT);
    end

endmodule
