#!/usr/bin/env python3
"""
gpu_sim.py
Cycle-accurate Python simulator for the custom GPU.
Used to verify PTX translation before Verilog simulation.

Usage:
  python3 gpu_sim.py gpu_program.hex [--kernel vec_add_i16] [--n 8]
"""

import sys
import struct
import argparse
from typing import Optional

# ─── BFloat16 helpers ─────────────────────────────────────────────────────────
def bf16_to_float(x: int) -> float:
    """Convert bf16 bit pattern to Python float."""
    # bf16 = upper 16 bits of float32
    bits32 = x << 16
    return struct.unpack('<f', struct.pack('<I', bits32))[0]

def float_to_bf16(f: float) -> int:
    """Convert Python float to bf16 bit pattern (round-to-nearest)."""
    bits32 = struct.unpack('<I', struct.pack('<f', f))[0]
    # Round to nearest (simple truncation)
    return (bits32 >> 16) & 0xFFFF

def bf16_mul(a: int, b: int) -> int:
    return float_to_bf16(bf16_to_float(a) * bf16_to_float(b))

def bf16_add(a: int, b: int) -> int:
    return float_to_bf16(bf16_to_float(a) + bf16_to_float(b))

def bf16_fma(a: int, b: int, c: int) -> int:
    return float_to_bf16(bf16_to_float(a) * bf16_to_float(b) + bf16_to_float(c))

# ─── 16-bit helpers ───────────────────────────────────────────────────────────
def s16(x): return x if x < 0x8000 else x - 0x10000
def u16(x): return x & 0xFFFF

def pack64_i16(l0, l1, l2, l3): return (u16(l3)<<48)|(u16(l2)<<32)|(u16(l1)<<16)|u16(l0)
def unpack64_i16(v): return [s16((v>>(16*i))&0xFFFF) for i in range(4)]
def unpack64_bf16(v): return [(v>>(16*i))&0xFFFF for i in range(4)]
def pack64_bf16(l): return sum((l[i]&0xFFFF)<<(16*i) for i in range(4))

# ─── Opcode defs ──────────────────────────────────────────────────────────────
OP = {
    0x00: 'NOP', 0x01: 'LD64', 0x02: 'ST64', 0x03: 'MOV',
    0x04: 'ADD_I16', 0x05: 'SUB_I16', 0x06: 'MAX_I16',
    0x07: 'MUL_BF16', 0x08: 'MAC_BF16',
    0x09: 'ADD64', 0x0A: 'ADDI64', 0x0B: 'BRA',
    0x0C: 'SETP_GE', 0x0D: 'MOV_TID', 0x0E: 'RET',
    0x0F: 'LD_PARAM', 0x10: 'MUL_WIDE',
}

