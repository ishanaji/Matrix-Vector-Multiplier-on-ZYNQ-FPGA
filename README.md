# Matrix-Vector Multiplier on Zynq FPGA

A hardware accelerator for `y = A · x`, built with Vitis HLS and deployed on a
Zynq-7000 (PYNQ-Z2, `xc7z020`) SoC. The matrix `A` (up to 64×64) is loaded
once over AXI-Lite, and batches of input vectors `x` are streamed in / results
`y` streamed out over AXI-Stream via AXI-DMA, so the PS can push many
vector-matrix products through the PL without reloading `A` each time.

Course project for EE5332 (HLS-based accelerator design).

**Authors:** Ishan Aji Hassan (EE23B097), Arjun Krishnaswamy (EE23B009), Sai Harshith Gajendra (EE23B069)

## How it works

The accelerator is a single HLS function, `matmul_stream` (`matmul_stream2.cpp` /
`matmul.h`), synthesized into an IP block and wired into a Zynq block design
alongside an AXI DMA:

```
                 AXI-Lite (control + A matrix)
   ┌─────┐  ───────────────────────────────────►  ┌───────────────┐
   │ PS7 │                                          │ matmul_stream │
   │(ARM)│  ──AXI-DMA (MM2S)──► in_stream (x) ────► │      IP       │
   │     │  ◄─AXI-DMA (S2MM)◄─ out_stream (y) ◄──── │               │
   └─────┘                                          └───────────────┘
```

- **A (the matrix)** is written into the IP's internal BRAM through the
  `s_axi_control` (AXI-Lite) interface, along with the `rows`, `cols`, and
  `num_vectors` scalar registers. It only needs to be loaded once per matrix.
- **x (input vectors)** and **y (output vectors)** are streamed through
  `in_stream` / `out_stream` (`AXI4-Stream`) via an AXI DMA in simple
  (non-scatter-gather) mode, so a whole batch of vectors can be pushed through
  in one DMA transfer without CPU intervention per vector.
- Values on the stream are packed as 32-bit words carrying a 24-bit signed
  fixed-point payload (`pack`/`unpack` in `matmul.h`), which the PS reconstructs
  by sign-extending back to 32 bits.

### Numeric representation

Values are `ap_fixed<24,14>` (24 total bits, 14 integer bits) fixed-point,
chosen to keep error to roughly ±1 while fitting inside a 32-bit AXI-Stream
word. The width is a single `typedef` (`data_t` in `matmul.h`) so the
precision/resource trade-off can be swept just by changing that one line (and
`DATA_WIDTH` to match).

### Interface summary

| Signal | Type | Purpose |
|---|---|---|
| `A` | `s_axilite` | 64×64 matrix, loaded once, held in BRAM |
| `rows`, `cols`, `num_vectors` | `s_axilite` | Matrix dimensions and batch size |
| `in_stream` | `axis` | Streams in `num_vectors` × `cols` input elements |
| `out_stream` | `axis` | Streams out `num_vectors` × `rows` result elements, `TLAST` on the final sample |

## Design space exploration

Three variants of `compute_y`'s inner dot product were synthesized and
compared, all against a 64×64 matrix:

| Variant | Inner loop | DSPs | BRAM | Iteration latency | Notes |
|---|---|---|---|---|---|
| Baseline | no unroll, no pipeline | 1 | 5 | 323 cycles/row | DSP time-multiplexed (folded) across all 64 MACs |
| Unrolled ×4 | `UNROLL` factor 4, `A`/`x_local` cyclically partitioned ×4 | 4 | 4 | ~73 cycles/row | ~4× baseline throughput; couldn't reach `II=1` despite partitioning |
| Fully pipelined | fully unrolled dot product, `II=1` on `compute_y` | 64 | 64–128* | 1 cycle/row (pipelined) | `A` and `x_local` fully partitioned; one MAC per element per cycle |

\* BRAM usage for the pipelined variant depends on `data_t` width: 128 BRAMs
with `ap_fixed<24,14>` (a 64-element column needs 2 BRAMs), dropping to 64
BRAMs with a narrower `ap_fixed<16,2>`.

The fully pipelined variant was the one taken through to FPGA deployment.
See the project report for the full Vitis HLS synthesis reports and resource
breakdowns for all three points.

## Deploying to hardware

### 1. Synthesize the IP (Vitis HLS)

Run `matmul_stream2.cpp` / `matmul.h` through Vitis HLS, then export the RTL
as an IP-XACT zip.

### 2. Build the Vivado project

```
matmul_project/
├── build/    # Vivado project output
├── ip/       # extracted HLS IP → matmul_project/ip/matmul_stream
├── pynq/     # generated .bit / .hwh land here
└── vivado/   # copy create_project.tcl here
```

Extract the HLS RTL export into `matmul_project/ip/matmul_stream`, copy
`create_project.tcl` into `matmul_project/vivado`, then in the Vivado Tcl
console:

```tcl
source /path/to/matmul_project/vivado/create_project.tcl
```

`create_project.tcl` builds the full block design (Zynq PS7 with HP0 enabled,
AXI DMA in simple mode, the `matmul_stream` IP, and the AXI-Lite/AXI-Stream
interconnect between them), runs synthesis and implementation, and copies the
resulting `matmul_design.bit` / `matmul_design.hwh` into `matmul_project/pynq`.
Edit the `PROJ_DIR` / `MATMUL_IP` paths at the top of the script to match
where you put `matmul_project`.

### 3. Run on the board

Copy `matmul_design.bit` and `matmul_design.hwh` to the PYNQ board and run
against them with `notebook_for_fpga(1)(fixed)(with output).ipynb`, which:

1. Generates a random 64×64 `A` and a batch of input vectors in NumPy.
2. Converts both to `ap_fixed<24,14>` by scaling by `2^10` and casting to `int32`.
3. Writes `A` and the control registers over AXI-Lite.
4. Streams the input batch in and results out over AXI-DMA.
5. Sign-extends the 24-bit results back to 32 bits, rescales, and checks
   against a floating-point NumPy reference.

## Results

Measured on a PYNQ-Z2 board with a 64×64 matrix and a batch of 10 vectors:

| Metric | Value |
|---|---|
| Verification | PASS |
| Max absolute error | 4.57 × 10⁻¹ |
| ARM CPU time | 1.39 ms |
| FPGA + DMA time | 3.01 ms |
| Speedup vs. CPU | 0.46× |
| Throughput | 3,323 vectors/s |

The FPGA implementation is slower than the ARM CPU reference at this problem
size — for a 64×64 matmul, per-transfer AXI-Lite/DMA setup overhead dominates
over the actual compute time, which the fully pipelined `II=1` core executes
in a handful of cycles per vector. The accelerator would be expected to pay
off at larger matrix sizes or when amortized over much bigger vector batches.

## Repository contents

| File | Description |
|---|---|
| `matmul_stream2.cpp` / `matmul.h` | HLS source for the `matmul_stream` accelerator |
| `create_project.tcl` | Vivado Tcl script: builds the block design, runs synthesis/implementation, exports `.bit`/`.hwh` |
| `notebook_for_fpga(1)(fixed)(with output).ipynb` | PYNQ notebook: generates test data, drives the accelerator, verifies against NumPy |
| `Project_Report_with_updated Vitis_Synthesis Reports.pdf` | Full project report with synthesis reports and resource analysis for all three design points |
