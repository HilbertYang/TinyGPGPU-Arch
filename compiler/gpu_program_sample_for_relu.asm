                    RD      RS1     RS2     IMM1
---------------------------------------------
    0   LD_PARAM    R1      0       0       0      //load a
    1   LD_PARAM    R2      0       0       0      //load b
    2   LD_PARAM    R3      0       0       0      //load c/out
    3   LD_PARAM    R4      0       0       0      //load n
    4   ADDIMM      R5      R0      0       0      //reset thread_id(R5=R0(0)+0)
Loop:
    5   SETP_GE     0       R5      R4      0       //compare
    6   BRA         0       0       0       RET     //if thread_id > n end the kernel

    7   SHIFTRV     R6      R5      0       2        //TID/4
    8   ADD64       R1      R1      R6      0
    9   ADD64       R3      R3      R6      0
    a   LD64        R10     R1      0       0

    b   MAX_I16     R12     R10     R0      0

    c   ST64        R12     R3      0       0
    d   ADDIMM      R5      R5      0       4
    e   J           0       0       0       Loop
RET:
    f  RET         0       0       0       0     //DONE CALCULATION