# RISC-V RV32I Pipelined Processor

5-stage pipelined RISC-V processor in SystemVerilog targeting the Basys 3 FPGA. Executes all 40 RV32I base integer instructions, handles data hazards through forwarding and stalling, predicts branches with a 64-entry BHT, and includes a direct-mapped instruction cache. Runs C programs compiled with a standard RISC-V GCC toolchain with UART serial output and LED display on the FPGA.

Validated against the official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) suite (37 RV32I tests). Deployed and tested on real hardware.

**Author:** Devansh Joshi

## Synthesis (Artix-7 XC7A35T, Vivado 2025.2)

After place-and-route with the fibonacci demo program embedded:

- **~91 MHz** (WNS = -0.938 ns at 100 MHz constraint, critical path through forwarding mux -> branch comparator -> PC next)
- **~2,500 LUTs** out of 20,800
- **~3,300 flip-flops** out of 41,600
- **512 LUTRAMs** for the data memory
- No BRAM used

The instruction cache takes up the most area (~700 LUTs, ~2,500 FFs for 64 tag+valid+data entries). The BHT is cheap at ~170 LUTs.

## Architecture

The pipeline follows the textbook 5-stage split from Patterson & Hennessy: Fetch, Decode, Execute, Memory, Writeback. Each stage is separated by a pipeline register that latches the relevant signals on the clock edge.

### Instruction fetch

The PC feeds into a 64-line direct-mapped instruction cache. On a hit, the instruction comes back combinationally. On a miss, the cache pulls from the backing ROM and fills the line. A branch history table (64 entries, 2-bit saturating counters indexed by PC[7:2]) predicts whether the current instruction is a taken branch. If the BHT says "taken," the PC speculatively jumps to the branch target.

### Decode

The instruction gets cracked into its fields (opcode, funct3, funct7, rs1, rs2, rd). The control unit generates all the datapath signals. The immediate generator reassembles and sign-extends the immediate from whichever of the 5 RISC-V formats the instruction uses. Meanwhile, the register file reads rs1 and rs2.

The register file includes a write-through bypass. If writeback is writing to a register in the exact same cycle that decode is reading it, the regfile forwards the write data directly instead of returning the stale value. This was originally a bug where the third instruction in a dependent sequence would silently read a register that hadn't been committed yet, and the bypass turned out to be the cleanest fix.

### Execute

The forwarding muxes check whether either source register matches the destination of an instruction currently in the MEM or WB stage, and if so, grab the result directly instead of using the outdated register file output. Three forwarding paths:

- **EX-EX**: the instruction right ahead just computed the needed operand
- **MEM-EX**: the instruction two ahead computed it
- **WB-ID**: handled by the register file bypass described above

The ALU does the computation (add, sub, shifts, comparisons, etc.), and the branch unit evaluates whether a branch should be taken. If the BHT predicted wrong, the hazard unit flushes the two instructions behind in the pipeline, a 2-cycle penalty.

For load-use hazards (where the instruction right after a load needs the loaded value), forwarding can't help because the data hasn't come out of memory yet. The hazard unit detects this and stalls the pipeline for one cycle, inserting a bubble.

### Memory

Loads and stores hit the memory-mapped I/O controller, which routes accesses based on the address:

| Address | Peripheral |
|---|---|
| `0x00000000` - `0x00000FFF` | Data RAM |
| `0x10000000` | LEDs |
| `0x10000004` | Switches |
| `0x10000008` | UART TX data |
| `0x1000000C` | UART TX busy flag |

The UART runs at 115200 baud, 8N1. Writing a byte to the UART data register kicks off a transmission.

### Writeback

The write-back mux picks between the ALU result, memory read data, the upper immediate (for LUI), or PC+4 (for JAL/JALR return addresses), and writes it back to the register file.

## Design Decisions

**Forwarding over stalling**: Back-to-back dependent instructions are everywhere in compiled code. Stalling on every RAW dependency would waste 1-2 cycles each time. Forwarding eliminates the penalty for everything except load-use, which still needs a 1-cycle stall since the data isn't available until memory responds.

**BHT over static prediction**: With static predict-not-taken, a 10-iteration loop wastes 20 cycles (2 per taken branch). The BHT learns the pattern after a couple iterations and only mispredicts on entry and exit, dropping the penalty to ~4 cycles. It costs ~170 LUTs.

**Branches resolve in EX, not ID**: Resolving in ID would cut the misprediction penalty to 1 cycle, but it means the branch operands need to be available in the decode stage. That would require adding forwarding paths to ID, complicating the critical path. Keeping resolution in EX is simpler and the BHT makes up for the extra cycle most of the time.

