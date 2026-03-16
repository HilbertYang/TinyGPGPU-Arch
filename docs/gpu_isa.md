# Custom GPU ISA - Maintained Notes

This document describes the ISA as implemented by the current maintained RTL. If you find a conflict, prefer `rtl/gpu_core/gpu_core3.v`, `rtl/control_unit/control_unit.v`, and the maintained testbenches over older generated artifacts.

## Instruction Format (32-bit)

| [31:27] | [26:23] | [22:19] | [18:15] | [14:0] |
|---------|---------|---------|---------|--------|
| OPCODE  | RD      | RS1     | RS2     | IMM15  |

`RD` also serves as `RS3` for `MAC_BF16`.

## Opcodes (5-bit)

| Code  | Hex  | Mnemonic  | Current Meaning |
|-------|------|-----------|-----------------|
| 00000 | 0x00 | NOP       | No operation |
| 00001 | 0x01 | ADD_I16   | `RD[4xi16] = RS1[4xi16] + RS2[4xi16]` |
| 00010 | 0x02 | SUB_I16   | `RD[4xi16] = RS1[4xi16] - RS2[4xi16]` |
| 00011 | 0x03 | MAX_I16   | `RD[4xi16] = max(RS1[4xi16], RS2[4xi16])` |
| 00100 | 0x04 | ADD64     | `RD = RS1 + RS2` |
| 00101 | 0x05 | ADDI64    | `RD = RS1 + sign_ext(imm15)` |
| 00110 | 0x06 | SETP_GE   | `PRED = (RS1[31:0] >= RS2[31:0])` |
| 00111 | 0x07 | SHIFTL16  | `RD = RS1 << 16` (fixed 16-bit left shift; lane 0 zeroed, upper lanes shift up) |
| 01000 | 0x08 | SHIFTR16  | `RD = RS1 >> 16` (fixed 16-bit logical right shift; lane 3 zeroed, lower lanes shift down) |
| 01001 | 0x09 | MAC_BF16  | `RD[4xbf16] = RS1[4xbf16] * RS2[4xbf16] + RD[4xbf16]` |
| 01010 | 0x0A | MUL_BF16  | `RD[4xbf16] = RS1[4xbf16] * RS2[4xbf16]` |
| 10000 | 0x10 | LD64      | `RD = DMEM[RS1 + imm15]` |
| 10001 | 0x11 | ST64      | `DMEM[RS1 + imm15] = RD` |
| 10010 | 0x12 | MOV       | `RD = sign_ext(imm15)` |
| 10011 | 0x13 | BPR       | If `PRED == 1`, `PC = imm15[8:0]` |
| 10100 | 0x14 | BR        | `PC = imm15[8:0]` |
| 10101 | 0x15 | RET       | Halt / end of kernel |
| 10110 | 0x16 | LD_PARAM  | `RD = PARAM[imm3]` |

## Register File

- `R0-R15`: 64-bit general-purpose registers
- `R0` is hardwired to zero
- 3 read ports: `RS1`, `RS2`, `RS3(=RD)`
- `RS3` is used as the accumulator input for `MAC_BF16`
- `PRED` is a 1-bit predicate register written by `SETP_GE`
- `PC` is a 9-bit word-addressed program counter

## Parameter Registers

- `PARAM[0..7]`: 64-bit parameter registers
- Written externally via `param_wr_en`, `param_wr_addr`, and `param_wr_data`
- Read via `LD_PARAM`

## Memory

- Instruction memory: `512 x 32`
- Data memory: `256 x 64`
- Each 64-bit data word naturally packs 4 lanes of 16-bit data

## Execution Model

- The current maintained core is SIMD, not SIMT.
- 64-bit registers are treated as packed vectors of 4 lanes.
- Current maintained sample programs use explicit loop counters and explicit address updates in general-purpose registers.
- Older `gen/` artifacts that describe a dedicated `TID` or `MOV_TID` flow are archival and should not be treated as current ISA behavior.

## Branch Behavior

- `BPR` branches when `PRED == 1`
- `BR` is unconditional
- Both use `imm15[8:0]` as an absolute program address
- Branches resolve in EX
- The maintained programs and testbenches assume a 3-instruction branch delay window

## Data Hazards and Scheduling

- The register file and parameter register file both provide same-cycle write-to-read forwarding at the read stage.
- There is no general EX/MEM forwarding network and no general branch flush mechanism.
- The shipped helper programs and testbenches use conservative manual scheduling with explicit NOP spacing.
- A common safe rule in the maintained examples is to leave 3 instruction slots after branch issue and to schedule around write-after-read dependencies explicitly.
- Tensor-core operations also interact with internal stall logic in `gpu_core3.v`; verify timing-sensitive assumptions against current RTL when editing programs.

## Pipeline Stages

1. IF - Instruction fetch from instruction memory
2. ID - Decode plus register / parameter reads
3. EX - ALU, tensor core issue, branch evaluation, predicate update
4. MEM - Data memory access
5. WB - Register writeback

## Writeback Select (`wb_sel`)

| wb_sel | Source      | Used by |
|--------|-------------|---------|
| 2'd0   | ALU result  | `ADD_I16`, `SUB_I16`, `MAX_I16`, `ADD64`, `ADDI64`, `SETP_GE`, `SHIFTL16`, `SHIFTR16` |
| 2'd1   | Tensor core | `MUL_BF16`, `MAC_BF16` |
| 2'd2   | D-MEM read  | `LD64` |
| 2'd3   | IMM / PARAM | `MOV`, `LD_PARAM` |
