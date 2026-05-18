`timescale 1ns / 1ps

// tests M extension (mul/div) and CSR read/write/trap handling.
// loads programs/asm/test_mext_csr.hex

module rv32i_mext_csr_tb;

  logic clk, rst_n;
  logic [31:0] debug_pc, debug_instr, debug_alu_result;

  rv32i_pipeline_top dut (.*);

  initial clk = 0;
  always #5 clk = ~clk;

  logic [31:0] pc_hist [0:3];
  int halt_count;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      halt_count <= 0;
      pc_hist[0] <= 32'hFFFF; pc_hist[1] <= 32'hFFFE;
      pc_hist[2] <= 32'hFFFD; pc_hist[3] <= 32'hFFFC;
    end else begin
      pc_hist[3] <= pc_hist[2]; pc_hist[2] <= pc_hist[1];
      pc_hist[1] <= pc_hist[0]; pc_hist[0] <= debug_pc;
      if (debug_pc == pc_hist[2] || debug_pc == pc_hist[3])
        halt_count <= halt_count + 1;
      else
        halt_count <= 0;
    end
  end

  task automatic check_reg(input int r, input int exp);
    logic [31:0] got;
    got = dut.u_regfile.regs[r];
    if (got == exp[31:0])
      $display("  PASS: x%0d = 0x%08h", r, got);
    else
      $display("  FAIL: x%0d = 0x%08h, expected 0x%08h", r, got, exp);
  endtask

  initial begin
    $display("M-extension + CSR testbench");
    rst_n = 0;

    // load test program into instruction memory
    for (int i = 0; i < 1024; i++)
      dut.u_imem.mem[i] = 32'h00000013; // NOP
    $readmemh("test_mext_csr.hex", dut.u_imem.mem);

    repeat (5) @(posedge clk);
    rst_n = 1;

    fork
      wait (halt_count > 50); // must be > 33 (divider latency)
      repeat (5000) @(posedge clk);
    join_any
    repeat (5) @(posedge clk);

    $display("  Halted at PC = 0x%08h", debug_pc);
    $display("");

    // expected results from test_mext_csr.s:
    // x10 = 7*13 = 91
    check_reg(10, 91);
    // x11 = 91/7 = 13
    check_reg(11, 13);
    // x12 = 91%7 = 0
    check_reg(12, 0);
    // x13 = (-6)*5 = -30
    check_reg(13, -30);
    // x14 = mcycle snapshot (nonzero)
    if (dut.u_regfile.regs[14] != 0)
      $display("  PASS: x14 (mcycle) = %0d (nonzero)", dut.u_regfile.regs[14]);
    else
      $display("  FAIL: x14 (mcycle) = 0");
    // x15 = mscratch readback = 0xDEADBEEF
    check_reg(15, 32'hDEADBEEF);

    $display("");
    $display("CSR unit state:");
    $display("  mcycle   = %0d", dut.u_csr.mcycle);
    $display("  minstret = %0d", dut.u_csr.minstret);
    $display("  branches = %0d", dut.u_csr.hpmcnt4);
    $display("  mispred  = %0d", dut.u_csr.hpmcnt3);

    $display("");
    $display("done");
    $finish;
  end

  initial begin
    #500000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
