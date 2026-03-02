#!/usr/bin/env python3
"""
ptx_to_hex.py
Translates PTX assembly into custom GPU machine code.

Hardware ISA (32-bit instruction):
  [31:27] OPCODE  (5 bits)
  [26:23] RD      (4 bits, reg index 0-15)
  [22:19] RS1     (4 bits)
  [18:15] RS2     (4 bits)
  [14:0]  IMM15   (15 bits, signed)

Opcodes match control_unit.v:
  NOP=0x00  ADD_I16=0x01  SUB_I16=0x02  MAX_I16=0x03
  ADD64=0x04  ADDI64=0x05  SETP_GE=0x06
  SHIFTLV=0x07  SHIFTRV=0x08
  MAC_BF16=0x09  MUL_BF16=0x0a
  LD64=0x10  ST64=0x11  MOV=0x12
  BPR=0x13  BR=0x14  RET=0x15  LD_PARAM=0x16

NOP insertion policy (no pipeline forwarding / flush hardware):
  - 3 NOPs after every ADD_I16  (data hazard)
  - 3 NOPs after every MUL_BF16 / MAC_BF16  (data hazard)
  - Branch NOPs must be added manually in PTX source

Usage:
  python3 ptx_to_hex.py kernel.ptx gpu_program.hex [listing.lst]
"""

import sys
import re
from typing import Optional

# ─── Opcode Table (must match control_unit.v) ────────────────────────────────
OPCODES = {
    'NOP':      0x00,
    'ADD_I16':  0x01,
    'SUB_I16':  0x02,
    'MAX_I16':  0x03,
    'ADD64':    0x04,
    'ADDI64':   0x05,
    'SETP_GE':  0x06,
    'SHIFTLV':  0x07,
    'SHIFTRV':  0x08,
    'MAC_BF16': 0x09,
    'MUL_BF16': 0x0a,
    'LD64':     0x10,
    'ST64':     0x11,
    'MOV':      0x12,
    'BPR':      0x13,   # predicated branch: if PRED → PC = imm15[8:0]
    'BR':       0x14,   # unconditional:      PC = imm15[8:0]
    'RET':      0x15,
    'LD_PARAM': 0x16,
}

NOP_INSTR        = 0x00000000
DATA_HAZARD_NOPS = 3   # NOPs inserted after write instructions

# ─── Encoding ─────────────────────────────────────────────────────────────────
def encode(op: str, rd=0, rs1=0, rs2=0, imm15=0) -> int:
    """Encode a 32-bit instruction: {op[4:0], rd[3:0], rs1[3:0], rs2[3:0], imm15[14:0]}"""
    opc = OPCODES[op]
    instr  = (opc   & 0x1F) << 27
    instr |= (rd    & 0x0F) << 23   # 4-bit [26:23]
    instr |= (rs1   & 0x0F) << 19   # 4-bit [22:19]
    instr |= (rs2   & 0x0F) << 15   # 4-bit [18:15]
    instr |= (imm15 & 0x7FFF)        # 15-bit [14:0]
    return instr & 0xFFFFFFFF

def encode_mov(rd: int, imm15: int) -> int:
    """MOV RD, sign_ext(imm15)"""
    return encode('MOV', rd=rd, imm15=imm15 & 0x7FFF)

def encode_ld_param(rd: int, param_idx: int) -> int:
    """LD_PARAM RD, param[idx] — idx in bits [2:0] (part of imm15)"""
    opc = OPCODES['LD_PARAM']
    instr  = (opc & 0x1F) << 27
    instr |= (rd  & 0x0F) << 23
    instr |= (param_idx & 0x7)       # [2:0] of imm15
    return instr & 0xFFFFFFFF

def encode_branch(opname: str, abs_pc9: int) -> int:
    """BPR / BR with 9-bit absolute target in imm15[8:0]"""
    opc = OPCODES[opname]
    instr  = (opc & 0x1F) << 27
    instr |= (abs_pc9 & 0x1FF)       # [8:0] of imm15
    return instr & 0xFFFFFFFF

