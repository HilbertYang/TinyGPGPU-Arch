// tb_gpu_top.v
// Testbench for gpu_top — Xilinx BLKMEM Write-First, pipe_stages=0
// 时序规律：
//   写：negedge 设信号 → posedge 锁入 → 完成
//   读：negedge 设addr/en=1 → posedge 锁入地址 → 下一个posedge后 dout 有效
//   关键：imem_prog_dout = imem_prog_en_d ? imem_dout : 0
//         imem_prog_en_d 是 imem_prog_en & en_mux 延迟一拍
//         所以采样时 imem_prog_en 必须保持为 1

`timescale 1ns/1ps

module tb_gpu_top;

    reg         clk, reset, start;
    wire        done;

    reg         param_wr_en;
    reg  [2:0]  param_wr_addr;
    reg  [63:0] param_wr_data;

    reg         imem_prog_en;
    reg  [8:0]  imem_prog_addr;
    reg  [31:0] imem_prog_din;
    wire [31:0] imem_prog_dout;

    reg         dmem_host_en, dmem_host_we;
    reg  [7:0]  dmem_host_addr;
    reg  [63:0] dmem_host_din;
    wire [63:0] dmem_host_dout;

    reg         dmem_prog_en, dmem_prog_we;
    reg  [7:0]  dmem_prog_addr;
    reg  [63:0] dmem_prog_din;
    wire [63:0] dmem_prog_dout;

    gpu_top DUT (
        .clk(clk), .reset(reset), .start(start), .done(done),
        .param_wr_en(param_wr_en), .param_wr_addr(param_wr_addr), .param_wr_data(param_wr_data),
        .imem_prog_en(imem_prog_en), .imem_prog_addr(imem_prog_addr),
        .imem_prog_din(imem_prog_din), .imem_prog_dout(imem_prog_dout),
        .dmem_host_en(dmem_host_en), .dmem_host_we(dmem_host_we),
        .dmem_host_addr(dmem_host_addr), .dmem_host_din(dmem_host_din),
        .dmem_host_dout(dmem_host_dout),
        .dmem_prog_en(dmem_prog_en), .dmem_prog_we(dmem_prog_we),
        .dmem_prog_addr(dmem_prog_addr), .dmem_prog_din(dmem_prog_din),
        .dmem_prog_dout(dmem_prog_dout)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // IMEM 写：每次调用写一条，imem_prog_en 保持高
    // -------------------------------------------------------
    task imem_write;
        input [8:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            imem_prog_en   = 1'b1;
            imem_prog_addr = addr;
            imem_prog_din  = data;
            @(posedge clk); // BRAM 锁入写操作
        end
    endtask

    // -------------------------------------------------------
    // IMEM 读回：
    //   imem_prog_en 在整个过程保持 1
    //   注意 gpu_top 里 imem_we_mux = imem_prog_en ? 1'b1 : imem_we_gpu
    //   所以读时也会写入 imem_prog_din 的值
    //   → 为了不破坏数据，调用前先把 imem_prog_din 设成期望值（幂等写）
    // -------------------------------------------------------
    task imem_read_check;
        input [8:0]  addr;
        input [31:0] expected;
        begin
            @(negedge clk);
            imem_prog_en   = 1'b1;       // 保持高
            imem_prog_addr = addr;
            imem_prog_din  = expected;   // 幂等写，防止覆盖
            @(posedge clk); #1;          // T0: 地址+写 锁入BRAM
            @(posedge clk); #1;          // T1: dout 有效，且 imem_prog_en_d=1
            if (imem_prog_dout === expected)
                $display("[PASS] IMEM[%0d] = 0x%08h", addr, imem_prog_dout);
            else
                $display("[FAIL] IMEM[%0d]: expected 0x%08h, got 0x%08h",
                          addr, expected, imem_prog_dout);
        end
    endtask

    // -------------------------------------------------------
    // DMEM Port A 写
    // -------------------------------------------------------
    task dmem_host_write;
        input [7:0]  addr;
        input [63:0] data;
        begin
            @(negedge clk);
            dmem_host_en   = 1'b1;
            dmem_host_we   = 1'b1;
            dmem_host_addr = addr;
            dmem_host_din  = data;
            @(posedge clk); #1;
            dmem_host_en   = 1'b0;
            dmem_host_we   = 1'b0;
        end
    endtask

    // -------------------------------------------------------
    // DMEM Port A 读回
    //   dmem_host_dout = dmem_host_en_d ? douta : 0
    //   dmem_host_en_d = delay(dmem_host_en & en_a)
    //   采样时 dmem_host_en 必须还是 1
    // -------------------------------------------------------
    task dmem_host_read_check;
        input [7:0]  addr;
        input [63:0] expected;
        begin
            @(negedge clk);
            dmem_host_en   = 1'b1;   // 保持高直到采样完
            dmem_host_we   = 1'b0;
            dmem_host_addr = addr;
            dmem_host_din  = 64'd0;
            @(posedge clk); #1;      // T0: 地址锁入
            @(posedge clk); #1;      // T1: dout 有效，host_en_d=1
            if (dmem_host_dout === expected)
                $display("[PASS] DMEM_A[%0d] = 0x%016h", addr, dmem_host_dout);
            else
                $display("[FAIL] DMEM_A[%0d]: expected 0x%016h, got 0x%016h",
                          addr, expected, dmem_host_dout);
            @(negedge clk);
            dmem_host_en = 1'b0;
        end
    endtask

    // -------------------------------------------------------
    // DMEM Port B 写
    // -------------------------------------------------------
    task dmem_portB_write;
        input [7:0]  addr;
        input [63:0] data;
        begin
            @(negedge clk);
            dmem_prog_en   = 1'b1;
            dmem_prog_we   = 1'b1;
            dmem_prog_addr = addr;
            dmem_prog_din  = data;
            @(posedge clk); #1;
            dmem_prog_en   = 1'b0;
            dmem_prog_we   = 1'b0;
        end
    endtask

    // -------------------------------------------------------
    // DMEM Port B 读回（doutb 直接输出，无 mux 遮挡）
    // -------------------------------------------------------
    task dmem_portB_read_check;
        input [7:0]  addr;
        input [63:0] expected;
        begin
            @(negedge clk);
            dmem_prog_en   = 1'b1;
            dmem_prog_we   = 1'b0;
            dmem_prog_addr = addr;
            @(posedge clk); #1;   // 地址锁入
            @(posedge clk); #1;   // doutb 有效
            if (dmem_prog_dout === expected)
                $display("[PASS] DMEM_B[%0d] = 0x%016h", addr, dmem_prog_dout);
            else
                $display("[FAIL] DMEM_B[%0d]: expected 0x%016h, got 0x%016h",
                          addr, expected, dmem_prog_dout);
            @(negedge clk);
            dmem_prog_en = 1'b0;
        end
    endtask

    // -------------------------------------------------------
    // 写 kernel 参数
    // -------------------------------------------------------
    task param_write;
        input [2:0]  idx;
        input [63:0] data;
        begin
            @(negedge clk);
            param_wr_en   = 1'b1;
            param_wr_addr = idx;
            param_wr_data = data;
            @(posedge clk); #1;
            param_wr_en   = 1'b0;
        end
    endtask

    //=========================================================
    // Main
    //=========================================================
    initial begin
        reset = 1; start = 0;
        param_wr_en = 0; param_wr_addr = 0; param_wr_data = 0;
        imem_prog_en = 0; imem_prog_addr = 0; imem_prog_din = 0;
        dmem_host_en = 0; dmem_host_we = 0; dmem_host_addr = 0; dmem_host_din = 0;
        dmem_prog_en = 0; dmem_prog_we = 0; dmem_prog_addr = 0; dmem_prog_din = 0;

        repeat(4) @(posedge clk);
        reset = 1'b0;
        repeat(2) @(posedge clk);

        // === TEST 1: IMEM 写入 ===
        $display("\n=== TEST 1: IMEM write ===");
        imem_write(9'd0, 32'hDEAD_0000);
        imem_write(9'd1, 32'hDEAD_0001);
        imem_write(9'd2, 32'hDEAD_0002);
        imem_write(9'd3, 32'hDEAD_0003);
        imem_write(9'd4, 32'hDEAD_0004);
        imem_write(9'd5, 32'hDEAD_0005);
        imem_write(9'd6, 32'hDEAD_0006);
        imem_write(9'd7, 32'hDEAD_0007);
        @(negedge clk); imem_prog_en = 0; imem_prog_din = 0;
        repeat(2) @(posedge clk);

        // === TEST 2: IMEM 读回 ===
        $display("\n=== TEST 2: IMEM readback ===");
        imem_read_check(9'd0, 32'hDEAD_0000);
        imem_read_check(9'd1, 32'hDEAD_0001);
        imem_read_check(9'd3, 32'hDEAD_0003);
        imem_read_check(9'd7, 32'hDEAD_0007);
        @(negedge clk); imem_prog_en = 0; imem_prog_din = 0;
        repeat(2) @(posedge clk);

        // === TEST 3: DMEM Port A 写入 ===
        $display("\n=== TEST 3: DMEM Port A write ===");
        dmem_host_write(8'd0,  64'hAAAA_BBBB_CCCC_0000);
        dmem_host_write(8'd1,  64'hAAAA_BBBB_CCCC_0001);
        dmem_host_write(8'd2,  64'hAAAA_BBBB_CCCC_0002);
        dmem_host_write(8'd10, 64'h1234_5678_9ABC_DEF0);
        dmem_host_write(8'd20, 64'hFFFF_FFFF_FFFF_FFFF);
        repeat(2) @(posedge clk);

        // === TEST 4: DMEM Port A 读回 ===
        $display("\n=== TEST 4: DMEM Port A readback ===");
        dmem_host_read_check(8'd0,  64'hAAAA_BBBB_CCCC_0000);
        dmem_host_read_check(8'd1,  64'hAAAA_BBBB_CCCC_0001);
        dmem_host_read_check(8'd2,  64'hAAAA_BBBB_CCCC_0002);
        dmem_host_read_check(8'd10, 64'h1234_5678_9ABC_DEF0);
        dmem_host_read_check(8'd20, 64'hFFFF_FFFF_FFFF_FFFF);
        repeat(2) @(posedge clk);

        // === TEST 5: DMEM Port B 写入与读回 ===
        $display("\n=== TEST 5: DMEM Port B write & readback ===");
        dmem_portB_write(8'd50, 64'hB0B0_B0B0_B0B0_B0B0);
        dmem_portB_write(8'd51, 64'hCAFE_BABE_DEAD_BEEF);
        repeat(2) @(posedge clk);
        dmem_portB_read_check(8'd50, 64'hB0B0_B0B0_B0B0_B0B0);
        dmem_portB_read_check(8'd51, 64'hCAFE_BABE_DEAD_BEEF);
        repeat(2) @(posedge clk);

        // === TEST 6: 写 kernel 参数 ===
        $display("\n=== TEST 6: Kernel params ===");
        param_write(3'd0, 64'h0000_0000_0000_1000);
        param_write(3'd1, 64'h0000_0000_0000_2000);
        param_write(3'd2, 64'h0000_0000_0000_0010);
        $display("[INFO] params written (no readback port)");

        // === TEST 7: Kernel launch ===
        $display("\n=== TEST 7: Kernel launch ===");
        @(negedge clk); start = 1'b1;
        $display("[INFO] start=1 at time %0t", $time);
        begin : wait_done
            integer timeout;
            timeout = 0;
            while (!done && timeout < 500) begin
                @(posedge clk); timeout = timeout + 1;
            end
            if (done) $display("[PASS] done=1 at time %0t (%0d cycles)", $time, timeout);
            else      $display("[FAIL] done never asserted");
        end
        @(negedge clk); start = 0;
        repeat(3) @(posedge clk);

        // === TEST 8: kernel 后 DMEM 数据完整性 ===
        $display("\n=== TEST 8: DMEM integrity after kernel ===");
        dmem_host_read_check(8'd0,  64'hAAAA_BBBB_CCCC_0000);
        dmem_host_read_check(8'd10, 64'h1234_5678_9ABC_DEF0);
        dmem_host_read_check(8'd20, 64'hFFFF_FFFF_FFFF_FFFF);

        // === TEST 9: 第二次 launch ===
        $display("\n=== TEST 9: Second launch ===");
        @(negedge clk); start = 1'b1;
        begin : wait_done2
            integer timeout2;
            timeout2 = 0;
            while (!done && timeout2 < 500) begin
                @(posedge clk); timeout2 = timeout2 + 1;
            end
            if (done) $display("[PASS] 2nd done=1 at time %0t", $time);
            else      $display("[FAIL] 2nd done never asserted");
        end
        @(negedge clk); start = 0;
        repeat(4) @(posedge clk);

        $display("\n=== ALL TESTS COMPLETE ===");
        $finish;
    end

    initial begin
        $dumpfile("tb_gpu_top.vcd");
        $dumpvars(0, tb_gpu_top);
    end

endmodule