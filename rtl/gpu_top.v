// gpu_top.v
// Top-level GPU System
// Connects:  I_M_32bit_512depth (instruction memory)
//            D_M_64bit_256       (data memory)
//            gpu_core
//
// Host interface:
//   - param_wr_*  : write kernel parameters before launch
//   - imem_prog_* : program instruction memory before launch
//   - start       : begin kernel execution
//   - done        : kernel finished

`timescale 1ns/1ps

module gpu_top(
    input  wire        clk,
    input  wire        rst_n,

    // Host: kernel launch
    input  wire        start,
    output wire        done,

    // Host: parameter loading
    input  wire        param_wr_en,
    input  wire [2:0]  param_wr_addr,
    input  wire [63:0] param_wr_data,

    // Host: instruction memory programming
    input  wire        imem_prog_en,
    input  wire [8:0]  imem_prog_addr,
    input  wire [31:0] imem_prog_din,
    output  wire [31:0] imem_prog_dout,


    // Host: data memory access (NOW uses Port A)
    input  wire        dmem_host_en,
    input  wire        dmem_host_we,
    input  wire [7:0]  dmem_host_addr,
    input  wire [63:0] dmem_host_din,
    output wire [63:0] dmem_host_dout,

    // External / programming interface (Port B RESERVED)
    input  wire        dmem_prog_en,
    input  wire        dmem_prog_we,
    input  wire [7:0]  dmem_prog_addr,
    input  wire [63:0] dmem_prog_din,
    output wire [63:0] dmem_prog_dout
);

    //=========================================================
    // Instruction Memory Signals
    //=========================================================
    wire [8:0]  imem_addr_gpu;
    wire        imem_en_gpu;
    wire        imem_we_gpu;
    wire [31:0] imem_din_gpu;
    wire [31:0] imem_dout;
    wire [31:0] imem_dout_gpu;

    // Mux: External programming selector
    wire [8:0]  imem_addr_mux = imem_prog_en ? imem_prog_addr  : imem_addr_gpu;
    wire        imem_en_mux   = imem_prog_en ? 1'b1            : imem_en_gpu;
    wire        imem_we_mux   = imem_prog_en ? 1'b1            : imem_we_gpu;
    wire [31:0] imem_din_mux  = imem_prog_en ? imem_prog_din   : imem_din_gpu;

    // synchronous：douta use last address
    reg imem_prog_en_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_prog_en_d <= 1'b0;
        end else begin 
            imem_prog_en_d <= imem_prog_en & imem_en_mux;
        end
    end

    // Host Read 
    assign imem_prog_dout = imem_prog_en_d ? imem_dout : 32'd0;
    // GPU Read 
    assign imem_dout_gpu  = (!imem_prog_en_d) ? imem_dout : 32'd0;

    I_M_32bit_512depth IMEM(
        .addr  (imem_addr_mux),
        .clk   (clk),
        .din   (imem_din_mux),
        .dout  (imem_dout),
        .en    (imem_en_mux),
        .we    (imem_we_mux)
    );

    //=========================================================
    // Data Memory Signals
    //=========================================================
    wire [7:0]  dmem_addr_gpu;
    wire [63:0] dmem_din_gpu;
    wire        dmem_we_gpu;
    wire        dmem_en_gpu;
    wire [63:0] dmem_dout_a;
    wire [63:0] dmem_dout_gpu;   // GPU data

    // Port A: GPU & Host readback/write
    // Port B: External programming interface
    wire [7:0]  dmem_addr_a = dmem_host_en ? dmem_host_addr : dmem_addr_gpu;
    wire [63:0] dmem_din_a  = dmem_host_en ? dmem_host_din  : dmem_din_gpu;
    wire        dmem_we_a   = dmem_host_en ? dmem_host_we   : dmem_we_gpu;
    wire        dmem_en_a   = dmem_host_en ? 1'b1           : dmem_en_gpu;

    // synchronous：douta use last address
    reg dmem_host_en_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_host_en_d <= 1'b0;
        end else begin 
            dmem_host_en_d <= dmem_host_en & dmem_en_a;
        end
    end

    // Host Read from port A
    assign dmem_host_dout = dmem_host_en_d ? dmem_dout_a : 64'd0;

    // GPU Read from port A (When the last clock is not using by HOST)
    assign dmem_dout_gpu  = (!dmem_host_en_d) ? dmem_dout_a : 64'd0;

    D_M_64bit_256 DMEM(
        // Port A: shared by Host/GPU
        .clka  (clk),
        .ena   (dmem_en_a),
        .wea   (dmem_we_a),
        .addra (dmem_addr_a),
        .dina  (dmem_din_a),
        .douta (dmem_dout_a),

        // Port B: external/programming interface
        .clkb  (clk),
        .enb   (dmem_prog_en),
        .web   (dmem_prog_we),
        .addrb (dmem_prog_addr),
        .dinb  (dmem_prog_din),
        .doutb (dmem_prog_dout)
    );

    //=========================================================
    // GPU Core
    //=========================================================
    gpu_core CORE(
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .done           (done),

        .param_wr_en    (param_wr_en),
        .param_wr_addr  (param_wr_addr),
        .param_wr_data  (param_wr_data),

        .dmem_addr_a    (dmem_addr_gpu),
        .dmem_din_a     (dmem_din_gpu),
        .dmem_we_a      (dmem_we_gpu),
        .dmem_en_a      (dmem_en_gpu),
        .dmem_dout_a    (dmem_dout_gpu),

        .imem_addr      (imem_addr_gpu),
        .imem_en        (imem_en_gpu),
        .imem_dout      (imem_dout_gpu)
    );

endmodule
