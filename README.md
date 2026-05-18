# RISC-V RV32IM Pipelined Processor

A 6-stage pipelined RISC-V processor implementing the RV32IM instruction set in SystemVerilog, deployed on a Digilent Basys 3 FPGA (Xilinx Artix-7 XC7A35T) with clean timing closure at **100 MHz**.

I started this project with the standard Patterson & Hennessy 5-stage pipeline running the base RV32I instruction set. It worked, hit about 91 MHz on the Artix-7, and passed the official riscv-tests compliance suite. But I wanted to push it further, so I started adding what real embedded cores actually have: hardware multiply/divide (the full RV32M extension), M-mode privileged architecture with CSR access and trap handling, a gshare branch predictor with a BTB and return address stack, and hardware performance counters that let software measure its own IPC.

The problem was that all of these features converge in the execute stage. After adding them, the critical path blew up to 19 logic levels and 15.5 ns through the forwarding mux, ALU carry chain, and branch resolution logic. Timing failed at -5.539 ns, capping the design at roughly 64 MHz. I could have accepted that, but 36% of every clock cycle being dead time wasn't something I was willing to ship. So I split the execute stage into EX1 (forwarding and operand selection) and EX2 (ALU, branch, MDU, CSR), following the same approach that cores like ARM Cortex-M4 and RISC-V Ibex use when they need to hit higher frequencies. That brought the critical path down to 7 logic levels at 9.87 ns and closed timing at 100 MHz with +0.135 ns of positive slack.

The tradeoff is a deeper pipeline: mispredictions now cost 3 cycles instead of 2. But the gshare predictor with BTB and RAS absorbs most of that penalty, and the 56% frequency gain more than compensates. The full design supports all 48 RV32IM instructions, runs C programs compiled with a standard RISC-V GCC toolchain over UART, and has been validated through a 24-point comprehensive test suite, the 37-test riscv-tests compliance suite, and deployment on real hardware.

**Author:** Devansh Joshi

## Synthesis Results (Artix-7 XC7A35T, Vivado 2025.2)

| Metric | Value |
|--------|-------|
| Clock | **100 MHz** — timing met, WNS = +0.135 ns |
| Slice LUTs | 6,805 / 20,800 (33%) |
| Slice Registers | 8,412 / 41,600 (20%) |
| DSP48E1 | 12 (pipelined 32x32 → 64-bit multiplier) |
| LUTRAMs | 512 (4 KB data memory) |
| BRAM | 0 |
| Critical path | Gshare PHT read → PC next mux (7 logic levels, 9.87 ns) |
| Verification | **24/24** comprehensive test, 37/37 riscv-tests compliance |
| FPGA validation | Fibonacci demo over UART + LEDs at 115200 baud |

## Motivation: From 5-Stage to 6-Stage

The standard Patterson & Hennessy 5-stage pipeline (IF/ID/EX/MEM/WB) served as the starting point for this design. With the base RV32I instruction set alone, the 5-stage implementation met timing at approximately 91 MHz on the target Artix-7 fabric, with a worst negative slack of -0.938 ns at the 100 MHz constraint.

The problem emerged when extending the processor to support the M extension (hardware multiply/divide), M-mode privileged CSRs, trap handling, and a gshare branch predictor. These features converge in the execute stage: the forwarding unit must compare source register addresses against three pipeline stages, select through a multi-level mux, then feed the result into the ALU carry chain, branch comparator, CSR read path, and result selection mux, all within a single clock cycle. After place-and-route, the critical path through this logic measured **15.5 ns across 19 logic levels**, from the forwarding address comparison in the ID/EX register through the ALU output to the EX/MEM register. Timing failed with a WNS of **-5.539 ns**, limiting the design to approximately **64 MHz**.

At 64 MHz with a 100 MHz constraint, 36% of each clock period is wasted slack where the combinational logic has already settled but the clock edge hasn't arrived. More critically, the design cannot meet its own timing specification, meaning hold-time violations could cause functional failures on hardware under certain PVT (process/voltage/temperature) conditions.

The solution was to split the execute stage into two pipeline stages, following the approach used in production cores like ARM Cortex-M4 and RISC-V Ibex when targeting higher clock frequencies:

