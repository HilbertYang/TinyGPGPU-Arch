                    RD      RS1     RS2     IMM1
---------------------------------------------
    0   LD_PARAM    R1      0       0       0      //load a
    1   LD_PARAM    R2      0       0       0      //load b
    2   LD_PARAM    R3      0       0       0      //load c/out
    3   LD_PARAM    R4      0       0       0      //load n
    4   MOV         R5      0       0       0      //reset thread_id(R5=0)
    5   NOP
    6   NOP
Loop:
    7   SETP_GE     0       R5      R4      0       //compare
    8   BPR         0       0       0       RET     //if thread_id > n end the kernel
        
    15  LD64        R10     R1      0       0      // R10 = MEM[R1]
    16  LD64        R11     R2      0       0      // R11 = MEM[R2]
    12  ADDI64      R1      R1      0       1      // R1 += 1;
    13  ADDI64      R2      R2      0       1      // R2 += 1;
    19  ADD_I16     R12     R10     R11     0      // R12 = R11 + R10
    f   BR          0       0       0       Loop
    e   ADDI64      R5      R5      0       4      // R5 += 4;
    d   ST64        R12     R3      0       0      // MEM[R3] = R12(result)
    14  ADDI64      R3      R3      0       1      // R3 += 1;

RET:
    10  RET         0       0       0       0     //DONE CALCULATION