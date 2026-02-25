// pe_bf16.v
// Single PE supporting:
//   MUL: Y = A*B + 0
//   MAC: Y = C + (A*B + 0)
// Simplified BF16 arithmetic: supports normalized numbers + +/-0.0.
// Omits full IEEE corner cases (NaN/Inf/denorm). Good for class projects.

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
  assign is_zero = (x[14:0] == 15'b0); // +/-0
endmodule

// -----------------------------
// BF16 MUL (normalized + zero)
// y = a*b
// -----------------------------
module bf16_mul(
  input  wire [15:0] a,
  input  wire [15:0] b,
  output reg  [15:0] y
);
  wire sa,sb,za,zb;
  wire [7:0] ea,eb;
  wire [6:0] fa,fb;

  bf16_unpack UA(a, sa, ea, fa, za);
  bf16_unpack UB(b, sb, eb, fb, zb);

  wire s = sa ^ sb;

  // treat exponent==0 as zero (simplified) to avoid denorm complexity
  wire norm_a = (!za) && (ea != 8'd0);
  wire norm_b = (!zb) && (eb != 8'd0);

  wire [7:0] ma = norm_a ? {1'b1, fa} : 8'd0; // 1.f in Q1.7 (scaled by 128)
  wire [7:0] mb = norm_b ? {1'b1, fb} : 8'd0;

  wire [15:0] prod = ma * mb; // Q2.14 (scaled by 16384), range ~ [1.0,4.0)

  integer e_tmp;
  reg [15:0] m_norm;
  reg [6:0]  frac;
  reg [7:0]  exp_out;
  reg guard, sticky, lsb;

  always @(*) begin
    if (ma == 0 || mb == 0) begin
      y = {s, 8'd0, 7'd0}; // +/-0
    end else begin
      e_tmp  = (ea + eb) - 8'd127;
      m_norm = prod;

      // normalize: if >=2.0 shift right 1, exp++
      if (m_norm >= 16'd32768) begin
        m_norm = m_norm >> 1;
        e_tmp  = e_tmp + 1;
      end

      // extract fraction bits from Q2.14:
      // hidden 1 at bit14, fraction bits are [13:7]
      frac   = m_norm[13:7];
      guard  = m_norm[6];
      sticky = |m_norm[5:0];
      lsb    = frac[0];

      // RNE rounding
      if (guard && (sticky || lsb)) begin
        {exp_out, frac} = {e_tmp[7:0], frac} + 1'b1;
      end else begin
        exp_out = e_tmp[7:0];
      end

      // clamp exponent (simplified)
      if (e_tmp <= 0) begin
        y = {s, 8'd0, 7'd0}; // underflow -> 0
      end else if (e_tmp >= 255) begin
        y = {s, 8'hFF, 7'd0}; // overflow -> inf (simplified)
      end else begin
        y = {s, exp_out, frac};
      end
    end
  end
endmodule

// -----------------------------
// BF16 ADD (normalized + zero)
// y = a + b
// Simplified: normalized + zero; ignores denorm/NaN/Inf correctness.
// -----------------------------
module bf16_add(
  input  wire [15:0] a,
  input  wire [15:0] b,
  output reg  [15:0] y
);
  wire sa,sb,za,zb;
  wire [7:0] ea,eb;
  wire [6:0] fa,fb;
  bf16_unpack UA(a, sa, ea, fa, za);
  bf16_unpack UB(b, sb, eb, fb, zb);

  integer i;

  always @(*) begin
    if (za) begin
      y = b;
    end else if (zb) begin
      y = a;
    end else begin
      // treat exponent==0 as zero (simplified)
      if (ea == 0) begin
        y = b;
      end else if (eb == 0) begin
        y = a;
      end else begin
        // mantissas: 1.f in Q1.7, then extend and add 3 extra bits for G/R/S
        reg [7:0] ma_u, mb_u;
        reg signed [12:0] ma_s, mb_s;
        reg [7:0] e_big, e_small;
        reg signed [12:0] m_big, m_small;
        reg [4:0] shift;
        reg dropped;

        reg signed [13:0] sum;
        reg [13:0] mag;
        reg s_out;
        reg [7:0] e_tmp;
        reg [13:0] norm;

        reg [6:0] frac;
        reg guard, sticky, lsb;
        reg [7:0] exp_out;

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
        if (shift > 5'd12) shift = 5'd12; // cap (simplified)

        dropped = 1'b0;
        for (i=0; i<shift; i=i+1) begin
          dropped = dropped | m_small[0];
          m_small = m_small >>> 1;
        end
        if (dropped) m_small[0] = 1'b1; // sticky

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

          // normalize to make leading 1 land at bit (7+3)=10
          // if too large
          while (norm[13:11] != 0) begin
            norm = norm >> 1;
            e_tmp = e_tmp + 1;
          end
          // if too small
          while (norm[10] == 0) begin
            norm = norm << 1;
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
  end
endmodule

// -----------------------------
// PE: MUL or MAC
// op=0: Y = A*B
// op=1: Y = C + A*B
// 1-cycle latency (registered output).
// -----------------------------
module pe_bf16 (
  input  wire        clk,
  input  wire        rst,

  input  wire        valid_in,
  input  wire        op_mac,      // 0=MUL, 1=MAC

  input  wire [15:0] A,
  input  wire [15:0] B,
  input  wire [15:0] C,

  output reg         valid_out,
  output reg  [15:0] Y
);
  wire [15:0] prod;
  wire [15:0] sum;

  bf16_mul UM(.a(A), .b(B), .y(prod));
  bf16_add UA(.a(C), .b(prod), .y(sum));

  always @(posedge clk) begin
    if (rst) begin
      valid_out <= 1'b0;
      Y         <= 16'd0;
    end else begin
      valid_out <= valid_in;
      if (valid_in) begin
        Y <= op_mac ? sum : prod; // MUL: A*B, MAC: C + A*B
      end
    end
  end
endmodule