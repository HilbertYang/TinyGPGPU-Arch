# Custom GPU ISA - 32-bit Instruction Encoding

## Instruction Format (32-bit)
| [31:27] | [26:23] | [22:19] | [18:15] | [14:0]  |
|---------|---------|---------|---------|---------|
| OPCODE  | RD      | RS1     | RS2     | IMM15   |

> RD also serves as RS3 (accumulator) for MAC_BF16.

## Opcodes (5-bit)
| Code  | Hex  | Mnemonic  | Operation                                             |
|-------|------|-----------|-------------------------------------------------------|
| 00000 | 0x00 | NOP       | No operation                                          |
| 00001 | 0x01 | ADD_I16   | RD[4×i16] = RS1[4×i16] + RS2[4×i16]                   |
| 00010 | 0x02 | SUB_I16   | RD[4×i16] = RS1[4×i16] - RS2[4×i16]                   |
| 00011 | 0x03 | MAX_I16   | RD[4×i16] = max(RS1[4×i16], RS2[4×i16])               |
| 00100 | 0x04 | ADD64     | RD = RS1 + RS2 (64-bit)                               |
| 00101 | 0x05 | ADDI64    | RD = RS1 + sign_ext(imm15)                            |
| 00110 | 0x06 | SETP_GE   | PRED = (RS1[31:0] >= RS2[31:0])                       |
| 00111 | 0x07 | SHIFTLV   | RD = RS1 <<< imm15                                    |
| 01000 | 0x08 | SHIFTRV   | RD = RS1 >>> imm15                                    |
| 01001 | 0x09 | MAC_BF16  | RD[4×bf16] = RS1[4×bf16] * RS2[4×bf16] + RD[4×bf16]   |
| 01010 | 0x0A | MUL_BF16  | RD[4×bf16] = RS1[4×bf16] * RS2[4×bf16]                |
| 10000 | 0x10 | LD64      | RD = DMEM[RS1 + imm15]                                |
| 10001 | 0x11 | ST64      | DMEM[RS1 + imm15] = RD                                |
| 10010 | 0x12 | MOV       | RD = sign_ext(imm15)                                  |
| 10011 | 0x13 | BPR       | if PRED: PC = imm15[8:0]  (absolute)                  |
| 10100 | 0x14 | BR        | PC = imm15[8:0]  (unconditional, absolute)            |
| 10101 | 0x15 | RET       | halt / end of kernel                                  |
| 10110 | 0x16 | LD_PARAM  | RD = PARAM[imm3]                                      |

## Register File
- R0-R15: 64-bit general purpose (R0 = zero reg)
- 3 read ports: RS1, RS2, RS3(=RD) — RS3 used as accumulator for MAC_BF16
- Special: PRED (1-bit predicate register, written by SETP_GE)
- Special: PC (9-bit program counter, word-addressed, 512-entry I-MEM)

## Parameter Registers
- PARAM[0..7]: 64-bit, 8 entries (3-bit imm3 address)
- Written externally via `param_wr_en / param_wr_addr / param_wr_data`
- Read by LD_PARAM during ID stage

## Memory
- I-MEM: 512 × 32-bit (PC is 9-bit)
- D-MEM: 256 × 64-bit (8-bit word address); each word holds 4 × i16 elements

## Thread Model
- TID starts at 0, increments by 4 each kernel iteration
- 4 lanes of 16-bit data packed into one 64-bit register
- For 4-lane load: word address = TID / 4  (stride = 8 bytes per 64-bit word)
- Kernel runs until terminated by RET

## Branch Behavior
- BPR: branches if PRED == 1; target = imm15[8:0] (absolute PC)
- BR:  unconditional; target = imm15[8:0] (absolute PC)
- Branch is resolved in EX stage; *3 branch delay slot*

## Data Dependence
- We have IFRF(internal forwaring inside the registers) for both parameter register and register file, when data come to WB, can directly help the juniors in ID stage
- We have data depend on Sinor 1 and Sinor 2 Instructions, need to insert NOP

## Pipeline Stages
1. IF  - Instruction Fetch from I_M (512×32)
2. ID  - Decode (control_unit) + Register Read (RS1, RS2, RS3/RD)
3. EX  - ALU (alu_i16x4) / Tensor Core (tensor_core_bf16x4) / Branch / PRED update
4. MEM - Data Memory Access (D_M_64bit_256)
5. WB  - Write Back to Register File

## WB Source Select (wb_sel)
| wb_sel | Source        | Used by                                                             |
|--------|---------------|---------------------------------------------------------------------|
| 2'd0   | ALU result    | ADD_I16, SUB_I16, MAX_I16, ADD64, ADDI64, SETP_GE, SHIFTLV, SHIFTRV |
| 2'd1   | Tensor Core   | MUL_BF16, MAC_BF16                                                  |
| 2'd2   | D-MEM read    | LD64                                                                |
| 2'd3   | IMM / PARAM   | MOV, LD_PARAM                                                       |
