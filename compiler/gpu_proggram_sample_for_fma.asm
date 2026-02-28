                    RD      RS1     RS2     IMM1
---------------------------------------------
    0   LD_PARAM    R1      0       0       0      //load a
    1   LD_PARAM    R2      0       0       0      //load b
    2   LD_PARAM    R3      0       0       0      //load c/out
    3   LD_PARAM    R4      0       0       0      //load n
    4   MOV         R5      0       0       0      //reset thread_id(R5=0)
Loop:
    
    5   SETP_GE     0       R5      R4      0       //compare
    6   BPR         0       0       0       RET     //if thread_id > n end the kernel

    7   ADDI64      R1      R1      0       1
    8   ADDI64      R2      R2      0       1
    9   ADDI64      R3      R3      0       1
    a   LD64        R10     R1      0       0
    b   LD64        R11     R2      0       0
    c   LD64        R12     R3      0       0

    d   MAC_BF16    R12     R10     R11     0

    e   ST64        R12     R3      0       0
    f   ADDI64      R5      R5      0       4
    10  BR          0       0       0       Loop
RET:
    11  RET         0       0       0       0     //DONE CALCULATION