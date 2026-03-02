// tb_gpu_core3_FMA_sample.v
// Testbench for gpu_core3 (no-flush, no-forwarding pipeline)
// NOP policy: 3 NOPs after every write instruction
//
// ISA:  {op[4:0], rd[3:0], rs1[3:0], rs2[3:0], imm15[14:0]}
//       [31:27]=OP  [26:23]=RD  [22:19]=RS1  [18:15]=RS2  [14:0]=IMM15
//
`timescale 1ns/1ps

module tb_gpu_core3;

    // -------------------------------------------------------
    // Signals
    // -------------------------------------------------------
    reg        clk, rst_n;
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
        .rst_n           (rst_n),
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
            @(negedge clk); pc_reset = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); pc_reset = 1'b0;
            repeat(2) @(posedge clk);
        end
    endtask


    // -------------------------------------------------------
    // Test : ADD
    // -------------------------------------------------------
    task load_test_add;
        begin
            imem_write(9'd0 ,   ENC(OP_LD_PARAM , 4'd1, 4'd0, 4'd0, 15'd1));
            imem_write(9'd1 ,   ENC(OP_LD_PARAM , 4'd2, 4'd0, 4'd0, 15'd2));
            imem_write(9'd2 ,   ENC(OP_LD_PARAM , 4'd3, 4'd0, 4'd0, 15'd3));
            imem_write(9'd3 ,   ENC(OP_LD_PARAM , 4'd4, 4'd0, 4'd0, 15'd4));
            imem_write(9'd4 ,   ENC(OP_MOV      , 4'd5, 4'd0, 4'd0, 15'd0));
            imem_write(9'd5 ,   NOP);
            imem_write(9'd6 ,   NOP);
            imem_write(9'd7 ,   ENC(OP_SETP_GE  , 4'd0, 4'd5, 4'd4, 15'd0));
            imem_write(9'd8 ,   ENC(OP_BPR      , 4'd0, 4'd0, 4'd0, 15'd19));
            imem_write(9'd9 ,   ENC(OP_LD64     , 4'd10, 4'd1, 4'd0, 15'd0));
            imem_write(9'd10,   ENC(OP_LD64     , 4'd11, 4'd2, 4'd0, 15'd0));
            imem_write(9'd11,   ENC(OP_LD64     , 4'd12, 4'd3, 4'd0, 15'd0));
            imem_write(9'd12,   ENC(OP_ADDI64   , 4'd1, 4'd1, 4'd0, 15'd1));
            imem_write(9'd13,   ENC(OP_ADDI64   , 4'd2, 4'd2, 4'd0, 15'd1));
            imem_write(9'd14,   ENC(OP_MAC_BF16  , 4'd12, 4'd10, 4'd11, 15'd0));
            imem_write(9'd15,   ENC(OP_BR       , 4'd0, 4'd0, 4'd0, 15'd7));
            imem_write(9'd16,   ENC(OP_ADDI64   , 4'd5, 4'd5, 4'd0, 15'd4));
            imem_write(9'd17,   ENC(OP_ST64     , 4'd12, 4'd3, 4'd0, 15'd0));
            imem_write(9'd18,   ENC(OP_ADDI64   , 4'd3, 4'd3, 4'd0, 15'd1));

            imem_write(9'd19,   ENC(OP_RET      , 4'd0, 4'd0, 4'd0, 15'd0));
        end
    endtask


    // -------------------------------------------------------
    // Main
    // -------------------------------------------------------
    initial begin
        rst_n          = 0;  run = 0;  step = 0;  pc_reset = 0;
        param_wr_en    = 0;  param_wr_addr = 0;  param_wr_data = 0;
        imem_prog_we   = 0;  imem_prog_addr = 0; imem_prog_wdata = 0;
        dmem_prog_en   = 0;  dmem_prog_we = 0;
        dmem_prog_addr = 0;  dmem_prog_wdata = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ========================================================
        // TEST : FMA
        // ========================================================
        $display("\n=== TEST : ADD  ===");

        // Pre-load bf16 input vectors
        dmem_write(8'd0, 64'h4040_4000_3F80_0000);//3  2  1  0
        dmem_write(8'd1, 64'h40E0_40C0_40A0_4080);//7  6  5  3
        dmem_write(8'd2, 64'h4130_4120_4110_4100);//11 10 9  8

        dmem_write(8'd10, 64'h4040_4000_3F80_0000);
        dmem_write(8'd11, 64'h40E0_40C0_40A0_4080);
        dmem_write(8'd12, 64'h4130_4120_4110_4100);

        dmem_write(8'd20, 64'h3F80_3F80_3F80_3F80);
        dmem_write(8'd21, 64'h3F80_3F80_3F80_3F80);
        dmem_write(8'd22, 64'h3F80_3F80_3F80_3F80);

        param_write(3'd1, 64'd0);
        param_write(3'd2, 64'd10);
        param_write(3'd3, 64'd20);
        param_write(3'd4, 64'd11);

        load_test_add;
        reset_pc;
        run_until_done(300);
        dmem_check(8'd20, 64'h4120_40A0_4000_3F80);//10 5  2   1
        dmem_check(8'd21, 64'h4248_4214_41D0_4188);//50 37 26 17
        dmem_check(8'd22, 64'h42F4_42CA_42A4_4282);//122 101 82 65
        dmem_check(8'd23, 64'h0000_0000_0000_0000);
        dmem_check(8'd24, 64'h0000_0000_0000_0000);
        dmem_check(8'd25, 64'h0000_0000_0000_0000);


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