class GPU:
    def __init__(self, imem: list, dmem_size=256):
        self.imem   = imem              # list of 32-bit instructions
        self.dmem   = [0]*dmem_size     # 64-bit words
        self.rf     = [0]*16            # 64-bit registers
        self.params = [0]*8             # 64-bit kernel parameters
        self.pc     = 0
        self.pred   = False
        self.tid    = 0
        self.halted = False
        self.cycles = 0

    def set_param(self, idx: int, val: int):
        self.params[idx] = val & ((1<<64)-1)

    def dmem_load(self, byte_addr: int) -> int:
        """Load 64-bit word from byte address."""
        word_addr = (byte_addr >> 3) % len(self.dmem)
        return self.dmem[word_addr]

    def dmem_store(self, byte_addr: int, val: int):
        word_addr = (byte_addr >> 3) % len(self.dmem)
        self.dmem[word_addr] = val & ((1<<64)-1)

    def getr(self, addr: int) -> int:
        return 0 if addr == 0 else self.rf[addr]

    def setr(self, addr: int, val: int):
        if addr != 0:
            self.rf[addr] = val & ((1<<64)-1)

    def step(self, verbose=False):
        if self.halted or self.pc >= len(self.imem):
            self.halted = True
            return

        instr = self.imem[self.pc]
        opc  = (instr >> 27) & 0x1F
        rd   = (instr >> 22) & 0x1F
        rs1  = (instr >> 17) & 0x1F
        rs2  = (instr >> 12) & 0x1F
        imm12 = instr & 0xFFF
        simm12 = imm12 if imm12 < 0x800 else imm12 - 0x1000
        imm17 = instr & 0x1FFFF
        param_idx = instr & 0x7

        a = self.getr(rs1)
        b = self.getr(rs2)
        c = self.getr(rd)   # for MAC accumulator

        op_name = OP.get(opc, f'UNK_{opc:X}')
        if verbose:
            print(f"  PC={self.pc:04X} {op_name:<10} R{rd} R{rs1} R{rs2} imm={simm12}")

        next_pc = self.pc + 1
        result = None
        self.cycles += 1

        if opc == 0x00:  # NOP
            pass

        elif opc == 0x01:  # LD64
            addr = a + simm12
            result = self.dmem_load(addr)
            self.setr(rd, result)

        elif opc == 0x02:  # ST64
            addr = a + simm12
            self.dmem_store(addr, b)

        elif opc == 0x03:  # MOV
            self.setr(rd, imm17)

        elif opc == 0x04:  # ADD_I16
            la = unpack64_i16(a); lb = unpack64_i16(b)
            r = [s16(la[i] + lb[i]) for i in range(4)]
            self.setr(rd, pack64_i16(*r))

        elif opc == 0x05:  # SUB_I16
            la = unpack64_i16(a); lb = unpack64_i16(b)
            r = [s16(la[i] - lb[i]) for i in range(4)]
            self.setr(rd, pack64_i16(*r))

        elif opc == 0x06:  # MAX_I16
            la = unpack64_i16(a); lb = unpack64_i16(b)
            r = [max(la[i], lb[i]) for i in range(4)]
            self.setr(rd, pack64_i16(*r))

        elif opc == 0x07:  # MUL_BF16
            la = unpack64_bf16(a); lb = unpack64_bf16(b)
            r = [bf16_mul(la[i], lb[i]) for i in range(4)]
            self.setr(rd, pack64_bf16(r))

        elif opc == 0x08:  # MAC_BF16 (rd = rs1 * rs2 + rd)
            la = unpack64_bf16(a); lb = unpack64_bf16(b); lc = unpack64_bf16(c)
            r = [bf16_fma(la[i], lb[i], lc[i]) for i in range(4)]
            self.setr(rd, pack64_bf16(r))

        elif opc == 0x09:  # ADD64
            self.setr(rd, (a + b) & ((1<<64)-1))

        elif opc == 0x0A:  # ADDI64
            self.setr(rd, (a + simm12) & ((1<<64)-1))

        elif opc == 0x0B:  # BRA
            if self.pred:
                next_pc = self.pc + simm12

        elif opc == 0x0C:  # SETP_GE
            a32 = a & 0xFFFFFFFF; b32 = b & 0xFFFFFFFF
            sa = a32 if a32 < 0x80000000 else a32 - 0x100000000
            sb = b32 if b32 < 0x80000000 else b32 - 0x100000000
            self.pred = (sa >= sb)

        elif opc == 0x0D:  # MOV_TID
            self.setr(rd, self.tid)

        elif opc == 0x0E:  # RET
            self.halted = True
            return

        elif opc == 0x0F:  # LD_PARAM
            self.setr(rd, self.params[param_idx])

        elif opc == 0x10:  # MUL_WIDE (rd = rs1[31:0] * imm12, sign-extended)
            sa = a & 0xFFFFFFFF
            if sa >= 0x80000000: sa -= 0x100000000
            self.setr(rd, (sa * simm12) & ((1<<64)-1))

        else:
            print(f"[WARN] Unknown opcode {opc:#x} at PC={self.pc}")

        self.pc = next_pc

    def run(self, max_cycles=100000, verbose=False):
        self.cycles = 0
        while not self.halted and self.cycles < max_cycles:
            self.step(verbose=verbose)
        return self.cycles

    def run_kernel(self, pc_start: int, n_elements: int, max_cycles=100000, verbose=False):
        """Run kernel iterating TID from 0 to n_elements step 4."""
        total_cycles = 0
        self.tid = 0
        while self.tid < n_elements:
            self.pc = pc_start
            self.halted = False
            self.rf = [0] * 16
            self.pred = False
            cyc = self.run(max_cycles=max_cycles, verbose=verbose)
            total_cycles += cyc
            self.tid += 4
        return total_cycles

