# `sim` Directory Guide

This directory contains the simulation-related content for the project. The main contents are Verilog testbenches organized by function, plus a small helper script and sample test data.

## Directory Layout

- `testbench/`
  - `tb_gpu_core/`: GPU core and top-level integration testbenches
  - `tb_tensor_core/`: BF16 tensor core combinational tests
  - `tb_alu/`: SIMD integer ALU tests
  - `tb_ECG/`: end-to-end ECG beat classifier testbench
  - `tb_param_reg/`: register file related tests
  - `tb_reg/`: parameter register tests
- `script/`
  - `CLeanlog.py`: removes noisy warning lines from ISim logs
  - `original_log.txt`: sample input log used by the script

## Main Testbench Groups

### `tb_gpu_core/`

This group is focused on GPU core behavior and top-level interface bring-up:

- `tb_gpu_top.v`
  - Targets `gpu_top`
  - Covers IMEM, DMEM, parameter register programming and readback, plus the `start/done` flow
  - The file documents BRAM timing, read/write latency, and `prog_en` hold behavior in useful detail, so it is a good timing reference for the top-level memory interfaces
- `tb_gpu_core3_basic.v`
  - Basic instruction and execution path validation
- `tb_gpu_core3_sample.v`
  - Runs a sample program through the core
- `tb_gpu_core3_ADD_sample*.v`
  - Sample-program-based validation for `ADD` behavior
- `tb_gpu_core3_MUL_sample_step_version.v`
  - Step-by-step validation for BF16 `MUL`
- `tb_gpu_core3_FMA_sample*.v`
  - Sample-program-based validation for BF16 `MAC/FMA`
- `tb_gpu_core3_SHIFT_sample.v`
  - Shift instruction validation
- `gpu_core_stub.v`
  - Stub used for some testbench integration cases

### `tb_tensor_core/`

This group validates the BF16 tensor datapath:

- `tb_tensor_core_bf16x4.v`
  - Main testbench for `tensor_core_bf16x4`
  - Verifies both `MUL` and `MAC` modes
  - Includes both exact-match checks and per-lane approximate checks
- `tb_pe_bf16_comb.v`
  - BF16 processing-element combinational test
- `pe_bf16_comb_tb_pipe1.v`
  - Single-pipeline-stage version test
- `pe_bf16_comb_tb_pipe2.v`
  - Two-pipeline-stage version test

### `tb_alu/`

- `tb_alu_i16x4.v`
  - Testbench for the 4-lane `i16` SIMD ALU

### `tb_param_reg/` and `tb_reg/`

- `tb_param_reg/tb_regfile.v`
  - Register file behavior test
- `tb_reg/tb_param_regs.v`
  - Parameter register write/read test

### `tb_ECG/`

This is the most application-like and end-to-end testbench currently in the directory:

- `tb_ECG.v`
  - Targets `gpu_core`
  - Uses 4-lane packed BF16 SIMD to classify 4 heartbeats in parallel
  - The file header already documents the DMEM layout, instruction encoding format, and NOP scheduling policy
  - The modeled workload is a `64 -> 2` classifier producing two logits

## Data Files Under `tb_ECG`

### `features/`

Input features and reference outputs:

- `*_features_bf16.mem`: BF16 feature data for simulation loading
- `*_features_fp32.txt`: FP32 text reference for the same features
- `*_bf16_logits.txt`, `*_fp32_logits.txt`: BF16 and FP32 logit references
- `*_bf16_pred.txt`, `*_fp32_pred.txt`: classification result references
- `*_labels.txt`: labels
- `*_beat_symbols.txt`, `*_beat_samples.txt`, `*_record_ids.txt`: beat metadata
- `*_meta.json`: dataset metadata
- `*_reference_bundle.npz`: bundled reference data

### `weights/`

Classifier weights and bias data:

- `netfpga_classifier_weight_bf16.mem`
- `netfpga_classifier_bias_bf16.mem`
- `*_float.txt`: readable floating-point versions of the same data
- `netfpga_classifier_bf16_meta.json`: weight metadata

## Simulation Notes

- The repository root README treats `sim/testbench/` as one of the actively maintained validation entry points.
- There is currently no single simulation launcher script or Makefile under `sim`, so testbenches are expected to be compiled manually with the chosen simulator and the required RTL files.
- `tb_gpu_top.v` and `tb_ECG.v` both contain useful task wrappers and are good references when writing new testbenches.
- `tb_ECG.v` and `tb_gpu_top.v` both include `$dumpfile(...)` and `$dumpvars(...)`, so they can generate waveform files directly for debugging.
- `script/CLeanlog.py` expects `original_log.txt` in the current working directory, so running it from `sim/script/` is the simplest option.

## Suggested Reading Order

If you are new to this directory, a practical reading order is:

1. `testbench/tb_gpu_core/tb_gpu_top.v`
2. `testbench/tb_tensor_core/tb_tensor_core_bf16x4.v`
3. `testbench/tb_ECG/tb_ECG.v`
4. `script/CLeanlog.py`

This order helps you understand the top-level memory interface timing first, then the BF16 compute block, and finally the application-style validation flow with real sample data.
