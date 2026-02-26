// tb_regfile.v  (with forwarding tests)
// Testbench for 16×64-bit register file with internal write-to-read forwarding
//
// Test groups:
//  1. Reset
//  2. R0 hardwired zero (write ignored, forwarding suppressed)
//  3. Normal write → read (no forwarding needed, different cycle)
//  4. FORWARDING — rs1/rs2/rs3 all read forwarded value same cycle as write
//  5. FORWARDING — simultaneous write + read on all three ports to same reg
//  6. FORWARDING — write to Rx while other ports read different registers (no false fwd)
//  7. wr_en=0 → no write, no forwarding
//  8. Overwrite (two consecutive writes to same register)
//  9. Reset clears all after writes
// 10. Boundary: R15 read/write/forwarding

`timescale 1ns/1ps

module tb_regfile;

    reg        clk, rst_n;
    reg  [3:0] rs1_addr, rs2_addr, rs3_addr;
    wire [63:0] rs1_data, rs2_data, rs3_data;
    reg        wr_en;
    reg  [3:0] wr_addr;
    reg  [63:0] wr_data;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    regfile dut(
        .clk(clk), .rst_n(rst_n),
        .rs1_addr(rs1_addr), .rs1_data(rs1_data),
        .rs2_addr(rs2_addr), .rs2_data(rs2_data),
        .rs3_addr(rs3_addr), .rs3_data(rs3_data),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------ utils
    task check64;
        input [63:0] got, exp;
        input [191:0] name;  // 24 chars
        begin
            if (got === exp) begin
                $display("  PASS  %-24s  got=%016h", name, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %-24s  got=%016h  exp=%016h", name, got, exp);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // Drive write port for one cycle, then deassert wr_en
    task write_reg;
        input [3:0]  addr;
        input [63:0] data;
        begin
            @(negedge clk);          // set up before rising edge
            wr_en = 1; wr_addr = addr; wr_data = data;
            @(posedge clk); #1;      // latch
            wr_en = 0;
        end
    endtask

    integer i;

    initial begin
        clk = 0; rst_n = 0;
        wr_en = 0; wr_addr = 0; wr_data = 0;
        rs1_addr = 0; rs2_addr = 0; rs3_addr = 0;

        // ================================================================
        $display("\n===== regfile (with forwarding) testbench =====");

        // ---- 1. Reset ----
        $display("\n[1] Reset: all regs must read 0");
        @(posedge clk); #1; rst_n = 1;
        for (i = 0; i < 16; i = i + 1) begin
            rs1_addr = i; #1;
            check64(rs1_data, 64'd0, "reset zero");
        end

        // ---- 2. R0 hardwired zero ----
        $display("\n[2] R0 hardwired zero");
        // 2a: write ignored in array
        write_reg(4'd0, 64'hDEAD_BEEF_DEAD_BEEF);
        rs1_addr = 0; #1;
        check64(rs1_data, 64'd0, "R0 write ignored");

        // 2b: forwarding suppressed even with wr_en active on R0
        @(negedge clk);
        wr_en = 1; wr_addr = 4'd0; wr_data = 64'hFFFF_FFFF_FFFF_FFFF;
        rs1_addr = 4'd0; rs2_addr = 4'd0; rs3_addr = 4'd0;
        #1; // combinational settle, before clock edge
        check64(rs1_data, 64'd0, "R0 fwd suppressed rs1");
        check64(rs2_data, 64'd0, "R0 fwd suppressed rs2");
        check64(rs3_data, 64'd0, "R0 fwd suppressed rs3");
        @(posedge clk); #1; wr_en = 0;

        // ---- 3. Normal write then read (different cycle) ----
        $display("\n[3] Normal write then read (no forwarding needed)");
        write_reg(4'd1, 64'h1111_1111_1111_1111);
        write_reg(4'd2, 64'h2222_2222_2222_2222);
        write_reg(4'd3, 64'h3333_3333_3333_3333);
        rs1_addr = 4'd1; rs2_addr = 4'd2; rs3_addr = 4'd3; #1;
        check64(rs1_data, 64'h1111_1111_1111_1111, "normal rd R1");
        check64(rs2_data, 64'h2222_2222_2222_2222, "normal rd R2");
        check64(rs3_data, 64'h3333_3333_3333_3333, "normal rd R3");

        // ---- 4. Forwarding — rs1 reads write-cycle value ----
        $display("\n[4] Forwarding on rs1 / rs2 / rs3 independently");

        // rs1 forwarding: set read addr to target, assert write in same cycle
        @(negedge clk);
        wr_en = 1; wr_addr = 4'd5; wr_data = 64'hABCD_EF01_2345_6789;
        rs1_addr = 4'd5; rs2_addr = 4'd1; rs3_addr = 4'd2;
        #1; // combinational, before posedge
        check64(rs1_data, 64'hABCD_EF01_2345_6789, "fwd rs1 same cycle");
        check64(rs2_data, 64'h1111_1111_1111_1111, "no fwd rs2 (diff addr)");
        @(posedge clk); #1; wr_en = 0;

        // rs2 forwarding
        @(negedge clk);
        wr_en = 1; wr_addr = 4'd6; wr_data = 64'hCAFE_BABE_0000_0001;
        rs1_addr = 4'd1; rs2_addr = 4'd6; rs3_addr = 4'd2;
        #1;
        check64(rs2_data, 64'hCAFE_BABE_0000_0001, "fwd rs2 same cycle");
        check64(rs1_data, 64'h1111_1111_1111_1111, "no fwd rs1 (diff addr)");
        @(posedge clk); #1; wr_en = 0;

        // rs3 forwarding
        @(negedge clk);
        wr_en = 1; wr_addr = 4'd7; wr_data = 64'hDEAD_C0DE_FEED_FACE;
        rs1_addr = 4'd1; rs2_addr = 4'd2; rs3_addr = 4'd7;
        #1;
        check64(rs3_data, 64'hDEAD_C0DE_FEED_FACE, "fwd rs3 same cycle");
        @(posedge clk); #1; wr_en = 0;

        // ---- 5. All three ports forwarded simultaneously to same register ----
        $display("\n[5] All three ports forwarded to same write target");
        @(negedge clk);
        wr_en = 1; wr_addr = 4'd8; wr_data = 64'h5A5A_5A5A_5A5A_5A5A;
        rs1_addr = 4'd8; rs2_addr = 4'd8; rs3_addr = 4'd8;
        #1;
        check64(rs1_data, 64'h5A5A_5A5A_5A5A_5A5A, "fwd all3 rs1");
        check64(rs2_data, 64'h5A5A_5A5A_5A5A_5A5A, "fwd all3 rs2");
        check64(rs3_data, 64'h5A5A_5A5A_5A5A_5A5A, "fwd all3 rs3");
        @(posedge clk); #1; wr_en = 0;
        // Verify the write also landed in the array
        rs1_addr = 4'd8; #1;
        check64(rs1_data, 64'h5A5A_5A5A_5A5A_5A5A, "fwd written to array");

        // ---- 6. Forwarding does not bleed to unrelated ports ----
        $display("\n[6] No false forwarding to unrelated addresses");
        @(negedge clk);
        wr_en = 1; wr_addr = 4'd9; wr_data = 64'hF00D_F00D_F00D_F00D;
        rs1_addr = 4'd1; rs2_addr = 4'd2; rs3_addr = 4'd3;
        #1;
        check64(rs1_data, 64'h1111_1111_1111_1111, "no fwd bleed rs1");
        check64(rs2_data, 64'h2222_2222_2222_2222, "no fwd bleed rs2");
        check64(rs3_data, 64'h3333_3333_3333_3333, "no fwd bleed rs3");
        @(posedge clk); #1; wr_en = 0;

        // ---- 7. wr_en=0: no write and no forwarding ----
        $display("\n[7] wr_en=0: no write, no forwarding");
        @(negedge clk);
        wr_en = 0; wr_addr = 4'd4; wr_data = 64'hBAD_BAD_BAD_BAD_0000;
        rs1_addr = 4'd4;
        #1;
        check64(rs1_data, 64'd0, "no fwd wr_en=0");  // R4 was never written
        @(posedge clk); #1;
        rs1_addr = 4'd4; #1;
        check64(rs1_data, 64'd0, "no write wr_en=0");

        // ---- 8. Overwrite: second write updates forwarded value ----
        $display("\n[8] Overwrite: forwarding reflects latest wr_data");
        write_reg(4'd10, 64'hAAAA_AAAA_AAAA_AAAA);
        // Now overwrite R10 and forward simultaneously
        @(negedge clk);
        wr_en = 1; wr_addr = 4'd10; wr_data = 64'hBBBB_BBBB_BBBB_BBBB;
        rs1_addr = 4'd10;
        #1;
        check64(rs1_data, 64'hBBBB_BBBB_BBBB_BBBB, "fwd overwrites");
        @(posedge clk); #1; wr_en = 0;
        rs1_addr = 4'd10; #1;
        check64(rs1_data, 64'hBBBB_BBBB_BBBB_BBBB, "overwrite in array");

        // ---- 9. Reset clears all after writes ----
        $display("\n[9] Reset clears all registers");
        rst_n = 0;
        @(posedge clk); #1; rst_n = 1;
        for (i = 0; i < 16; i = i + 1) begin
            rs1_addr = i; #1;
            check64(rs1_data, 64'd0, "post-reset zero");
        end

        // ---- 10. Boundary: R15 write/read/forwarding ----
        $display("\n[10] Boundary: R15");
        write_reg(4'd15, 64'hF0F0_F0F0_F0F0_F0F0);
        rs1_addr = 4'd15; #1;
        check64(rs1_data, 64'hF0F0_F0F0_F0F0_F0F0, "R15 normal rd");

        @(negedge clk);
        wr_en = 1; wr_addr = 4'd15; wr_data = 64'h0F0F_0F0F_0F0F_0F0F;
        rs1_addr = 4'd15; rs2_addr = 4'd15; rs3_addr = 4'd15;
        #1;
        check64(rs1_data, 64'h0F0F_0F0F_0F0F_0F0F, "R15 fwd rs1");
        check64(rs2_data, 64'h0F0F_0F0F_0F0F_0F0F, "R15 fwd rs2");
        check64(rs3_data, 64'h0F0F_0F0F_0F0F_0F0F, "R15 fwd rs3");
        @(posedge clk); #1; wr_en = 0;

        // ---- Summary ----
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