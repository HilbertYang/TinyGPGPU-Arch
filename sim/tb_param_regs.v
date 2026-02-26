// tb_param_regs.v  (with forwarding tests) - fixed expected values
`timescale 1ns/1ps

module tb_param_regs;

    reg        clk, rst_n;
    reg        wr_en;
    reg  [2:0] wr_addr;
    reg [63:0] wr_data;
    reg  [2:0] rd_addr;
    wire [63:0] rd_data;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    param_regs dut(
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr), .rd_data(rd_data)
    );

    always #5 clk = ~clk;

    task check64;
        input [63:0] got, exp;
        input [191:0] name;
        begin
            if (got === exp) begin
                $display("  PASS  %-26s  got=%016h", name, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %-26s  got=%016h  exp=%016h", name, got, exp);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task write_param;
        input [2:0]  addr;
        input [63:0] data;
        begin
            @(negedge clk);
            wr_en = 1; wr_addr = addr; wr_data = data;
            @(posedge clk); #1;
            wr_en = 0;
        end
    endtask

    integer i;

    // Track expected contents of param array in testbench
    // so expected values stay consistent as tests overwrite entries.
    reg [63:0] expected [0:7];

    initial begin
        clk = 0; rst_n = 0;
        wr_en = 0; wr_addr = 0; wr_data = 0; rd_addr = 0;
        for (i = 0; i < 8; i = i + 1) expected[i] = 64'd0;

        $display("\n===== param_regs (with forwarding) testbench =====");

        // ---- 1. Reset ----
        $display("\n[1] Reset: all params must read 0");
        @(posedge clk); #1; rst_n = 1;
        for (i = 0; i < 8; i = i + 1) begin
            rd_addr = i; #1;
            check64(rd_data, 64'd0, "reset zero");
        end

        // ---- 2. Write all 8, read back next cycle ----
        $display("\n[2] Normal write then read (different cycles)");
        for (i = 0; i < 8; i = i + 1) begin
            expected[i] = 64'hA0A0_0000_0000_0000 | (i * 64'h0101_0101);
            write_param(i, expected[i]);
        end
        for (i = 0; i < 8; i = i + 1) begin
            rd_addr = i; #1;
            check64(rd_data, expected[i], "normal rd");
        end

        // ---- 3. Forwarding: same-cycle write+read on same address ----
        $display("\n[3] Forwarding: same-cycle read/write to same address");
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            wr_en = 1; wr_addr = i;
            wr_data = 64'hF0F0_BEEF_0000_0000 | i;
            expected[i] = wr_data;
            rd_addr = i;
            #1;
            check64(rd_data, expected[i], "fwd same addr");
            @(posedge clk); #1; wr_en = 0;
        end
        // After loop: expected[] = F0F0_BEEF_0000_000x for all x

        // ---- 4. No false forwarding when addrs differ ----
        $display("\n[4] No false forwarding when read addr != write addr");

        // Write param[2] = CAFE..., read param[2] next cycle to establish
        write_param(3'd2, 64'hCAFE_CAFE_CAFE_CAFE);
        expected[2] = 64'hCAFE_CAFE_CAFE_CAFE;

        // Now write param[5], read param[2] at same time — no forwarding
        @(negedge clk);
        wr_en = 1; wr_addr = 3'd5; wr_data = 64'hDEAD_DEAD_DEAD_DEAD;
        expected[5] = wr_data;
        rd_addr = 3'd2;
        #1;
        check64(rd_data, expected[2], "no false fwd diff addr");
        @(posedge clk); #1; wr_en = 0;

        // Write param[1], read param[3] — both non-zero, different
        @(negedge clk);
        wr_en = 1; wr_addr = 3'd1; wr_data = 64'h1234_5678_9ABC_DEF0;
        expected[1] = wr_data;
        rd_addr = 3'd3;
        #1;
        check64(rd_data, expected[3], "no false fwd p3");
        @(posedge clk); #1; wr_en = 0;

        // ---- 5. Boundary: param 0 and param 7 forwarding ----
        $display("\n[5] Boundary params 0 and 7 forwarding");
        @(negedge clk);
        wr_en = 1; wr_addr = 3'd0; wr_data = 64'hAAAA_AAAA_AAAA_AAAA;
        expected[0] = wr_data;
        rd_addr = 3'd0; #1;
        check64(rd_data, expected[0], "fwd param0");
        @(posedge clk); #1; wr_en = 0;

        @(negedge clk);
        wr_en = 1; wr_addr = 3'd7; wr_data = 64'h5555_5555_5555_5555;
        expected[7] = wr_data;
        rd_addr = 3'd7; #1;
        check64(rd_data, expected[7], "fwd param7");
        @(posedge clk); #1; wr_en = 0;

        // ---- 6. wr_en=0: no forwarding, no write ----
        $display("\n[6] wr_en=0: no forwarding, value unchanged");
        // param[4] currently = expected[4] (set in step 3)
        @(negedge clk);
        wr_en = 0; wr_addr = 3'd4; wr_data = 64'hBAD0_BAD0_BAD0_BAD0;
        rd_addr = 3'd4; #1;
        check64(rd_data, expected[4], "no fwd wr_en=0");
        @(posedge clk); #1;
        rd_addr = 3'd4; #1;
        check64(rd_data, expected[4], "no write wr_en=0");

        // ---- 7. Overwrite: forwarding reflects new wr_data ----
        $display("\n[7] Overwrite: forwarding always shows current wr_data");
        write_param(3'd6, 64'h1111_1111_1111_1111);
        expected[6] = 64'h1111_1111_1111_1111;
        @(negedge clk);
        wr_en = 1; wr_addr = 3'd6; wr_data = 64'h9999_9999_9999_9999;
        expected[6] = wr_data;
        rd_addr = 3'd6; #1;
        check64(rd_data, expected[6], "fwd overwrite");
        @(posedge clk); #1; wr_en = 0;
        rd_addr = 3'd6; #1;
        check64(rd_data, expected[6], "overwrite in array");

        // ---- 8. Forwarding cycle followed by normal read ----
        $display("\n[8] Forwarding cycle followed by normal read next cycle");
        @(negedge clk);
        wr_en = 1; wr_addr = 3'd3; wr_data = 64'hBEEF_FEED_CAFE_BABE;
        expected[3] = wr_data;
        rd_addr = 3'd3; #1;
        check64(rd_data, expected[3], "fwd cycle");
        @(posedge clk); #1; wr_en = 0;
        rd_addr = 3'd3; #1;
        check64(rd_data, expected[3], "normal rd after fwd");

        // ---- 9. Reset clears all ----
        $display("\n[9] Reset clears all params");
        rst_n = 0;
        @(posedge clk); #1; rst_n = 1;
        for (i = 0; i < 8; i = i + 1) begin
            rd_addr = i; #1;
            check64(rd_data, 64'd0, "post-reset zero");
        end

        $display("\n========================================");
        $display("  Results: %0d PASS  /  %0d FAIL", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  *** SOME TESTS FAILED ***");
        $display("========================================");
        $finish;
    end

endmodule