- **EX1 (Forwarding + Operand Select)**: performs the 3-source forwarding comparison and mux, selects ALU operands (rs1/PC for AUIPC, rs2/immediate for I-type), and prepares CSR write data. The output is registered into the EX1/EX2 pipeline register.
- **EX2 (ALU + Branch + CSR + MDU)**: takes the registered operands and feeds them directly into the ALU, branch unit, multiply/divide unit, and CSR unit with no preceding combinational logic.

This partitioning reduces the longest combinational path from 19 logic levels to 7, bringing the critical path delay under the 10 ns budget with 0.135 ns of positive slack. The architectural tradeoff is a deeper pipeline: branch mispredictions now incur a 3-cycle penalty (flushing IF, ID, and EX1) compared to 2 cycles in the 5-stage design. The gshare predictor with BTB and return address stack mitigates this by predicting both direction and target in the fetch stage, keeping the effective misprediction rate low enough that the IPC impact is minimal relative to the 56% frequency improvement.

## Pipeline Architecture

```
IF ──► ID ──► EX1 ──► EX2 ──► MEM ──► WB
         │      ▲       │       │       │
         │      │  forwarding   │       │
         │      └───────┴───────┘       │
         │           register file      │
         └──────────write-through───────┘
```

### IF (Instruction Fetch)

The PC feeds a 64-line direct-mapped instruction cache. Hits return combinationally; misses pull from the backing ROM and fill the line in one cycle. A three-component branch predictor runs in parallel:

- **Gshare PHT** (64 entries, 2-bit saturating counters) predicts direction by indexing with PC[7:2] XOR a 6-bit global history register
- **BTB** (32 entries, direct-mapped) supplies the predicted target address, storing tag + target + entry type (branch/JAL/call/return)
- **RAS** (4-entry circular stack) predicts return targets for JALR instructions

If the BTB hits and the PHT says taken (or the entry is a JAL/call/return), the PC redirects speculatively to the predicted target. Mispredictions are detected in EX2 and cause a 3-cycle flush.

### ID (Instruction Decode)

The instruction is decoded into control signals for all RV32IM + SYSTEM instructions. The immediate generator reassembles sign-extended immediates from all 5 RISC-V formats (I/S/B/U/J). The register file (32x32 with write-through bypass from WB) reads both source operands.

Call/return heuristics detect JAL/JALR instructions targeting link registers (x1 or x5) and push the return address onto the RAS.

### EX1 (Forwarding + Operand Select)

Three forwarding sources resolve RAW data hazards without stalling:

| Source | Distance | Data |
|--------|----------|------|
| EX2 | 1 instruction ahead | ALU result, LUI immediate, or CSR read (combinational, gated by MDU valid) |
| MEM | 2 instructions ahead | ALU result, CSR data, PC+4, or load data from dmem |
| WB | 3 instructions ahead | Final write-back value |

Priority: EX2 > MEM > WB (most recent result wins). Loads and in-progress MDU operations in EX2 are excluded from forwarding; the hazard unit stalls instead.

The forwarding mux also has a fresh register file read path with WB bypass. This handles the edge case where an instruction is stalled in EX1 for many cycles (during a multi-cycle divide) and the pipelined register file value goes stale because the source register was written by an instruction that has since left WB. Without this path, the processor would silently read an outdated value after the stall releases. This took a while to find.

After forwarding, the ALU input muxes select between the forwarded rs1/PC (for AUIPC) and forwarded rs2/immediate (for I-type). The CSR write data is also prepared here (either the forwarded rs1 value or the zero-extended zimm field for immediate CSR variants).

### EX2 (Execute)

The registered operands from EX1 feed directly into the ALU and branch unit with no preceding combinational logic, keeping this stage fast.

**ALU**: 10 operations (ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA).

**MDU** (Multiply/Divide Unit): 2-cycle pipelined multiplier for MUL/MULH/MULHSU/MULHU (operands registered on cycle 1, multiplication on cycle 2, infers 12 DSP48 blocks on Artix-7). 32-cycle iterative restoring divider for DIV/DIVU/REM/REMU with pipeline stall. Handles all edge cases per the RISC-V spec: division by zero returns quotient = -1 and remainder = dividend; signed overflow (MIN_INT / -1) returns MIN_INT with remainder 0.

**Branch unit**: evaluates all 6 branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU). Branch target = PC + immediate. JALR target = (rs1 + immediate) & ~1. Misprediction detection compares actual outcome against the prediction carried through the pipeline.

**CSR unit**: atomic read-modify-write for all 6 CSR instructions. Holds the M-mode register file (mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip) plus 64-bit performance counters (mcycle, minstret, and two custom HPM counters for branch statistics).

