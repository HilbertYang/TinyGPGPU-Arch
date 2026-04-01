# G-Accelerator: FPGA SIMD GPGPU and BF16 Accelerator

G-Accelerator is a custom FPGA GPGPU built around a packed-SIMD execution model and a BF16 tensor datapath. The maintained implementation lives in the RTL, testbenches, and bring-up scripts in this repository.

## Current Status

- The current source of truth is `rtl/`, `docs/`, `sim/testbench/`, and `scripts/`.
- Files under `gen/` are outdated archival artifacts and should not be treated as the active toolchain.
- Sample CUDA/PTX files under `kernels/` and assembly samples under `compiler/` are reference material, not a guaranteed up-to-date build flow.

## Key Features

- 5-stage pipeline: `IF -> ID -> EX -> MEM -> WB`
- 64-bit packed register architecture with 4 lanes of 16-bit data
- Integer SIMD support for `ADD_I16`, `SUB_I16`, and `MAX_I16`
- BF16 tensor support for `MUL_BF16` and `MAC_BF16`
- BRAM-backed instruction and data memories
- Parameter register file plus explicit branch and predicate control

## Architecture Overview

The design targets the NetFPGA platform and uses a simple single-stream control model rather than GPU-style SIMT scheduling.

### Main Hardware Blocks

- Control unit for decode and branch control
- 16 x 64-bit general-purpose register file with R0 hardwired to zero
- 8 x 64-bit parameter register file
- 4-lane integer ALU
- BF16 tensor core built from `tensor16_pipe3`
- Instruction memory: `512 x 32`
- Data memory: `256 x 64`

### Execution Model

- This is a SIMD machine, not a SIMT machine.
- Packed 64-bit registers carry 4 lanes of `i16` or `bf16` values.
- Current maintained programs use explicit loop counters and address updates in general-purpose registers.
- Historical `gen/`-based assumptions about automatic PTX-to-ISA flow or built-in `TID` handling should not be treated as current behavior.

## Validation Workflow

1. Modify or inspect the RTL under `rtl/`.
2. Validate behavior with the testbenches in `sim/testbench/` using Vivado.
3. Start with lightweight unit coverage in `sim/testbench/tb_alu/`, then move to `sim/testbench/tb_gpu_core/` for pipeline and sample-program checks.
4. Use `sim/testbench/tb_ECG/` for the most application-like end-to-end BF16 validation flow currently in the repository.
5. Use the maintained helpers under `scripts/python/` or `scripts/perl/` for register-level bring-up and loading sample programs.
6. Use small utilities under `sim/script/` for BF16 conversion or simulation-log cleanup when inspecting results.
7. Treat `kernels/`, `compiler/`, and `gen/` as reference or archival material unless separately re-validated.

## Project Structure

- `/rtl`: Current hardware implementation
- `/sim/testbench`: Maintained Verilog testbenches
- `/sim/script`: Small simulation utilities such as BF16 conversion and log cleanup
- `/scripts/python`: Python bring-up and stepping helpers
- `/scripts/perl`: Perl bring-up and stepping helpers
- `/docs`: ISA and architecture notes
- `/kernels`: Sample CUDA / PTX reference inputs
- `/compiler`: Sample handwritten or generated assembly listings
- `/gen`: Outdated generated or experimental artifacts
- `/bin`, `/xml`: Vivado project artifacts and packaged outputs

## Design Notes

The project leans into SIMD over SIMT to keep the architecture practical on resource-constrained FPGA fabric. BF16 support is included to make multiply and MAC-heavy workloads cheaper in hardware while still preserving enough numeric range for accelerator-style experimentation.

## Maintained Validation Entry Points

- `sim/testbench/tb_alu/tb_alu_i16x4.v`: fast ALU-focused SIMD unit coverage
- `sim/testbench/tb_gpu_core/tb_gpu_core3_basic.v`: maintained full-pipeline smoke test
- `sim/testbench/tb_gpu_core/tb_gpu_top.v`: top-level programming, memory timing, and `start/done` bring-up reference
- `sim/testbench/tb_gpu_core/tb_gpu_core3_*_sample*.v`: sample-program-oriented ADD / MUL / FMA / SHIFT coverage
- `sim/testbench/tb_ECG/tb_ECG.v`: application-style 4-lane BF16 classifier validation with bundled feature and weight data