def _nops(n: int):
    return [(NOP_INSTR, None)] * n

# ─── Register Allocator ──────────────────────────────────────────────────────
class RegAlloc:
    """Maps PTX virtual registers to physical registers R1-R15 (R0 = zero)."""
    def __init__(self):
        self.map  = {}
        self.next = 1

    def alloc(self, name: str) -> int:
        if name not in self.map:
            if self.next > 15:
                self.next = 1
            self.map[name] = self.next
            self.next += 1
        return self.map[name]

    def get(self, name: str) -> int:
        if name in ('0', 'zero'):
            return 0
        return self.alloc(name)

# ─── PTX Parsing helpers ─────────────────────────────────────────────────────
def strip_comment(line: str) -> str:
    idx = line.find('//')
    if idx >= 0:
        line = line[:idx]
    return line.strip()

def parse_reg(tok: str) -> str:
    return tok.strip().rstrip(',').strip('[];')

def parse_imm(tok: str) -> int:
    tok = tok.strip().rstrip(',').strip()
    return int(tok, 16) if tok.startswith(('0x', '0X')) else int(tok)

# ─── Kernel representation ───────────────────────────────────────────────────
class PTXKernel:
    def __init__(self, name: str, params: list):
        self.name   = name
        self.params = params
        self.lines  = []