**Trap detection**: catches illegal instructions, ECALL, and EBREAK. On a trap: flush the pipeline (IF, ID, EX1), save PC to mepc, write cause to mcause, disable interrupts (MIE → MPIE), redirect PC to mtvec. MRET reverses the process: restore MIE from MPIE, redirect PC to mepc.

### MEM (Memory Access)

The MMIO controller routes accesses by address:

| Address Range | Peripheral |
|---------------|------------|
| `0x00000000` - `0x00000FFF` | 4 KB data RAM (byte/half/word addressable with sign extension) |
| `0x10000000` | 16-bit LED output |
| `0x10000004` | 16-bit switch input |
| `0x10000008` | UART TX data (write a byte to transmit) |
| `0x1000000C` | UART TX busy flag |

The UART runs at 115200 baud, 8N1, implemented as a shift-register transmitter with a busy-wait interface.

### WB (Write Back)

The write-back mux selects the final result for the register file:

| Condition | Source |
|-----------|--------|
| JAL / JALR | PC + 4 (return address) |
| Load | Data memory read |
| CSR instruction | CSR read value |
| Everything else | ALU result (includes LUI) |

The register file write port includes a write-through bypass: if WB writes a register in the same cycle that ID reads it, the new value is forwarded directly, avoiding a stale read.

## Hazard Handling

The hazard unit manages three types of pipeline hazards:

**Load-use**: if the instruction in EX2 is a load and the instruction in EX1 reads the same register, the data won't be available until after the memory read. The hazard unit stalls PC, IF/ID, and ID/EX1 for one cycle and flushes EX1/EX2, inserting a bubble. On the next cycle, the load data is available from MEM for forwarding.

**MDU stall**: multiply takes 2 cycles, divide takes up to 33 cycles. While the MDU is computing, the entire pipeline from EX2 back is stalled (PC, IF/ID, ID/EX1, EX1/EX2 all hold). EX2/MEM receives bubbles (suppressed control signals) to prevent intermediate results from propagating. When the MDU signals valid, the stall releases and the result is forwarded.

**Control hazards**: branch mispredictions, JAL, JALR, traps, and MRET all flush the three stages behind EX2 (IF, ID, EX1). The gshare predictor reduces misprediction frequency; the BTB eliminates the target computation penalty for correctly-predicted branches.

## M Extension

All 8 RV32M instructions are implemented in hardware:

| Instruction | Latency | Implementation |
|-------------|---------|----------------|
| MUL | 2 cycles | Pipelined: register operands on cycle 1, DSP48 multiply on cycle 2 |
| MULH | 2 cycles | Signed x signed, upper 32 bits of 64-bit product |
| MULHSU | 2 cycles | Signed x unsigned, upper 32 bits |
| MULHU | 2 cycles | Unsigned x unsigned, upper 32 bits |
| DIV | 33 cycles | Iterative restoring divider, signed, pipeline stalls |
| DIVU | 33 cycles | Iterative restoring divider, unsigned |
| REM | 33 cycles | Remainder from signed division |
| REMU | 33 cycles | Remainder from unsigned division |

The multiplier is pipelined to enable clean DSP48 inference on Artix-7. Each DSP48E1 block handles a 25x18 signed multiply natively; a full 32x32 → 64-bit multiply is decomposed across multiple blocks. The divider uses a standard restoring algorithm: shift the dividend left one bit per cycle, trial-subtract the divisor, and build up the quotient bit by bit. Signed division takes absolute values of both operands, divides unsigned, then negates the result based on the original signs.

Division by zero is handled per the RISC-V spec without trapping: quotient = all ones (-1 signed), remainder = the dividend. Signed overflow (0x80000000 / -1) returns 0x80000000 with remainder 0.

## Privileged Architecture

The processor implements M-mode (machine mode) from the RISC-V Privileged Specification:

| CSR | Address | Function |
|-----|---------|----------|
| mstatus | 0x300 | Global interrupt enable (MIE), previous interrupt enable (MPIE) |
| mie | 0x304 | Per-source interrupt enable mask |
| mtvec | 0x305 | Trap vector base address |
| mscratch | 0x340 | Scratch register for trap handler use |
| mepc | 0x341 | PC of the instruction that caused the trap |
| mcause | 0x342 | Trap cause code |
| mtval | 0x343 | Additional trap information (faulting instruction/address) |
| mip | 0x344 | Pending interrupts |

