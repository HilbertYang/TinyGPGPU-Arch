// tb_ECG.v
// ECG beat classifier testbench for gpu_core3
// Architecture: 1 hidden-layer classifier (64 -> 2)
//   logit[o] = sum_i(X[i] * W[o][i]) + bias[o],  o in {0,1}
//
// NOP policy: 3 NOPs after every write instruction before dependent consumer
// ISA:  {op[4:0], rd[3:0], rs1[3:0], rs2[3:0], imm15[14:0]}
//       [31:27]=OP  [26:23]=RD  [22:19]=RS1  [18:15]=RS2  [14:0]=IMM15
//
// DMEM layout (64-bit words, each word = 4x BF16 packed {lane3|lane2|lane1|lane0}):
//   [  0.. 63]  features:  DMEM[i] = {X4[i], X3[i], X2[i], X1[i]}
//   [ 64..127]  W1:        DMEM[64+i] = {W1[i], W1[i], W1[i], W1[i]}
//   [128..191]  W2:        DMEM[128+i] = {W2[i], W2[i], W2[i], W2[i]}
//   [192]       bias1 x4   (read-only during inference, preserved)
//   [193]       bias2 x4   (read-only during inference, preserved)
//   [194]       logit1 x4  (written after dot-product loop)
//   [195]       logit2 x4  (written after dot-product loop)
//
// Computation: 4 beats processed in parallel via SIMD lanes
//   Beat1 in lane0 [15:0], Beat2 in lane1 [31:16],
//   Beat3 in lane2 [47:32], Beat4 in lane3 [63:48]
//
`timescale 1ns/1ps

module tb_gpu_core3;

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

    task param_write;
        input [2:0]  addr;
        input [63:0] data;
        begin
            @(negedge clk);
            param_wr_en    = 1'b1;
            param_wr_addr  = addr;
            param_wr_data  = data;
            @(posedge clk); #1;
            param_wr_en = 1'b0;
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
            cnt = 4;
            @(negedge clk); run = 1'b1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;
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
    // DMEM initialisation: ECG classifier data
    //
    // DMEM[0..63]   : feature vectors packed across 4 SIMD lanes
    //                 DMEM[i] = {X4[i], X3[i], X2[i], X1[i]}
    // DMEM[64..127] : W1[i] replicated across all lanes
    // DMEM[128..191]: W2[i] replicated across all lanes
    // DMEM[192]     : bias1 replicated x4
    // DMEM[193]     : bias2 replicated x4
    // -------------------------------------------------------
    task load_classifier_dmem;
        begin
        // --- Features: DMEM[i] = {X4[i], X3[i], X2[i], X1[i]} ---
        dmem_write(8'd  0, 64'h3E073F293E0E3F1D); // feat[i=0]
        dmem_write(8'd  1, 64'h3D1C3F1A3D613F03); // feat[i=1]
        dmem_write(8'd  2, 64'h3E3E3E3F3D973E42); // feat[i=2]
        dmem_write(8'd  3, 64'h3E213D153E1D3D2E); // feat[i=3]
        dmem_write(8'd  4, 64'h3E7B3E0E3E4B3DE2); // feat[i=4]
        dmem_write(8'd  5, 64'h3D683F3F3E043F1F); // feat[i=5]
        dmem_write(8'd  6, 64'h3E613E2E3E843DB5); // feat[i=6]
        dmem_write(8'd  7, 64'h3EB13E253EA03DD6); // feat[i=7]
        dmem_write(8'd  8, 64'h3D973F133DB33F08); // feat[i=8]
        dmem_write(8'd  9, 64'h3E803D063E953D11); // feat[i=9]
        dmem_write(8'd 10, 64'h3D263F203DEA3F26); // feat[i=10]
        dmem_write(8'd 11, 64'h3E043ECF3DD23EC4); // feat[i=11]
        dmem_write(8'd 12, 64'h3EB33D803ED33D4B); // feat[i=12]
        dmem_write(8'd 13, 64'h3E883E1D3E123DAB); // feat[i=13]
        dmem_write(8'd 14, 64'h3E6E3DC53E5E3D74); // feat[i=14]
        dmem_write(8'd 15, 64'h3EB73DA33EDB3DB5); // feat[i=15]
        dmem_write(8'd 16, 64'h3E973DA83EA33CE8); // feat[i=16]
        dmem_write(8'd 17, 64'h3E5C3D093E9E3D7F); // feat[i=17]
        dmem_write(8'd 18, 64'h3EC13E0D3F093DBA); // feat[i=18]
        dmem_write(8'd 19, 64'h3C253F333D403F09); // feat[i=19]
        dmem_write(8'd 20, 64'h3E6A3E433E453DB6); // feat[i=20]
        dmem_write(8'd 21, 64'h3DAE3EF03E2E3EFE); // feat[i=21]
        dmem_write(8'd 22, 64'h3E023F133E1B3F01); // feat[i=22]
        dmem_write(8'd 23, 64'h3E993DCD3EA13D2B); // feat[i=23]
        dmem_write(8'd 24, 64'h3EC73DD63EBC3DDF); // feat[i=24]
        dmem_write(8'd 25, 64'h3E233F2A3E5D3F0B); // feat[i=25]
        dmem_write(8'd 26, 64'h3EF63D343F013D1B); // feat[i=26]
        dmem_write(8'd 27, 64'h3D053F133D503ED9); // feat[i=27]
        dmem_write(8'd 28, 64'h3E793DAC3E453CF3); // feat[i=28]
        dmem_write(8'd 29, 64'h3D9D3F0C3D3D3EFA); // feat[i=29]
        dmem_write(8'd 30, 64'h3ECA3E8B3EB13E51); // feat[i=30]
        dmem_write(8'd 31, 64'h3E843E0F3EAB3D9E); // feat[i=31]
        dmem_write(8'd 32, 64'h3E983D803EB03D4A); // feat[i=32]
        dmem_write(8'd 33, 64'h3E043EAD3D953EA8); // feat[i=33]
        dmem_write(8'd 34, 64'h3E913E363EAC3D95); // feat[i=34]
        dmem_write(8'd 35, 64'h3E883E033E893DF6); // feat[i=35]
        dmem_write(8'd 36, 64'h3E913E593E763D2D); // feat[i=36]
        dmem_write(8'd 37, 64'h3EA93DD63EA53DBF); // feat[i=37]
        dmem_write(8'd 38, 64'h3ED73D7E3EF63CFB); // feat[i=38]
        dmem_write(8'd 39, 64'h3D943F553E393F43); // feat[i=39]
        dmem_write(8'd 40, 64'h3E793DDB3E813D68); // feat[i=40]
        dmem_write(8'd 41, 64'h3E093D293E133D1A); // feat[i=41]
        dmem_write(8'd 42, 64'h3EA53D843ECD3CF9); // feat[i=42]
        dmem_write(8'd 43, 64'h3E823D8B3E3B3D8D); // feat[i=43]
        dmem_write(8'd 44, 64'h3EA13E883E9E3E09); // feat[i=44]
        dmem_write(8'd 45, 64'h3E5D3EE53E183EBC); // feat[i=45]
        dmem_write(8'd 46, 64'h3D8A3F073DEF3F00); // feat[i=46]
        dmem_write(8'd 47, 64'h3EBF3D903EC03D99); // feat[i=47]
        dmem_write(8'd 48, 64'h3ED13D513EDC3D15); // feat[i=48]
        dmem_write(8'd 49, 64'h3DB13F103D513F02); // feat[i=49]
        dmem_write(8'd 50, 64'h3DBC3F1E3E2A3F07); // feat[i=50]
        dmem_write(8'd 51, 64'h3E5D3E843E033E99); // feat[i=51]
        dmem_write(8'd 52, 64'h3EC63E4A3E8E3DC4); // feat[i=52]
        dmem_write(8'd 53, 64'h3C483F293DCA3F27); // feat[i=53]
        dmem_write(8'd 54, 64'h3E563E903E473E12); // feat[i=54]
        dmem_write(8'd 55, 64'h3EBD3DCC3EA03D4A); // feat[i=55]
        dmem_write(8'd 56, 64'h3EC43EC13EBD3E76); // feat[i=56]
        dmem_write(8'd 57, 64'h3E023F083E2D3F0D); // feat[i=57]
        dmem_write(8'd 58, 64'h3EE53E523EF23DFE); // feat[i=58]
        dmem_write(8'd 59, 64'h3E283F073E083F03); // feat[i=59]
        dmem_write(8'd 60, 64'h3C783F323DA83F30); // feat[i=60]
        dmem_write(8'd 61, 64'h3E343E163EA13D9E); // feat[i=61]
        dmem_write(8'd 62, 64'h3EEC3E473F173DFE); // feat[i=62]
        dmem_write(8'd 63, 64'h3D3F3F0E3E123F05); // feat[i=63]
        // --- W1: DMEM[64+i] = {W1[i] x4} ---
        dmem_write(8'd 64, 64'hBF13BF13BF13BF13); // W1[ 0]=BF13
        dmem_write(8'd 65, 64'hBF1FBF1FBF1FBF1F); // W1[ 1]=BF1F
        dmem_write(8'd 66, 64'hBF2DBF2DBF2DBF2D); // W1[ 2]=BF2D
        dmem_write(8'd 67, 64'h3F0D3F0D3F0D3F0D); // W1[ 3]=3F0D
        dmem_write(8'd 68, 64'h3F043F043F043F04); // W1[ 4]=3F04
        dmem_write(8'd 69, 64'hBF36BF36BF36BF36); // W1[ 5]=BF36
        dmem_write(8'd 70, 64'h3F143F143F143F14); // W1[ 6]=3F14
        dmem_write(8'd 71, 64'h3F203F203F203F20); // W1[ 7]=3F20
        dmem_write(8'd 72, 64'hBEFCBEFCBEFCBEFC); // W1[ 8]=BEFC
        dmem_write(8'd 73, 64'h3F0C3F0C3F0C3F0C); // W1[ 9]=3F0C
        dmem_write(8'd 74, 64'hBF0EBF0EBF0EBF0E); // W1[10]=BF0E
        dmem_write(8'd 75, 64'hBF06BF06BF06BF06); // W1[11]=BF06
        dmem_write(8'd 76, 64'h3F063F063F063F06); // W1[12]=3F06
        dmem_write(8'd 77, 64'h3F133F133F133F13); // W1[13]=3F13
        dmem_write(8'd 78, 64'h3EB33EB33EB33EB3); // W1[14]=3EB3
        dmem_write(8'd 79, 64'h3EB13EB13EB13EB1); // W1[15]=3EB1
        dmem_write(8'd 80, 64'h3ED13ED13ED13ED1); // W1[16]=3ED1
        dmem_write(8'd 81, 64'h3EF93EF93EF93EF9); // W1[17]=3EF9
        dmem_write(8'd 82, 64'h3EB63EB63EB63EB6); // W1[18]=3EB6
        dmem_write(8'd 83, 64'hBF38BF38BF38BF38); // W1[19]=BF38
        dmem_write(8'd 84, 64'h3F083F083F083F08); // W1[20]=3F08
        dmem_write(8'd 85, 64'hBF0ABF0ABF0ABF0A); // W1[21]=BF0A
        dmem_write(8'd 86, 64'hBF1EBF1EBF1EBF1E); // W1[22]=BF1E
        dmem_write(8'd 87, 64'h3EF13EF13EF13EF1); // W1[23]=3EF1
        dmem_write(8'd 88, 64'h3ECC3ECC3ECC3ECC); // W1[24]=3ECC
        dmem_write(8'd 89, 64'hBF0BBF0BBF0BBF0B); // W1[25]=BF0B
        dmem_write(8'd 90, 64'h3EDE3EDE3EDE3EDE); // W1[26]=3EDE
        dmem_write(8'd 91, 64'hBF3FBF3FBF3FBF3F); // W1[27]=BF3F
        dmem_write(8'd 92, 64'h3EB73EB73EB73EB7); // W1[28]=3EB7
        dmem_write(8'd 93, 64'hBF0ABF0ABF0ABF0A); // W1[29]=BF0A
        dmem_write(8'd 94, 64'h3ED03ED03ED03ED0); // W1[30]=3ED0
        dmem_write(8'd 95, 64'h3EA43EA43EA43EA4); // W1[31]=3EA4
        dmem_write(8'd 96, 64'h3EE23EE23EE23EE2); // W1[32]=3EE2
        dmem_write(8'd 97, 64'hBF13BF13BF13BF13); // W1[33]=BF13
        dmem_write(8'd 98, 64'h3F093F093F093F09); // W1[34]=3F09
        dmem_write(8'd 99, 64'h3F113F113F113F11); // W1[35]=3F11
        dmem_write(8'd100, 64'h3EFD3EFD3EFD3EFD); // W1[36]=3EFD
        dmem_write(8'd101, 64'h3F083F083F083F08); // W1[37]=3F08
        dmem_write(8'd102, 64'h3EAC3EAC3EAC3EAC); // W1[38]=3EAC
        dmem_write(8'd103, 64'hBF0ABF0ABF0ABF0A); // W1[39]=BF0A
        dmem_write(8'd104, 64'h3F023F023F023F02); // W1[40]=3F02
        dmem_write(8'd105, 64'h3F1E3F1E3F1E3F1E); // W1[41]=3F1E
        dmem_write(8'd106, 64'h3EE93EE93EE93EE9); // W1[42]=3EE9
        dmem_write(8'd107, 64'h3EFF3EFF3EFF3EFF); // W1[43]=3EFF
        dmem_write(8'd108, 64'h3EF43EF43EF43EF4); // W1[44]=3EF4
        dmem_write(8'd109, 64'hBF21BF21BF21BF21); // W1[45]=BF21
        dmem_write(8'd110, 64'hBF29BF29BF29BF29); // W1[46]=BF29
        dmem_write(8'd111, 64'h3ED53ED53ED53ED5); // W1[47]=3ED5
        dmem_write(8'd112, 64'h3F003F003F003F00); // W1[48]=3F00
        dmem_write(8'd113, 64'hBF2DBF2DBF2DBF2D); // W1[49]=BF2D
        dmem_write(8'd114, 64'hBF4ABF4ABF4ABF4A); // W1[50]=BF4A
        dmem_write(8'd115, 64'hBF21BF21BF21BF21); // W1[51]=BF21
        dmem_write(8'd116, 64'h3ED43ED43ED43ED4); // W1[52]=3ED4
        dmem_write(8'd117, 64'hBF2EBF2EBF2EBF2E); // W1[53]=BF2E
        dmem_write(8'd118, 64'h3F0F3F0F3F0F3F0F); // W1[54]=3F0F
        dmem_write(8'd119, 64'h3EE33EE33EE33EE3); // W1[55]=3EE3
        dmem_write(8'd120, 64'h3EE23EE23EE23EE2); // W1[56]=3EE2
        dmem_write(8'd121, 64'hBF19BF19BF19BF19); // W1[57]=BF19
        dmem_write(8'd122, 64'h3ECE3ECE3ECE3ECE); // W1[58]=3ECE
        dmem_write(8'd123, 64'hBF10BF10BF10BF10); // W1[59]=BF10
        dmem_write(8'd124, 64'hBF41BF41BF41BF41); // W1[60]=BF41
        dmem_write(8'd125, 64'h3F0F3F0F3F0F3F0F); // W1[61]=3F0F
        dmem_write(8'd126, 64'h3EA33EA33EA33EA3); // W1[62]=3EA3
        dmem_write(8'd127, 64'hBF2BBF2BBF2BBF2B); // W1[63]=BF2B
        // --- W2: DMEM[128+i] = {W2[i] x4} ---
        dmem_write(8'd128, 64'h3F0E3F0E3F0E3F0E); // W2[ 0]=3F0E
        dmem_write(8'd129, 64'h3F2C3F2C3F2C3F2C); // W2[ 1]=3F2C
        dmem_write(8'd130, 64'h3F2B3F2B3F2B3F2B); // W2[ 2]=3F2B
        dmem_write(8'd131, 64'hBF00BF00BF00BF00); // W2[ 3]=BF00
        dmem_write(8'd132, 64'hBF13BF13BF13BF13); // W2[ 4]=BF13
        dmem_write(8'd133, 64'h3F263F263F263F26); // W2[ 5]=3F26
        dmem_write(8'd134, 64'hBF00BF00BF00BF00); // W2[ 6]=BF00
        dmem_write(8'd135, 64'hBEE3BEE3BEE3BEE3); // W2[ 7]=BEE3
        dmem_write(8'd136, 64'h3F2E3F2E3F2E3F2E); // W2[ 8]=3F2E
        dmem_write(8'd137, 64'hBF00BF00BF00BF00); // W2[ 9]=BF00
        dmem_write(8'd138, 64'h3F123F123F123F12); // W2[10]=3F12
        dmem_write(8'd139, 64'h3F293F293F293F29); // W2[11]=3F29
        dmem_write(8'd140, 64'hBED0BED0BED0BED0); // W2[12]=BED0
        dmem_write(8'd141, 64'hBF02BF02BF02BF02); // W2[13]=BF02
        dmem_write(8'd142, 64'hBEF8BEF8BEF8BEF8); // W2[14]=BEF8
        dmem_write(8'd143, 64'hBEA3BEA3BEA3BEA3); // W2[15]=BEA3
        dmem_write(8'd144, 64'hBEEEBEEEBEEEBEEE); // W2[16]=BEEE
        dmem_write(8'd145, 64'hBEEDBEEDBEEDBEED); // W2[17]=BEED
        dmem_write(8'd146, 64'hBF07BF07BF07BF07); // W2[18]=BF07
        dmem_write(8'd147, 64'h3F423F423F423F42); // W2[19]=3F42
        dmem_write(8'd148, 64'hBF01BF01BF01BF01); // W2[20]=BF01
        dmem_write(8'd149, 64'h3F133F133F133F13); // W2[21]=3F13
        dmem_write(8'd150, 64'h3F203F203F203F20); // W2[22]=3F20
        dmem_write(8'd151, 64'hBEFABEFABEFABEFA); // W2[23]=BEFA
        dmem_write(8'd152, 64'hBEFBBEFBBEFBBEFB); // W2[24]=BEFB
        dmem_write(8'd153, 64'h3F3B3F3B3F3B3F3B); // W2[25]=3F3B
        dmem_write(8'd154, 64'hBEF8BEF8BEF8BEF8); // W2[26]=BEF8
        dmem_write(8'd155, 64'h3F353F353F353F35); // W2[27]=3F35
        dmem_write(8'd156, 64'hBF0DBF0DBF0DBF0D); // W2[28]=BF0D
        dmem_write(8'd157, 64'h3F303F303F303F30); // W2[29]=3F30
        dmem_write(8'd158, 64'hBE87BE87BE87BE87); // W2[30]=BE87
        dmem_write(8'd159, 64'hBEDABEDABEDABEDA); // W2[31]=BEDA
        dmem_write(8'd160, 64'hBEA9BEA9BEA9BEA9); // W2[32]=BEA9
        dmem_write(8'd161, 64'h3F2D3F2D3F2D3F2D); // W2[33]=3F2D
        dmem_write(8'd162, 64'hBED5BED5BED5BED5); // W2[34]=BED5
        dmem_write(8'd163, 64'hBED6BED6BED6BED6); // W2[35]=BED6
        dmem_write(8'd164, 64'hBEEABEEABEEABEEA); // W2[36]=BEEA
        dmem_write(8'd165, 64'hBEF2BEF2BEF2BEF2); // W2[37]=BEF2
        dmem_write(8'd166, 64'hBF02BF02BF02BF02); // W2[38]=BF02
        dmem_write(8'd167, 64'h3F123F123F123F12); // W2[39]=3F12
        dmem_write(8'd168, 64'hBEC5BEC5BEC5BEC5); // W2[40]=BEC5
        dmem_write(8'd169, 64'hBEF4BEF4BEF4BEF4); // W2[41]=BEF4
        dmem_write(8'd170, 64'hBEEEBEEEBEEEBEEE); // W2[42]=BEEE
        dmem_write(8'd171, 64'hBF0CBF0CBF0CBF0C); // W2[43]=BF0C
        dmem_write(8'd172, 64'hBF05BF05BF05BF05); // W2[44]=BF05
        dmem_write(8'd173, 64'h3F3C3F3C3F3C3F3C); // W2[45]=3F3C
        dmem_write(8'd174, 64'h3F323F323F323F32); // W2[46]=3F32
        dmem_write(8'd175, 64'hBEDEBEDEBEDEBEDE); // W2[47]=BEDE
        dmem_write(8'd176, 64'hBEA9BEA9BEA9BEA9); // W2[48]=BEA9
        dmem_write(8'd177, 64'h3F133F133F133F13); // W2[49]=3F13
        dmem_write(8'd178, 64'h3F253F253F253F25); // W2[50]=3F25
        dmem_write(8'd179, 64'h3F3E3F3E3F3E3F3E); // W2[51]=3F3E
        dmem_write(8'd180, 64'hBEA3BEA3BEA3BEA3); // W2[52]=BEA3
        dmem_write(8'd181, 64'h3F303F303F303F30); // W2[53]=3F30
        dmem_write(8'd182, 64'hBF1ABF1ABF1ABF1A); // W2[54]=BF1A
        dmem_write(8'd183, 64'hBEDBBEDBBEDBBEDB); // W2[55]=BEDB
        dmem_write(8'd184, 64'hBEF0BEF0BEF0BEF0); // W2[56]=BEF0
        dmem_write(8'd185, 64'h3F453F453F453F45); // W2[57]=3F45
        dmem_write(8'd186, 64'hBE8EBE8EBE8EBE8E); // W2[58]=BE8E
        dmem_write(8'd187, 64'h3F143F143F143F14); // W2[59]=3F14
        dmem_write(8'd188, 64'h3F363F363F363F36); // W2[60]=3F36
        dmem_write(8'd189, 64'hBF07BF07BF07BF07); // W2[61]=BF07
        dmem_write(8'd190, 64'hBEC9BEC9BEC9BEC9); // W2[62]=BEC9
        dmem_write(8'd191, 64'h3F2A3F2A3F2A3F2A); // W2[63]=3F2A
        // --- Biases (read-only; accumulators initialised from these) ---
        dmem_write(8'd192, 64'hBE39BE39BE39BE39); // bias1=BE39 (-0.1807) x4
        dmem_write(8'd193, 64'h3E0E3E0E3E0E3E0E); // bias2=3E0E (+0.1387) x4
        // --- Logit output slots (overwritten by epilogue ST64s) ---
        dmem_write(8'd194, 64'h0000000000000000); // logit1 placeholder
        dmem_write(8'd195, 64'h0000000000000000); // logit2 placeholder
        end
    endtask

    // -------------------------------------------------------
    // ECG Classifier program
    //
    // Parameters (param registers):
    //   P1 =   0 : base address of feature vectors in DMEM
    //   P2 =  64 : base address of W1 in DMEM
    //   P3 = 128 : base address of W2 in DMEM
    //   P4 =  64 : loop iteration count (64 feature dimensions)
    //   P5 = 192 : DMEM address of bias1 (load only, preserved)
    //   P6 = 193 : DMEM address of bias2 (load only, preserved)
    //   P7 = 194 : DMEM address of logit1 output
    //
    // Register assignment:
    //   R1  : running pointer into feature array  (starts at 0)
    //   R2  : running pointer into W1 array       (starts at 64)
    //   R3  : running pointer into W2 array       (starts at 128)
    //   R4  : loop limit (64)
    //   R5  : loop counter (0 -> 63)
    //   R6  : DMEM address of bias1 slot (192, used for LD64 only)
    //   R7  : DMEM address of bias2 slot (193, used for LD64 only)
    //   R8  : DMEM address of logit1 output (194)
    //   R9  : DMEM address of logit2 output (195, computed as R8+1)
    //   R10 : current X[i] (4 beats in SIMD lanes)
    //   R11 : current W1[i] (replicated across lanes)
    //   R12 : logit1 accumulator (initialised from bias1)
    //   R13 : logit2 accumulator (initialised from bias2)
    //   R14 : current W2[i] (replicated across lanes)
    //
    // Instruction addresses:
    //   0-12  : prologue (load params, compute R9, load biases)
    //   13-27 : main loop (15 instructions/iteration)
    //   28-31 : epilogue (store logits, RET)
    //
    // Hazard analysis (write+4 rule, all accesses verified):
    //   LD_PARAM Rx @ addr N, first use at addr N+5 or later ✓
    //   ADDI64 R9  @ addr 10, used @ addr 29 (epilogue, gap>>4) ✓
    //   LD64 R10 @ addr 15, used @ addrs 22,23 (gap 7,8) ✓
    //   LD64 R11 @ addr 16, used @ addr 22  (gap 6) ✓
    //   LD64 R14 @ addr 17, used @ addr 23  (gap 6) ✓
    //   MAC R12  @ addr 22, next read @ addr 22 (+15 instr) ✓
    //   MAC R13  @ addr 23, next read @ addr 23 (+15 instr) ✓
    //   Loop-exit path from last MAC to ST64: 10+ instructions ✓
    //   ST64 R12@28 and ST64 R13@29 have no GPR-write hazard ✓
    // -------------------------------------------------------
    task load_ecg_program;
        begin
        // --- Prologue ---
        // addr  0: R1  = P1 (base_X = 0)
        imem_write(9'd0,  ENC(OP_LD_PARAM, 4'd1,  4'd0, 4'd0, 15'd1));
        // addr  1: R2  = P2 (base_W1 = 64)
        imem_write(9'd1,  ENC(OP_LD_PARAM, 4'd2,  4'd0, 4'd0, 15'd2));
        // addr  2: R3  = P3 (base_W2 = 128)
        imem_write(9'd2,  ENC(OP_LD_PARAM, 4'd3,  4'd0, 4'd0, 15'd3));
        // addr  3: R4  = P4 (loop limit = 64)
        imem_write(9'd3,  ENC(OP_LD_PARAM, 4'd4,  4'd0, 4'd0, 15'd4));
        // addr  4: R6  = P5 (bias1 load addr = 192)
        imem_write(9'd4,  ENC(OP_LD_PARAM, 4'd6,  4'd0, 4'd0, 15'd5));
        // addr  5: R7  = P6 (bias2 load addr = 193)
        imem_write(9'd5,  ENC(OP_LD_PARAM, 4'd7,  4'd0, 4'd0, 15'd6));
        // addr  6: R8  = P7 (logit1 store addr = 194)
        imem_write(9'd6,  ENC(OP_LD_PARAM, 4'd8,  4'd0, 4'd0, 15'd7));
        // addr  7: R5  = 0  (loop counter; independent of above)
        imem_write(9'd7,  ENC(OP_MOV,      4'd5,  4'd0, 4'd0, 15'd0));
        // addr  8-9: NOPs (gap for R8@6 before ADDI64@10: gap=4 ✓)
        imem_write(9'd8,  NOP);
        imem_write(9'd9,  NOP);
        // addr 10: R9  = R8+1 (logit2 store addr = 195)
        //          R8 ready: written@6, consumer@10, gap=4 ✓
        imem_write(9'd10, ENC(OP_ADDI64,   4'd9,  4'd8, 4'd0, 15'd1));
        // addr 11: R12 = DMEM[R6+0] = bias1 (logit1 accumulator)
        //          R6 ready: written@4, consumer@11, gap=7 ✓
        imem_write(9'd11, ENC(OP_LD64,     4'd12, 4'd6, 4'd0, 15'd0));
        // addr 12: R13 = DMEM[R7+0] = bias2 (logit2 accumulator)
        //          R7 ready: written@5, consumer@12, gap=7 ✓
        imem_write(9'd12, ENC(OP_LD64,     4'd13, 4'd7, 4'd0, 15'd0));

        // --- Loop top = addr 13 ---
        // addr 13: predicate = (R5 >= R4)
        imem_write(9'd13, ENC(OP_SETP_GE,  4'd0,  4'd5, 4'd4, 15'd0));
        // addr 14: if predicate, branch to done (addr 28)
        imem_write(9'd14, ENC(OP_BPR,      4'd0,  4'd0, 4'd0, 15'd28));
        // addr 15-17: branch delay slots (execute regardless of BPR outcome)
        // addr 15: R10 = DMEM[R1+0] = X[i]
        imem_write(9'd15, ENC(OP_LD64,     4'd10, 4'd1, 4'd0, 15'd0));
        // addr 16: R11 = DMEM[R2+0] = W1[i]
        imem_write(9'd16, ENC(OP_LD64,     4'd11, 4'd2, 4'd0, 15'd0));
        // addr 17: R14 = DMEM[R3+0] = W2[i]
        imem_write(9'd17, ENC(OP_LD64,     4'd14, 4'd3, 4'd0, 15'd0));
        // addr 18: R1++  (advance feature pointer)
        imem_write(9'd18, ENC(OP_ADDI64,   4'd1,  4'd1, 4'd0, 15'd1));
        // addr 19: R2++  (advance W1 pointer)
        imem_write(9'd19, ENC(OP_ADDI64,   4'd2,  4'd2, 4'd0, 15'd1));
        // addr 20: R3++  (advance W2 pointer)
        imem_write(9'd20, ENC(OP_ADDI64,   4'd3,  4'd3, 4'd0, 15'd1));
        // addr 21: R5++  (increment loop counter)
        imem_write(9'd21, ENC(OP_ADDI64,   4'd5,  4'd5, 4'd0, 15'd1));
        // addr 22: R12 += R10 * R11  (logit1 += X[i] * W1[i])
        //          R10@15 gap=7, R11@16 gap=6, R12(acc) gap>=10 ✓
        imem_write(9'd22, ENC(OP_MAC_BF16, 4'd12, 4'd10, 4'd11, 15'd0));
        // addr 23: R13 += R10 * R14  (logit2 += X[i] * W2[i])
        //          R10@15 gap=8, R14@17 gap=6, R13(acc) gap>=11 ✓
        //          No dependency on R12 result at addr 22 ✓
        imem_write(9'd23, ENC(OP_MAC_BF16, 4'd13, 4'd10, 4'd14, 15'd0));
        // addr 24: branch back to loop top
        imem_write(9'd24, ENC(OP_BR,       4'd0,  4'd0, 4'd0, 15'd13));
        // addr 25-27: branch delay slots
        imem_write(9'd25, NOP);
        imem_write(9'd26, NOP);
        imem_write(9'd27, NOP);

        // --- Epilogue (done = addr 28) ---
        // Exit path: last MAC R12@22 → 23→24→25→26→27→13→14→15→16→17→28 (gap=10) ✓
        // addr 28: DMEM[R8+0] = R12  (write logit1 to DMEM[194])
        imem_write(9'd28, ENC(OP_ST64,     4'd12, 4'd8, 4'd0, 15'd0));
        // Exit path: last MAC R13@23 → same path → 29 (gap=11) ✓
        // ST64 is not a GPR write; no hazard between addr 28 and 29 ✓
        // addr 29: DMEM[R9+0] = R13  (write logit2 to DMEM[195])
        imem_write(9'd29, ENC(OP_ST64,     4'd13, 4'd9, 4'd0, 15'd0));
        // addr 30: RET
        imem_write(9'd30, ENC(OP_RET,      4'd0,  4'd0, 4'd0, 15'd0));
        // drain remaining instructions with NOP
        imem_write(9'd31, NOP);
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

        $display("\n=== TEST : ECG Classifier (64-dim -> 2-class, 4 beats SIMD) ===");

        // --------------------------------------------------
        // 1. Load DMEM: features, weights, biases
        // --------------------------------------------------
        load_classifier_dmem;

        // --------------------------------------------------
        // 2. Set kernel parameters
        //    P1=0   (base X),    P2=64  (base W1),  P3=128 (base W2)
        //    P4=64  (loop count),P5=192 (bias1 load addr)
        //    P6=193 (bias2 load addr), P7=194 (logit1 store addr)
        //    logit2 store addr (195) computed as P7+1 inside program
        // --------------------------------------------------
        param_write(3'd1, 64'd0);
        param_write(3'd2, 64'd64);
        param_write(3'd3, 64'd128);
        param_write(3'd4, 64'd64);
        param_write(3'd5, 64'd192);
        param_write(3'd6, 64'd193);
        param_write(3'd7, 64'd194);

        // --------------------------------------------------
        // 3. Load and run the classifier program
        // --------------------------------------------------
        load_ecg_program;
        reset_pc;
        run_until_done(2000);

        // --------------------------------------------------
        // 4. Check results
        //
        //    Bias slots must be unchanged:
        //      DMEM[192] = bias1 x4 = BE39_BE39_BE39_BE39
        //      DMEM[193] = bias2 x4 = 3E0E_3E0E_3E0E_3E0E
        //
        //    Logit outputs (RTL-faithful BF16 simulation of tensor16_pipe3):
        //      DMEM[194] = {logit1_beat4, logit1_beat3, logit1_beat2, logit1_beat1}
        //      DMEM[195] = {logit2_beat4, logit2_beat3, logit2_beat2, logit2_beat1}
        //        Beat1: logit1 = C0D9 (-6.7812),  logit2 = 40EA (+7.3125)
        //        Beat2: logit1 = 4066 (+3.5938),  logit2 = C05A (-3.4062)
        //        Beat3: logit1 = C0D5 (-6.6562),  logit2 = 40E7 (+7.2188)
        //        Beat4: logit1 = 4073 (+3.7969),  logit2 = C05F (-3.4844)
        //    Predicted class: argmax(logit1, logit2)
        //        Beat1: class 1 (logit2 > logit1)
        //        Beat2: class 0 (logit1 > logit2)
        //        Beat3: class 1 (logit2 > logit1)
        //        Beat4: class 0 (logit1 > logit2)
        // --------------------------------------------------
        // Verify biases are untouched
        dmem_check(8'd192, 64'hBE39BE39BE39BE39); // bias1 preserved
        dmem_check(8'd193, 64'h3E0E3E0E3E0E3E0E); // bias2 preserved
        // Verify computed logits
        dmem_check(8'd194, 64'h4073C0D54066C0D9); // logit1 all beats
        dmem_check(8'd195, 64'hC05F40E7C05A40EA); // logit2 all beats

        $display("\n=== ALL TESTS COMPLETE ===");
        $finish;
    end

    // -------------------------------------------------------
    // VCD
    // -------------------------------------------------------
    initial begin
        $dumpfile("tb_ECG.vcd");
        $dumpvars(0, tb_gpu_core3);
    end

endmodule
