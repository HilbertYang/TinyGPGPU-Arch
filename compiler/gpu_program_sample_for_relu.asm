                    RD      RS1     RS2     IMM1
---------------------------------------------
    0   LD_PARAM    R1      0       0       0      //load a
    1   LD_PARAM    R3      0       0       0      //load c/out
    2   LD_PARAM    R4      0       0       0      //load n
Loop:
    3   MOV_TID     R5      0       0       0       //get TID
    4   SETP_GE     0       R5      R4      0       //compare
    5   BRA         0       0       0       RET     //if thread_id > n end the kernel

    6   SHIFTL      R6      R5      0       2        //TID/4
    7   ADD64       R1      R1      R6      0
    8   ADD64       R3      R3      R6      0          
    9   LD64        R10     R1      0       0
    a   MAX_I16     R12     R10     R0      0        //compare with 0 which one is bigger
    b   ST64        R12     R3      0       0
    c   ADDIMM      R5      R5      0       4
RET:
    d   RET         0       0       0       0     //DONE CALCULATION