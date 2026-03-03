////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995-2008 Xilinx, Inc.  All rights reserved.
////////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor: Xilinx
// \   \   \/     Version: K.31
//  \   \         Application: netgen
//  /   /         Filename: mul.v
// /___/   /\     Timestamp: Tue Mar 03 10:20:18 2026
// \   \  /  \ 
//  \___\/\___\
//             
// Command	: -intstyle ise -w -sim -ofmt verilog C:\moduleTest\lab7test6\test6\tmp\_cg\mul.ngc C:\moduleTest\lab7test6\test6\tmp\_cg\mul.v 
// Device	: 2vp30ff896-6
// Input file	: C:/moduleTest/lab7test6/test6/tmp/_cg/mul.ngc
// Output file	: C:/moduleTest/lab7test6/test6/tmp/_cg/mul.v
// # of Modules	: 1
// Design Name	: mul
// Xilinx        : C:\Xilinx\10.1\ISE
//             
// Purpose:    
//     This verilog netlist is a verification model and uses simulation 
//     primitives which may not represent the true implementation of the 
//     device, however the netlist is functionally correct and should not 
//     be modified. This file cannot be synthesized and should only be used 
//     with supported simulation tools.
//             
// Reference:  
//     Development System Reference Guide, Chapter 23 and Synthesis and Simulation Design Guide, Chapter 6
//             
////////////////////////////////////////////////////////////////////////////////

`timescale 1 ns/1 ps

module mul (
a, b, p
);
  input [7 : 0] a;
  input [7 : 0] b;
  output [15 : 0] p;
  
  // synthesis translate_off
  
  wire \BU2/clk ;
  wire NLW_VCC_P_UNCONNECTED;
  wire NLW_GND_G_UNCONNECTED;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<35>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<34>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<33>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<32>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<31>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<30>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<29>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<28>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<27>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<26>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<25>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<24>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<23>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<22>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<21>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<20>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<19>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<18>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<17>_UNCONNECTED ;
  wire \NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<16>_UNCONNECTED ;
  wire [7 : 0] a_2;
  wire [7 : 0] b_3;
  wire [15 : 0] \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> ;
  wire [0 : 0] \BU2/zero_detect ;
  assign
    a_2[7] = a[7],
    a_2[6] = a[6],
    a_2[5] = a[5],
    a_2[4] = a[4],
    a_2[3] = a[3],
    a_2[2] = a[2],
    a_2[1] = a[1],
    a_2[0] = a[0],
    b_3[7] = b[7],
    b_3[6] = b[6],
    b_3[5] = b[5],
    b_3[4] = b[4],
    b_3[3] = b[3],
    b_3[2] = b[2],
    b_3[1] = b[1],
    b_3[0] = b[0],
    p[15] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [15],
    p[14] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [14],
    p[13] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [13],
    p[12] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [12],
    p[11] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [11],
    p[10] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [10],
    p[9] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [9],
    p[8] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [8],
    p[7] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [7],
    p[6] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [6],
    p[5] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [5],
    p[4] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [4],
    p[3] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [3],
    p[2] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [2],
    p[1] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [1],
    p[0] = \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [0];
  VCC   VCC_0 (
    .P(NLW_VCC_P_UNCONNECTED)
  );
  GND   GND_1 (
    .G(NLW_GND_G_UNCONNECTED)
  );
  MULT18X18   \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18  (
    .A({\BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], 
\BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], a_2[7], a_2[6], a_2[5], a_2[4], a_2[3], a_2[2], a_2[1], a_2[0]
}),
    .B({\BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], 
\BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], \BU2/zero_detect [0], b_3[7], b_3[6], b_3[5], b_3[4], b_3[3], b_3[2], b_3[1], b_3[0]
}),
    .P({\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<35>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<34>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<33>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<32>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<31>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<30>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<29>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<28>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<27>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<26>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<25>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<24>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<23>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<22>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<21>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<20>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<19>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<18>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<17>_UNCONNECTED , 
\NLW_BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/use_mult18x18.appMULT[0].bppMULT[0].no_Mreg.m18x18_P<16>_UNCONNECTED , 
\BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [15], \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [14], 
\BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [13], \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [12], 
\BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [11], \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [10], 
\BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [9], \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [8], 
\BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [7], \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [6], 
\BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [5], \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [4], 
\BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [3], \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [2], 
\BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [1], \BU2/U0/gEMBEDDED_MULT.gEMB_MULTS_only.gMULT18.iMULT18/pi_Mreg<0><0> [0]})
  );
  GND   \BU2/XST_GND  (
    .G(\BU2/zero_detect [0])
  );

// synthesis translate_on

endmodule

// synthesis translate_off

`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;

    wire GSR;
    wire GTS;
    wire PRLD;

    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (weak1, weak0) GSR = GSR_int;
    assign (weak1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

endmodule

// synthesis translate_on
