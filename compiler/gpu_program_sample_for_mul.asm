                    RD      RS1     RS2     IMM1
---------------------------------------------
    0   LD_PARAM    R1      0       0       0      //load a
    1   LD_PARAM    R2      0       0       0      //load b
    2   LD_PARAM    R3      0       0       0      //load c/out
    3   LD_PARAM    R4      0       0       0      //load n
Loop:
    4   MOV_TID     R5      0       0       0       //get TID
    5   SETP_GE     0       R5      R4      0       //compare
    6   BRA         0       0       0       RET     //if thread_id > n end the kernel

    7   SHIFTRV     R6      R5      0       2        //TID/4
    8   ADD64       R1      R1      R6      0
    9   ADD64       R2      R2      R6      0
    a   ADD64       R3      R3      R6      0
    b   LD64        R10     R1      0       0
    c   LD64        R11     R2      0       0
    d   LD64        R12     R3      0       0

    d   MUL_BF16    R12     R10     R11     0

    e   ST64        R12     R3      0       0
    f   ADDIMM      R5      R5      0       4
RET:
    10  RET         0       0       0       0     //DONE CALCULATION