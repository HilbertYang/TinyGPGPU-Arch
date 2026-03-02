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

  // -------- module-scope regs (Verilog-2001 safe) --------
  reg [7:0]          ma_u, mb_u;
  reg signed [12:0]  ma_s, mb_s;
  reg [7:0]          e_big, e_small;
  reg signed [12:0]  m_big, m_small;

  reg [4:0]          shift;      // 0..12
  reg                dropped;

  reg signed [13:0]  sum;
  reg [13:0]         mag;
  reg                s_out;

  reg [7:0]          e_tmp;
  reg [13:0]         norm;

  reg [6:0]          frac;
  reg                guard, sticky, lsb;
  reg [7:0]          exp_out;

  // -------------------------------------------------------
  // NOTE:
  // - no while loops
  // - for loops are fixed bound (static): 13, 14, 14
  // -------------------------------------------------------
  always @(*) begin
    // defaults
    y       = 16'd0;

    // handle zeros / denorms as zero (simple GPU-style behavior)
    if (za) begin
      y = b;
    end else if (zb) begin
      y = a;
    end else if (ea == 8'd0) begin
      y = b;
    end else if (eb == 8'd0) begin
      y = a;
    end else begin
      // unpack mantissas (implicit 1)
      ma_u = {1'b1, fa}; // 8-bit
      mb_u = {1'b1, fb};

      // signed mantissas (extend to 13 bits)
      ma_s = sa ? -$signed({5'b0, ma_u}) :  $signed({5'b0, ma_u});
      mb_s = sb ? -$signed({5'b0, mb_u}) :  $signed({5'b0, mb_u});

      // choose bigger exponent as reference
      if (ea >= eb) begin
        e_big   = ea;  e_small = eb;
        m_big   = ma_s <<< 3;   // keep 3 extra bits for rounding
        m_small = mb_s <<< 3;
      end else begin
        e_big   = eb;  e_small = ea;
        m_big   = mb_s <<< 3;
        m_small = ma_s <<< 3;
      end

      // exponent difference clamp to 12 (static align limit)
      shift = e_big - e_small;
      if (shift > 5'd12) shift = 5'd12;

      // align smaller mantissa right by 'shift' with sticky collection
      dropped = 1'b0;
      for (i = 0; i < 13; i = i + 1) begin : ALIGN_SHIFT
        if (i < shift) begin
          dropped = dropped | m_small[0];
          m_small = m_small >>> 1;
        end
      end
      if (dropped) m_small[0] = 1'b1; // sticky into LSB

      // add
      sum = $signed(m_big) + $signed(m_small);

      // sign/magnitude
      if (sum < 0) begin
        s_out = 1'b1;
        mag   = -sum;
      end else begin
        s_out = 1'b0;
        mag   = sum;
      end

      if (mag == 14'd0) begin
        y = {1'b0, 8'd0, 7'd0};
      end else begin
        e_tmp = e_big;
        norm  = mag;

        // -------- normalize RIGHT: ensure norm[13:11]==0 (fit range) --------
        // fixed 14 iterations, XST can unroll
        for (i = 0; i < 14; i = i + 1) begin : NORM_RIGHT
          if (norm[13:11] != 3'b000) begin
            norm  = norm >> 1;
            e_tmp = e_tmp + 1'b1;
          end
        end

        // -------- normalize LEFT: ensure leading 1 at bit[10] --------
        for (i = 0; i < 14; i = i + 1) begin : NORM_LEFT
          if (norm[10] == 1'b0) begin
            norm  = norm << 1;
            e_tmp = e_tmp - 1'b1;
          end
        end

        // extract frac + rounding bits (norm has guard/sticky space)
        frac   = norm[9:3];
        guard  = norm[2];
        sticky = |norm[1:0];
        lsb    = frac[0];

        // round-to-nearest-even
        exp_out = e_tmp;
        if (guard && (sticky || lsb)) begin
          {exp_out, frac} = {e_tmp, frac} + 1'b1;

          // if rounding overflowed frac (carry), renormalize once
          // (carry out into exp_out already happened, but leading 1 might shift)
          // Here, frac is only 7 bits; carry means implicit 1 moved.
          // Simple fix: if frac wrapped to 0, bump exponent already done; keep frac=0 ok.
        end

        // exponent clamp (very simple saturation)
        if ($signed({1'b0,e_tmp}) <= 9'sd0) begin
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