# ─── Translator ──────────────────────────────────────────────────────────────
class PTXTranslator:
    def __init__(self):
        self.kernels: list[PTXKernel]    = []
        self.instructions: list[int]     = []
        self.kernel_offsets: dict[str, int] = {}

    # ── Phase 1: parse PTX into kernel objects ──────────────────────────────
    def parse(self, src: str):
        lines = src.splitlines()
        i = 0
        while i < len(lines):
            line = strip_comment(lines[i])
            if '.visible .entry' in line or line.startswith('.entry'):
                m = re.search(r'\.entry\s+(\w+)', line)
                kname = m.group(1) if m else f'kernel_{i}'
                params = []
                while i < len(lines) and '{' not in lines[i]:
                    pline = strip_comment(lines[i])
                    pm = re.search(r'\.param\s+(\S+)\s+(\w+)', pline)
                    if pm:
                        params.append((pm.group(1), pm.group(2)))
                    i += 1
                body = []
                depth = 1
                i += 1
                while i < len(lines) and depth > 0:
                    bl = lines[i]
                    depth += bl.count('{') - bl.count('}')
                    if depth > 0:
                        body.append(bl)
                    i += 1
                k = PTXKernel(kname, params)
                k.lines = body
                self.kernels.append(k)
            else:
                i += 1

    # ── Phase 2: translate each kernel ─────────────────────────────────────
    def translate(self):
        for kernel in self.kernels:
            self.kernel_offsets[kernel.name] = len(self.instructions)
            self._translate_kernel(kernel)
        return self.instructions

    def _translate_kernel(self, kernel: PTXKernel):
        ra        = RegAlloc()
        param_map = {pname: idx for idx, (_, pname) in enumerate(kernel.params)}

        instrs_local: list[tuple] = []   # (int_instr | None, label | None)
        label_pc:    dict[str, int] = {}
        pending_bra: list[tuple]   = []  # (idx, label)

        in_asm   = False
        asm_const = 0

        for raw in kernel.lines:
            line = strip_comment(raw)
            if not line:
                continue

            # ── Inline ASM ────────────────────────────────────────────────
            if '// begin inline asm' in raw or 'begin inline asm' in line:
                in_asm    = True
                asm_const = 0
                continue
            if '// end inline asm' in raw or 'end inline asm' in line:
                in_asm = False
                continue

            if in_asm:
                line = line.rstrip(';}').strip()

                # mov.b16 c, 0xXXXXU  → capture constant
                mov_m = re.search(r'mov\.b16\s+c\s*,\s*(0x[0-9a-fA-F]+)U?', line)
                if mov_m:
                    asm_const = int(mov_m.group(1), 16)
                    continue

                # fma.rn.bf16 rd, rs1, rs2, rs3_or_c
                fma_m = re.search(
                    r'fma\.rn\.bf16\s+(%\w+)\s*,\s*(%\w+)\s*,\s*(%\w+)\s*,\s*(\S+)', line)
                if fma_m:
                    rd_p  = ra.alloc(fma_m.group(1))
                    rs1_p = ra.alloc(fma_m.group(2))
                    rs2_p = ra.alloc(fma_m.group(3))
                    rs3_tok = fma_m.group(4).rstrip(';').strip()

                    if rs3_tok == 'c':
                        if asm_const == 0x8000:
                            # fma(a, b, -0.0) ≈ MUL
                            instr = encode('MUL_BF16', rd=rd_p, rs1=rs1_p, rs2=rs2_p)
                        else:
                            # fma(a, 1.0, c) ≈ ADD
                            instr = encode('ADD_I16', rd=rd_p, rs1=rs1_p, rs2=rs2_p)
                    else:
                        rs3_p = ra.alloc(rs3_tok)
                        # rd = rs1 * rs2 + rs3;  if rs3 != rd, copy first
                        if rs3_p != rd_p:
                            instrs_local.append(
                                (encode('ADD64', rd=rd_p, rs1=rs3_p, rs2=0), None))
                            instrs_local.extend(_nops(DATA_HAZARD_NOPS))
                        instr = encode('MAC_BF16', rd=rd_p, rs1=rs1_p, rs2=rs2_p)

                    instrs_local.append((instr, None))
                    # ── NOP insertion after MUL/MAC (FMA) ─────────────────
                    instrs_local.extend(_nops(DATA_HAZARD_NOPS))
                continue

            # ── Label ──────────────────────────────────────────────────────
            label_m = re.match(r'\$(\w+)\s*:', line)
            if label_m:
                label_pc[label_m.group(1)] = len(instrs_local)
                continue

            # ── Skip declarations ──────────────────────────────────────────
            if line.startswith(('.reg', '.local', '.shared', '{', '}')):
                continue

            # ── ret ────────────────────────────────────────────────────────
            if line in ('ret;', 'ret'):
                instrs_local.append((encode('RET'), None))
                continue

            # ── ld.param ───────────────────────────────────────────────────
            ldp_m = re.match(r'ld\.param\.\w+\s+(%\w+)\s*,\s*\[(\w+)\]', line)
            if ldp_m:
                rd_p  = ra.alloc(ldp_m.group(1))
                pidx  = param_map.get(ldp_m.group(2), 0)
                instrs_local.append((encode_ld_param(rd_p, pidx), None))
                continue

            # ── mov.u32 %r1, %tid.x ────────────────────────────────────────
            # No MOV_TID in new ISA — use R0 (always 0) as a placeholder NOP
            tid_m = re.match(r'mov\.\w+\s+(%\w+)\s*,\s*%tid\.x', line)
            if tid_m:
                print(f"  [WARN] MOV_TID not in new ISA: {line!r} → NOP")
                instrs_local.append((NOP_INSTR, None))
                continue

            # ── setp.ge ────────────────────────────────────────────────────
            setp_m = re.match(r'setp\.ge\.\w+\s+(%\w+)\s*,\s*(%\w+)\s*,\s*(%\w+)', line)
            if setp_m:
                rs1_p = ra.get(setp_m.group(2))
                rs2_p = ra.get(setp_m.group(3))
                instrs_local.append((encode('SETP_GE', rs1=rs1_p, rs2=rs2_p), None))
                continue

            # ── @%p1 bra $label  (conditional → BPR) ─────────────────────
            bra_m = re.match(r'@%\w+\s+bra\s+\$(\w+)', line)
            if bra_m:
                lbl = bra_m.group(1)
                idx = len(instrs_local)
                instrs_local.append((None, lbl))
                pending_bra.append((idx, lbl, 'BPR'))
                continue

            # ── bra $label (unconditional → BR) ───────────────────────────
            ubra_m = re.match(r'bra\s+\$(\w+)', line)
            if ubra_m:
                lbl = ubra_m.group(1)
                idx = len(instrs_local)
                instrs_local.append((None, lbl))
                pending_bra.append((idx, lbl, 'BR'))
                continue

            # ── cvta.to.global ─────────────────────────────────────────────
            cvta_m = re.match(r'cvta\.to\.global\.\w+\s+(%\w+)\s*,\s*(%\w+)', line)
            if cvta_m:
                rd_p  = ra.alloc(cvta_m.group(1))
                rs1_p = ra.get(cvta_m.group(2))
                instrs_local.append((encode('ADD64', rd=rd_p, rs1=rs1_p, rs2=0), None))
                continue

            # ── mul.wide.s32 → no ISA equivalent, NOP ─────────────────────
            mulw_m = re.match(r'mul\.wide\.s32\s+(%\w+)\s*,\s*(%\w+)\s*,\s*(\d+)', line)
            if mulw_m:
                print(f"  [WARN] MUL_WIDE not in new ISA: {line!r} → NOP")
                instrs_local.append((NOP_INSTR, None))
                continue

            # ── add.s64 ────────────────────────────────────────────────────
            add64_m = re.match(r'add\.s64\s+(%\w+)\s*,\s*(%\w+)\s*,\s*(%\w+)', line)
            if add64_m:
                rd_p  = ra.alloc(add64_m.group(1))
                rs1_p = ra.get(add64_m.group(2))
                rs2_p = ra.get(add64_m.group(3))
                instrs_local.append((encode('ADD64', rd=rd_p, rs1=rs1_p, rs2=rs2_p), None))
                continue

            # ── ld.global.u16 / ld.global.u64 ────────────────────────────
            ldg_m = re.match(r'ld\.global\.\w+\s+(%\w+)\s*,\s*\[(%\w+)\]', line)
            if ldg_m:
                rd_p  = ra.alloc(ldg_m.group(1))
                rs1_p = ra.get(ldg_m.group(2))
                instrs_local.append((encode('LD64', rd=rd_p, rs1=rs1_p), None))
                continue

            # ── st.global.u16 / st.global.u64 ────────────────────────────
            stg_m = re.match(r'st\.global\.\w+\s+\[(%\w+)\]\s*,\s*(%\w+)', line)
            if stg_m:
                rs1_p = ra.get(stg_m.group(1))   # address register → rs1
                rd_p  = ra.get(stg_m.group(2))   # data register    → rd
                instrs_local.append((encode('ST64', rd=rd_p, rs1=rs1_p), None))
                continue

            # ── add.s16 ────────────────────────────────────────────────────
            add16_m = re.match(r'add\.s16\s+(%\w+)\s*,\s*(%\w+)\s*,\s*(%\w+)', line)
            if add16_m:
                rd_p  = ra.alloc(add16_m.group(1))
                rs1_p = ra.get(add16_m.group(2))
                rs2_p = ra.get(add16_m.group(3))
                instrs_local.append((encode('ADD_I16', rd=rd_p, rs1=rs1_p, rs2=rs2_p), None))
                # ── NOP insertion after ADD ────────────────────────────────
                instrs_local.extend(_nops(DATA_HAZARD_NOPS))
                continue

            # ── sub.s16 ────────────────────────────────────────────────────
            sub16_m = re.match(r'sub\.s16\s+(%\w+)\s*,\s*(%\w+)\s*,\s*(%\w+)', line)
            if sub16_m:
                rd_p  = ra.alloc(sub16_m.group(1))
                rs1_p = ra.get(sub16_m.group(2))
                rs2_p = ra.get(sub16_m.group(3))
                instrs_local.append((encode('SUB_I16', rd=rd_p, rs1=rs1_p, rs2=rs2_p), None))
                continue

            # ── max.s16 ────────────────────────────────────────────────────
            max16_m = re.match(r'max\.s16\s+(%\w+)\s*,\s*(%\w+)\s*,\s*(\S+)', line)
            if max16_m:
                rd_p  = ra.alloc(max16_m.group(1))
                rs1_p = ra.get(max16_m.group(2))
                instrs_local.append((encode('MAX_I16', rd=rd_p, rs1=rs1_p, rs2=0), None))
                continue

            # ── Unrecognized ────────────────────────────────────────────────
            print(f"  [WARN] Unrecognized PTX: {line!r} → NOP")
            instrs_local.append((NOP_INSTR, None))

        # ── Resolve branches (absolute address) ───────────────────────────
        base = len(self.instructions)
        for idx, lbl, branch_op in pending_bra:
            found = None
            for k, v in label_pc.items():
                if k == lbl or lbl.endswith(k) or k.endswith(lbl):
                    found = v
                    break
            if found is None:
                found = len(instrs_local)   # past end → RET-like

            abs_pc = (base + found) & 0x1FF   # 9-bit absolute word address
            instrs_local[idx] = (encode_branch(branch_op, abs_pc), None)

        # ── Append to global list ──────────────────────────────────────────
        for instr, _ in instrs_local:
            self.instructions.append(instr if instr is not None else NOP_INSTR)

        print(f"Kernel '{kernel.name}': {len(instrs_local)} instructions @ offset {base}")

    # ── Output ─────────────────────────────────────────────────────────────
    def dump_hex(self, path: str):
        with open(path, 'w') as f:
            for instr in self.instructions:
                f.write(f"{instr:08X}\n")
        print(f"Written {len(self.instructions)} instructions to {path}")

    def dump_listing(self, path: str):
        rev_op = {v: k for k, v in OPCODES.items()}
        with open(path, 'w') as f:
            f.write("ADDR  HEX        OP          RD   RS1  RS2  IMM15\n")
            f.write("-" * 58 + "\n")
            for i, instr in enumerate(self.instructions):
                opc   = (instr >> 27) & 0x1F
                rd    = (instr >> 23) & 0x0F
                rs1   = (instr >> 19) & 0x0F
                rs2   = (instr >> 15) & 0x0F
                imm15 = instr & 0x7FFF
                simm  = imm15 if imm15 < 0x4000 else imm15 - 0x8000
                op_name = rev_op.get(opc, f'UNK_{opc:02X}')
                f.write(f"{i:04X}  {instr:08X}   {op_name:<10}  R{rd:<3}  R{rs1:<3}  R{rs2:<3}  {simm:+d}\n")
        print(f"Listing written to {path}")

    def dump_kernel_map(self, path: str):
        with open(path, 'w') as f:
            f.write("# Kernel entry point table\n")
            for name, offset in self.kernel_offsets.items():
                f.write(f"{name}: {offset} (0x{offset:04X})\n")
        print(f"Kernel map written to {path}")


# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 3:
        print("Usage: ptx_to_hex.py <input.ptx> <output.hex> [listing.lst]")
        sys.exit(1)

    ptx_file = sys.argv[1]
    hex_file = sys.argv[2]
    lst_file = sys.argv[3] if len(sys.argv) > 3 else hex_file.replace('.hex', '.lst')
    map_file = hex_file.replace('.hex', '_kernels.txt')

    with open(ptx_file) as f:
        src = f.read()

    t = PTXTranslator()
    t.parse(src)
    t.translate()
    t.dump_hex(hex_file)
    t.dump_listing(lst_file)
    t.dump_kernel_map(map_file)

if __name__ == '__main__':
    main()