All 6 CSR instructions are supported: CSRRW, CSRRS, CSRRC (register operand) and CSRRWI, CSRRSI, CSRRCI (5-bit zero-extended immediate). ECALL, EBREAK, and MRET are fully implemented with correct pipeline flushing and state save/restore.

## Performance Counters

Four 64-bit hardware counters tick automatically and are readable via CSR instructions:

| Counter | CSR Address | What it counts |
|---------|-------------|----------------|
| mcycle | 0xB00 / 0xB80 | Clock cycles since reset |
| minstret | 0xB02 / 0xB82 | Instructions retired (committed at MEM stage) |
| mhpmcounter3 | 0xB03 / 0xB83 | Branch mispredictions |
| mhpmcounter4 | 0xB04 / 0xB84 | Total branches executed |

These enable IPC measurement and predictor tuning from software:

```c
unsigned int c0, c1, i0, i1;
asm volatile("csrr %0, mcycle" : "=r"(c0));
asm volatile("csrr %0, minstret" : "=r"(i0));
// ... workload ...
asm volatile("csrr %0, mcycle" : "=r"(c1));
asm volatile("csrr %0, minstret" : "=r"(i1));
// IPC = (i1 - i0) / (c1 - c0)
```

## Verification

The processor is tested at four levels, from unit to system:

| Level | Testbench | What it covers | Result |
|-------|-----------|----------------|--------|
| 1 | `rv32i_tb.sv` | Single-cycle reference: every instruction in isolation | PASS |
| 2 | `rv32i_pipeline_tb.sv` | Pipeline correctness: sum 1-to-10, exercises forwarding, load-use stalls, branch misprediction. Expected: x1 = x5 = 55, mem[0] = 55 | PASS |
| 3 | `rv32i_comprehensive_tb.sv` | 24-point test covering M-ext (all 8 ops + edge cases), all 6 CSR instructions, trap handling (ecall → handler → mret → resume), performance counters, and pipeline hazard forwarding from mul to dependent add. Automated PASS/FAIL with summary | **24/24 PASS** |
| 4 | `rv32i_riscv_tests_tb.sv` | Official riscv-tests compliance suite: 37 rv32ui-p-* tests covering every RV32I instruction with corner cases | PASS |

The comprehensive test (level 3) is designed to catch the subtle bugs that simple tests miss:

- **Divide-by-zero and signed overflow**: verifies the MDU returns spec-compliant results for 7/0, MIN_INT/-1
- **CSR read-modify-write atomicity**: writes 0xDEADBEEF to mscratch, reads it back, then chains CSRRS → CSRRC → CSRRWI → CSRRSI → CSRRCI, verifying each intermediate value
- **Trap round-trip**: sets mtvec, triggers ecall, handler reads mcause (expects 11), advances mepc past the ecall, executes mret, verifies execution resumes at the correct PC
- **Forwarding under stall**: multiply followed by an immediately dependent add, verifying EX2 → EX1 forwarding produces the correct result even with MDU pipeline latency

A GitHub Actions CI workflow runs the pipeline and comprehensive testbenches on every push using Icarus Verilog.

## FPGA Demo

The instruction ROM ships with a precompiled Fibonacci program. When deployed on the Basys 3:

- The serial terminal (115200 baud) prints F(0) through F(19) as each value is computed
- The LEDs show the lower 16 bits of the current Fibonacci number
- After completion, LEDs hold F(19) = 4181 = 0x1055 (LEDs 0, 2, 4, 6, 12 lit)
- Pressing the center button resets the processor and reruns the program

A separate `perf_report.c` program (compilable with the RISC-V toolchain) runs the same Fibonacci workload and then prints cycle count, instruction count, IPC, total branches, mispredictions, and mispredict rate over UART.

## Building

### Vivado Simulation

```
cd <project-dir>
source create_project.tcl
set_property top rv32i_comprehensive_tb [get_filesets sim_1]
launch_simulation
run 2ms
```

### Compiling C Programs

Requires the xPack RISC-V GCC toolchain ([download](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases)).

```
cd programs/c
make fibonacci
make perf_report
```

Programs compile with `-march=rv32im_zicsr`, generating hardware multiply/divide and CSR instructions.

### FPGA Deployment

