// pe_bf16_comb.v
// Combinational PE:
//   op_mac=0: Y = A*B
//   op_mac=1: Y = C + A*B
//
// Fix: all reg declarations moved to module scope (Verilog-2001 compatible,
//      no declarations inside unnamed always blocks).

module bf16_unpack(
  input  wire [15:0] x,
  output wire        s,
  output wire [7:0]  e,
  output wire [6:0]  f,
  output wire        is_zero
);
  assign s = x[15];
  assign e = x[14:7];
  assign f = x[6:0];
  assign is_zero = (x[14:0] == 15'b0);
endmodule

module bf16_mul(
  input  wire [15:0] a,
  input  wire [15:0] b,
  output reg  [15:0] y
);
  wire sa, sb, za, zb;
  wire [7:0] ea, eb;
  wire [6:0] fa, fb;

  bf16_unpack UA(a, sa, ea, fa, za);
  bf16_unpack UB(b, sb, eb, fb, zb);

  wire s = sa ^ sb;

  wire norm_a = (!za) && (ea != 8'd0);
  wire norm_b = (!zb) && (eb != 8'd0);

  wire [7:0] ma = norm_a ? {1'b1, fa} : 8'd0;
  wire [7:0] mb = norm_b ? {1'b1, fb} : 8'd0;

  wire [15:0] prod = ma * mb;

  // Module-level regs (Verilog-2001: no decls inside always blocks)
  integer    e_tmp;
  reg [15:0] m_norm;
  reg [6:0]  frac;
  reg [7:0]  exp_out;
  reg        guard, sticky, lsb;

  always @(*) begin
    if (ma == 0 || mb == 0) begin
      y = {s, 8'd0, 7'd0};
    end else begin
      e_tmp  = (ea + eb) - 8'd127;
      m_norm = prod;

      if (m_norm >= 16'd32768) begin
        m_norm = m_norm >> 1;
        e_tmp  = e_tmp + 1;
      end

      frac   = m_norm[13:7];
      guard  = m_norm[6];
      sticky = |m_norm[5:0];
      lsb    = frac[0];

      if (guard && (sticky || lsb)) begin
        {exp_out, frac} = {e_tmp[7:0], frac} + 1'b1;
      end else begin
        exp_out = e_tmp[7:0];
      end

      if (e_tmp <= 0) begin
        y = {s, 8'd0, 7'd0};
      end else if (e_tmp >= 255) begin
        y = {s, 8'hFF, 7'd0};
      end else begin
        y = {s, exp_out, frac};
      end
    end
  end
endmodule

module bf16_add(
  input  wire [15:0] a,
  input  wire [15:0] b,
  output reg  [15:0] y
);
  wire sa, sb, za, zb;
  wire [7:0] ea, eb;
  wire [6:0] fa, fb;

  bf16_unpack UA(a, sa, ea, fa, za);
  bf16_unpack UB(b, sb, eb, fb, zb);

  integer i;

  // All reg declarations at module scope (Verilog-2001 compatible)
  reg [7:0]          ma_u, mb_u;
  reg signed [12:0]  ma_s, mb_s;
  reg [7:0]          e_big, e_small;
  reg signed [12:0]  m_big, m_small;
  reg [4:0]          shift;
  reg                dropped;
  reg signed [13:0]  sum;
  reg [13:0]         mag;
  reg                s_out;
  reg [7:0]          e_tmp;
  reg [13:0]         norm;
  reg [6:0]          frac;
  reg                guard, sticky, lsb;
  reg [7:0]          exp_out;

  always @(*) begin
    if (za) begin
      y = b;
    end else if (zb) begin
      y = a;
    end else if (ea == 0) begin
      y = b;
    end else if (eb == 0) begin
      y = a;
    end else begin
      ma_u = {1'b1, fa};
      mb_u = {1'b1, fb};

      ma_s = sa ? -$signed({5'b0, ma_u}) : $signed({5'b0, ma_u});
      mb_s = sb ? -$signed({5'b0, mb_u}) : $signed({5'b0, mb_u});

      if (ea >= eb) begin
        e_big   = ea; e_small = eb;
        m_big   = ma_s <<< 3;
        m_small = mb_s <<< 3;
      end else begin
        e_big   = eb; e_small = ea;
        m_big   = mb_s <<< 3;
        m_small = ma_s <<< 3;
      end

      shift = e_big - e_small;
      if (shift > 5'd12) shift = 5'd12;

      dropped = 1'b0;
      for (i = 0; i < shift; i = i + 1) begin
        dropped = dropped | m_small[0];
        m_small = m_small >>> 1;
      end
      if (dropped) m_small[0] = 1'b1;

      sum = $signed(m_big) + $signed(m_small);

      if (sum < 0) begin
        s_out = 1'b1;
        mag   = -sum;
      end else begin
        s_out = 1'b0;
        mag   = sum;
      end

      if (mag == 0) begin
        y = {1'b0, 8'd0, 7'd0};
      end else begin
        e_tmp = e_big;
        norm  = mag;

        // normalize: place leading 1 at bit 10
        while (norm[13:11] != 0) begin
          norm  = norm >> 1;
          e_tmp = e_tmp + 1;
        end
        while (norm[10] == 0) begin
          norm  = norm << 1;
          e_tmp = e_tmp - 1;
        end

        frac   = norm[9:3];
        guard  = norm[2];
        sticky = |norm[1:0];
        lsb    = frac[0];

        if (guard && (sticky || lsb)) begin
          {exp_out, frac} = {e_tmp, frac} + 1'b1;
        end else begin
          exp_out = e_tmp;
        end

        if (e_tmp <= 0) begin
          y = {1'b0, 8'd0, 7'd0};
        end else if (e_tmp >= 8'hFF) begin
          y = {s_out, 8'hFF, 7'd0};
        end else begin
          y = {s_out, exp_out, frac};
        end
      end
    end
  end
endmodule

module pe_bf16_comb(
  input  wire        op_mac,    // 0=MUL, 1=MAC
  input  wire [15:0] A,
  input  wire [15:0] B,
  input  wire [15:0] C,
  output wire [15:0] Y
);
  wire [15:0] prod;
  wire [15:0] sum;

  bf16_mul UM(.a(A), .b(B), .y(prod));
  bf16_add UA(.a(C), .b(prod), .y(sum));

  assign Y = op_mac ? sum : prod;
endmodule