**Direct-mapped cache**: A set-associative cache would have better hit rates, but for the small programs running on this core, a direct-mapped cache with 64 lines covers the working set fine. It's already the most expensive module in the design.

## Verification

Three levels of testing:

1. **Single-cycle testbench** (`rv32i_tb.sv`) -- runs each instruction without pipelining to verify correctness in isolation
2. **Pipeline testbench** (`rv32i_pipeline_tb.sv`) -- runs a sum-1-to-10 program that exercises all hazard cases (forwarding, stalls, branch misprediction). Expected result: x1 = x5 = 55, mem[0] = 55
3. **riscv-tests compliance** (`rv32i_riscv_tests_tb.sv`) -- runs all 37 official rv32ui-p-* tests covering every RV32I instruction with corner cases (overflow, x0 behavior, boundary values, etc.)

The runner script (`tools/run_riscv_tests.sh`) automates all 37 tests and reports pass/fail.

## FPGA Demo

The default program embedded in the instruction ROM computes 20 Fibonacci numbers. When programmed onto the Basys 3:

- The serial terminal (115200 baud) outputs the computed values as they're calculated
- The LEDs display the lower 16 bits of each Fibonacci number
- After completion, the LEDs hold F(19) = 4181 = 0x1055 (LEDs 0, 2, 4, 6, 12 on)
- Pressing the center button resets and reruns the program

## Building

### Simulation

```
cd <project-dir>
source create_project.tcl
launch_simulation
run 200us
```

### Compiling C programs

Requires `riscv32-unknown-elf-gcc` ([xpack toolchain](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases)).

```
cd programs/c
make bubble_sort
make fibonacci
```

Copy the `.hex` file to the sim directory as `program.hex` and relaunch.

### Running riscv-tests

```
git clone https://github.com/riscv-software-src/riscv-tests
cd riscv-tests && git submodule update --init --recursive
autoconf && ./configure --prefix=$PWD/install && make && make install
cd <project-dir>
bash tools/run_riscv_tests.sh ./riscv-tests
```

### FPGA deployment

1. Set `fpga_top` as synthesis top
2. Synthesize, implement, generate bitstream
3. Program the Basys 3
4. Open a serial terminal at 115200 baud on the FPGA's COM port
5. Press center button to reset and rerun

## Files

```
rtl/
  pkg_riscv.sv                opcodes and type definitions
  pc.sv                       program counter
  imem.sv                     instruction ROM
  regfile.sv                  register file with write-through bypass
  alu.sv                      arithmetic/logic unit
  imm_gen.sv                  immediate extraction
  control.sv                  main decoder
  branch_unit.sv              branch condition evaluation
  branch_predictor.sv         64-entry BHT
  icache.sv                   direct-mapped instruction cache
  dmem.sv                     data memory (byte/half/word)
  pipe_if_id.sv               IF/ID pipeline register
  pipe_id_ex.sv               ID/EX pipeline register
  pipe_ex_mem.sv              EX/MEM pipeline register
  pipe_mem_wb.sv              MEM/WB pipeline register
  forwarding_unit.sv          RAW hazard forwarding
  hazard_unit.sv              stall and flush control
  rv32i_top.sv                single-cycle version (for debug)
  rv32i_pipeline_top.sv       pipelined version (simulation)
  rv32i_pipeline_mmio_top.sv  pipelined version with MMIO (FPGA)
  mmio.sv                     memory-mapped I/O
  uart_tx.sv                  UART transmitter
  fpga_top.sv                 FPGA top wrapper

tb/
  rv32i_tb.sv                 single-cycle testbench
  rv32i_pipeline_tb.sv        pipeline testbench
  rv32i_riscv_tests_tb.sv     riscv-tests testbench

programs/asm/
  sum_1_to_10.s               validation program
  sum_1_to_10.hex             pre-assembled hex

programs/c/
  Makefile                    builds C to hex
  link.ld                     linker script
  start.s                     startup code
  mmio.h                      hardware register definitions
  bubble_sort.c               sorts an array, prints over UART
  fibonacci.c                 Fibonacci sequence on UART + LEDs

constraints/
  basys3.xdc                  FPGA pin assignments

tools/
  hex_disasm.py               hex-to-assembly disassembler
  run_riscv_tests.sh          riscv-tests runner
```

## References

- Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition*
- [RISC-V ISA spec](https://riscv.org/specifications/)
- [riscv-tests](https://github.com/riscv-software-src/riscv-tests)
- [Bruno Levy's learn-fpga](https://github.com/BrunoLevy/learn-fpga)

## License

MIT