1. Open the project in Vivado (`source create_project.tcl`)
2. Ensure `fpga_top` is the synthesis top
3. Run synthesis, implementation, and generate bitstream
4. Program the Basys 3 over JTAG
5. Open a serial terminal at 115200 baud on the FPGA's COM port
6. Press the center button to reset and run

### Running riscv-tests

```
git clone https://github.com/riscv-software-src/riscv-tests
cd riscv-tests && git submodule update --init --recursive
autoconf && ./configure --prefix=$PWD/install && make && make install
cd <project-dir>
bash tools/run_riscv_tests.sh ./riscv-tests
```

## File Structure

```
rtl/
  pkg_riscv.sv                type definitions, opcodes, CSR addresses, exception codes
  pc.sv                       program counter with write enable
  imem.sv                     instruction ROM (1024 x 32, preloaded with fibonacci)
  icache.sv                   64-line direct-mapped instruction cache
  regfile.sv                  32x32 register file with write-through bypass
  control.sv                  main decoder for RV32IM + SYSTEM instructions
  imm_gen.sv                  immediate extraction for all 5 RISC-V formats
  alu.sv                      10-operation arithmetic/logic unit
  mdu.sv                      pipelined multiplier + iterative divider (RV32M)
  csr_unit.sv                 M-mode CSR register file with performance counters
  branch_unit.sv              6-condition branch evaluator
  branch_predictor.sv         gshare PHT + direct-mapped BTB + return address stack
  forwarding_unit.sv          3-source RAW hazard forwarding (EX2, MEM, WB)
  hazard_unit.sv              stall/flush control for 6-stage pipeline
  pipe_if_id.sv               IF/ID pipeline register (with stall + flush)
  pipe_id_ex.sv               ID/EX1 pipeline register (with stall + flush)
  pipe_ex1_ex2.sv             EX1/EX2 pipeline register (with stall + flush)
  pipe_ex_mem.sv              EX2/MEM pipeline register
  pipe_mem_wb.sv              MEM/WB pipeline register
  mmio.sv                     memory-mapped I/O controller (RAM + LEDs + switches + UART)
  dmem.sv                     4 KB data memory (byte/half/word with sign extension)
  uart_tx.sv                  115200 baud 8N1 UART transmitter
  rv32i_top.sv                single-cycle reference implementation
  rv32i_pipeline_top.sv       6-stage pipelined processor (simulation)
  rv32i_pipeline_mmio_top.sv  6-stage pipelined processor with MMIO (FPGA)
  fpga_top.sv                 FPGA wrapper with reset synchronizer

tb/
  rv32i_tb.sv                 single-cycle testbench
  rv32i_pipeline_tb.sv        pipeline testbench (sum 1-to-10)
  rv32i_comprehensive_tb.sv   24-point comprehensive test (M-ext, CSR, traps, hazards)
  rv32i_mext_csr_tb.sv        targeted M-extension + CSR test
  rv32i_riscv_tests_tb.sv     riscv-tests compliance harness

programs/asm/
  sum_1_to_10.s               forwarding + branch validation program
  test_mext_csr.s             M-extension + CSR test program
  test_comprehensive.s        full-coverage test (hand-encoded with verified hex)

programs/c/
  Makefile                    cross-compilation for rv32im_zicsr
  link.ld                     linker script (ROM 0x0000-0x0FFF, stack at top)
  start.s                     bare-metal startup (set SP, call main, halt)
  mmio.h                      hardware register definitions and UART drivers
  fibonacci.c                 Fibonacci sequence with UART + LED output
  bubble_sort.c               array sort with UART output
  perf_report.c               runs fibonacci then prints IPC and branch stats

constraints/
  basys3.xdc                  Basys 3 pin assignments (100 MHz clock, LEDs, switches, UART TX)

tools/
  hex_disasm.py               hex-to-assembly disassembler
  run_riscv_tests.sh          automated riscv-tests runner

.github/workflows/
  sim.yml                     CI: runs pipeline + comprehensive testbenches on every push
```

## References

- Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition*
- [The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA](https://riscv.org/specifications/)
- [The RISC-V Instruction Set Manual, Volume II: Privileged Architecture](https://riscv.org/specifications/privileged-isa/)
- [riscv-tests](https://github.com/riscv-software-src/riscv-tests) (official ISA compliance suite)
- McFarling, "Combining Branch Predictors" (WRL Technical Note TN-36, 1993)
- Hennessy & Patterson, *Computer Architecture: A Quantitative Approach* (forwarding and hazard analysis)

## License

MIT
