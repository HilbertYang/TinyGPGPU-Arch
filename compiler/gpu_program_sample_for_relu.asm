                    RD      RS1     RS2     IMM1
---------------------------------------------
    0   LD_PARAM    R1      0       0       0      //load a
    1   LD_PARAM    R3      0       0       0      //load c/out
    2   LD_PARAM    R4      0       0       0      //load n
    3   MOV         R5      0       0       0      //reset thread_id(R5=0)
    4   NOP
    5   NOP
Loop:
    6   SETP_GE     0       R5      R4      0       //if R5 >=n
    7   BPR         0       0       0       RET     //if >= go RET
       
    8   LD64        R10     R1      0       0      // R10 = MEM[R1]
    9   ADDI64      R1      R1      0       1      // R1 += 1;
    10  BR          0       0       0       Loop
    11  MAX_I16     R12     R10     R0      0      // Relu(R10)
    12  ADDI64      R5      R5      0       4      // R5 += 4;
    13  ST64        R12     R3      0       0      // MEM[R3] = R12(result)
    14  ADDI64      R3      R3      0       1      // R3 += 1;

RET:
    15  RET         0       0       0       0     //DONE CALCULATION