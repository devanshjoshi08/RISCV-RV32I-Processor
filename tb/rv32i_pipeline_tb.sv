`timescale 1ns / 1ps

module rv32i_pipeline_tb;

  logic clk, rst_n;
  logic [31:0] debug_pc, debug_instr, debug_alu_result;

  rv32i_pipeline_top dut (.*);

  initial clk = 0;
  always #5 clk = ~clk;

  // halt detection: jal x0,0 makes the PC cycle through 3 values
  // in the pipeline, so we check if the PC repeats within a window
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
      $display("  PASS: x%0d = %0d", r, got);
    else
      $display("  FAIL: x%0d = %0d, expected %0d", r, got, exp);
  endtask

  task automatic check_mem(input int addr, input int exp);
    logic [31:0] got;
    got = dut.u_dmem.mem[addr];
    if (got == exp[31:0])
      $display("  PASS: mem[%0d] = %0d", addr, got);
    else
      $display("  FAIL: mem[%0d] = %0d, expected %0d", addr, got, exp);
  endtask

  initial begin
    $display("=== Pipeline TB ===");
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;

    $display("Running...");
    fork
      wait (halt_count > 10);
      repeat (500) @(posedge clk);
    join_any
    repeat (5) @(posedge clk);

    $display("  Halted at PC = 0x%08h", debug_pc);
    $display("");
    check_reg(1, 55);
    check_reg(2, 11);
    check_reg(3, 11);
    check_reg(5, 55);
    check_mem(0, 55);

    $display("");
    for (int i = 0; i < 32; i++)
      if (dut.u_regfile.regs[i] != 0)
        $display("  x%0d = %0d (0x%08h)", i, dut.u_regfile.regs[i], dut.u_regfile.regs[i]);

    $display("=== Done ===");
    $finish;
  end

  initial begin
    #200000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
