
`timescale 1ns / 1ps

module tensor16_pipe1 (
       input [15:0]           fb16_A,
       input [15:0]           fb16_B,
       input [15:0]           fb16_C,
       input                  op_mac,     // 1: mac, 0: mul
		 input clk,
		 input reset,
		 input pc_reset,
		 input advance,

       output [15:0]          result
);
       

   
//modules
// multip mantissa_16 (.a(mantissa_1[7:0]),    //input_1
//               .b(mantissa_2[7:0]),          //input_2
//               .p(OUTPUT_mantissa[15:0]));   //output contains all precision for potential modification



// mul logic
wire  sign_A = fb16_A[15];
wire  sign_B = fb16_B[15];
wire  [7:0] exponent_A = fb16_A[14:7];
wire  [7:0] exponent_B = fb16_B[14:7];
wire  [6:0] mantissa_A = fb16_A[6:0];
wire  [6:0] mantissa_B = fb16_B[6:0];
//intermid calculation
wire  [15:7] mantissa_mul_CAL;
wire  [7:0] bias;    //exponent bias for single precision is 127
wire  carry_mul;         //carry over 
wire [7:0] mantissa_A_CAL;
wire [7:0] mantissa_B_CAL;

assign bias = 8'b01111111; //127 in decimal
assign carry_mul  = mantissa_mul_CAL[15]; //check for carry from multiplication
//output
wire  [6:0]  mantissa_mul_output;
wire  [7:0]  exponent_mul_output;
wire  sign_mul_output;
wire  [15:0] mul_result = {sign_mul_output, exponent_mul_output, mantissa_mul_output};

//mul mantissa_16 (.a(mantissa_A_CAL), 
multest2 mantissa_16 (.a(mantissa_A_CAL), 
              .b(mantissa_B_CAL), 
              .p(mantissa_mul_CAL[15:7]));   //output contains all precision for potential modification



assign sign_mul_output = sign_A ^ sign_B; // XOR for sign of the result
assign exponent_mul_output = exponent_A + exponent_B - bias + carry_mul; // Add exponents and subtract bias
assign mantissa_A_CAL = {1'b1, mantissa_A}; // add implicit leading 1
assign mantissa_B_CAL = {1'b1, mantissa_B}; // add implicit leading 1

assign mantissa_mul_output = carry_mul ? mantissa_mul_CAL[14:8] : mantissa_mul_CAL[13:7]; // Normalize the result based on carry

reg [6:0]  mantissa_mul_output_stage2;
reg [7:0]  exponent_mul_output_stage2;
reg [15:0] fb16_C_stage2 ;
reg sign_mul_output_stage2;
reg op_mac_stage2;

	always @(posedge clk) begin
        if (reset || pc_reset) begin
            mantissa_mul_output_stage2 <= 8'd0;
				exponent_mul_output_stage2 <= 7'b0;
				sign_mul_output_stage2 <= 1'b0;
				fb16_C_stage2 <= 8'b0;
				op_mac_stage2 <= 1'b0;
        end else if (advance) begin
            mantissa_mul_output_stage2 <= mantissa_mul_output;
				exponent_mul_output_stage2 <= exponent_mul_output;
				fb16_C_stage2 <= fb16_C;
				sign_mul_output_stage2 <= sign_mul_output;
				op_mac_stage2 <= op_mac;
        end
    end

//mac logic  num_1 = A*B, num_2 = C
wire sign_C = fb16_C_stage2[15];
wire [7:0] exponent_C = fb16_C_stage2[14:7];
wire [6:0] mantissa_C = fb16_C_stage2[6:0];
//intermid calculation
wire [7:0] mantissa_mac_cal1 = {1'b1, mantissa_mul_output_stage2}; // add
wire [7:0] mantissa_mac_cal2 = {1'b1, mantissa_C}; // add implicit leading 1 for C

wire sign_mac_cal = sign_mul_output_stage2 ^ sign_C; // XOR for sign of the result
wire exp_cmp = exponent_C > exponent_mul_output_stage2; // Compare exponents to determine which is larger
wire exp_equal = exponent_C == exponent_mul_output_stage2; // Check if exponents are equal
wire man_cmp = mantissa_mac_cal2 > mantissa_mac_cal1; // Compare mantissas to determine which is larger when exponents are equal
wire shift_signal =  exp_equal ? man_cmp : exp_cmp ; // Sign of the exponent difference
wire [8:0] shift_mac_exponent = shift_signal ? (exponent_C - exponent_mul_output_stage2) : (exponent_mul_output_stage2 - exponent_C); // Absolute value of exponent difference

wire [8:0] mantissa_mac_cal;
wire carry_mac = mantissa_mac_cal[8]; // Check for carry from addition/subtraction
wire [8:0] low_mac_mantissa;
wire [8:0] high_mac_mantissa;
//reg [7:0]shiftback_mac;
wire [7:0]shiftback_mac;
reg  [8:0] mantissa_mac_subcheck;
wire [7:0] exponent_shift_offset = (shiftback_mac == 8) ? exponent_C : shiftback_mac; // Determine the exponent offset for normalization based on shiftback value

wire sign_mac_output;
wire [7:0] exponent_mac_output;
reg [6:0] mantissa_mac_output;
wire [15:0] mac_result = {sign_mac_output, exponent_mac_output, mantissa_mac_output};

assign sign_mac_output = sign_mac_cal ? ( shift_signal ? sign_C : sign_mul_output_stage2) : sign_C ; 
assign low_mac_mantissa = shift_signal ? (mantissa_mac_cal1 >> shift_mac_exponent) : (mantissa_mac_cal2 >> shift_mac_exponent); // shift the small exponent
assign high_mac_mantissa = shift_signal ? mantissa_mac_cal2 : mantissa_mac_cal1; // keep the marge mantissa
assign mantissa_mac_cal = sign_mac_cal ? (high_mac_mantissa - low_mac_mantissa) : (high_mac_mantissa + low_mac_mantissa); // Add or subtract mantissas based on signs

assign exponent_mac_output = (shift_signal ? exponent_C : exponent_mul_output_stage2) + carry_mac - exponent_shift_offset; // Use the larger exponent


assign shiftback_mac =
        (mantissa_mac_cal[8]) ? 8'd0 :
        (mantissa_mac_cal[7]) ? 8'd0 :
        (mantissa_mac_cal[6]) ? 8'd1 :
        (mantissa_mac_cal[5]) ? 8'd2 :
        (mantissa_mac_cal[4]) ? 8'd3 :
        (mantissa_mac_cal[3]) ? 8'd4 :
        (mantissa_mac_cal[2]) ? 8'd5 :
        (mantissa_mac_cal[1]) ? 8'd6 :
        (mantissa_mac_cal[0]) ? 8'd7 :
                                8'd8;   // default
										  
// integer i;
always @(*) begin
	/*
       shiftback_mac = 8'd8; // Default value for shiftback
       for (i = 0; i <= 8; i = i + 1) begin
              if (mantissa_mac_cal[i]) begin
                     if (i == 8 ) 
                            shiftback_mac = 8'd0;
                     else   shiftback_mac = 7 - i; // Calculate shiftback based on the position of the first '1'
              end
       end
		*/ 
		 

       if (carry_mac) begin
              mantissa_mac_subcheck = mantissa_mac_cal >> 1;
       end
       else begin
              mantissa_mac_subcheck = mantissa_mac_cal << shiftback_mac; // Shift left to normalize if there's no carry
       end

       mantissa_mac_output = mantissa_mac_subcheck[6:0]; // Take the top 7 bits for the output mantissa

end

assign result = op_mac_stage2 ? mac_result : mul_result; // Select between MAC and MUL results based on control signal



endmodule