# ─── Test Harness ─────────────────────────────────────────────────────────────
def load_hex(path: str) -> list:
    instrs = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                instrs.append(int(line, 16))
    return instrs

def load_kernel_map(path: str) -> dict:
    km = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if ':' in line and not line.startswith('#'):
                    name, rest = line.split(':', 1)
                    offset = int(rest.strip().split()[0])
                    km[name.strip()] = offset
    except FileNotFoundError:
        pass
    return km

def run_vec_add_i16(gpu: GPU, a_vals, b_vals, base_a=0, base_b=0x200, base_c=0x400):
    """Load data, run vec_add_i16, return results."""
    n = len(a_vals)
    # Store inputs as packed 64-bit (4 × i16 per word)
    for i in range(0, n, 4):
        chunk_a = [a_vals[j] if j < n else 0 for j in range(i, i+4)]
        chunk_b = [b_vals[j] if j < n else 0 for j in range(i, i+4)]
        gpu.dmem[(base_a>>3) + i//4] = pack64_i16(*chunk_a)
        gpu.dmem[(base_b>>3) + i//4] = pack64_i16(*chunk_b)

    gpu.set_param(0, base_a)  # ptr_a
    gpu.set_param(1, base_b)  # ptr_b
    gpu.set_param(2, base_c)  # ptr_c (output)
    gpu.set_param(3, n)       # element count
    return gpu

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('hex', help='GPU program hex file')
    parser.add_argument('--kernel', default='vec_add_i16')
    parser.add_argument('--n', type=int, default=8)
    parser.add_argument('--verbose', '-v', action='store_true')
    args = parser.parse_args()

    instrs = load_hex(args.hex)
    km = load_kernel_map(args.hex.replace('.hex', '_kernels.txt'))
    print(f"Loaded {len(instrs)} instructions")
    print(f"Kernel map: {km}")

    pc_start = km.get(args.kernel, 0)

    gpu = GPU(instrs)
    gpu.pc = pc_start

    n = args.n
    a_vals = list(range(n))
    b_vals = [10 + i for i in range(n)]

    if args.kernel == 'vec_add_i16':
        gpu = run_vec_add_i16(gpu, a_vals, b_vals)
        expected = [a_vals[i] + b_vals[i] for i in range(n)]
        label = 'ADD'
    elif args.kernel == 'vec_sub_i16':
        gpu = run_vec_add_i16(gpu, a_vals, b_vals)
        expected = [a_vals[i] - b_vals[i] for i in range(n)]
        label = 'SUB'
    elif args.kernel == 'relu_i16':
        a_vals = [-5+i*3 for i in range(n)]
        gpu.set_param(0, 0)
        gpu.set_param(1, 0x200)
        gpu.set_param(2, n)
        for i in range(0, n, 4):
            chunk = [a_vals[j] if j < n else 0 for j in range(i, i+4)]
            gpu.dmem[i//4] = pack64_i16(*chunk)
        expected = [max(0, a_vals[i]) for i in range(n)]
        label = 'RELU'
    else:
        print(f"No test harness for kernel '{args.kernel}', running with default params")
        expected = None
        label = args.kernel

    cycles = gpu.run_kernel(pc_start, n, verbose=args.verbose)
    print(f"\nKernel '{args.kernel}' completed in {cycles} cycles")

    if expected:
        print(f"\n{'Elem':>4}  {'A':>6}  {'B':>6}  {'Expected':>10}  {'Got':>10}  {'OK?':>4}")
        print('-' * 50)
        out_base = 0x400
        all_ok = True
        for i in range(n):
            word_idx = i // 4
            lane = i % 4
            word = gpu.dmem[(out_base>>3) + word_idx]
            vals = unpack64_i16(word)
            got = vals[lane]
            exp = expected[i]
            ok = (got == exp)
            if not ok: all_ok = False
            b_str = str(b_vals[i]) if label != 'RELU' else ''
            print(f"{i:>4}  {a_vals[i]:>6}  {b_str:>6}  {exp:>10}  {got:>10}  {'✓' if ok else '✗':>4}")

        print()
        if all_ok:
            print("✅ All results correct!")
        else:
            print("❌ Some results incorrect!")

if __name__ == '__main__':
    main()
