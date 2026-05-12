`timescale 1ns / 1ps

module rv32i_tb;

  logic clk, rst_n;
  logic [31:0] debug_pc, debug_instr, debug_alu_result;

  rv32i_top dut (.*);

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic check_reg(input int r, input int exp);
    logic [31:0] got;
    got = dut.u_regfile.regs[r];
    if (got == exp[31:0])
      $display("  PASS: x%0d = %0d (0x%08h)", r, got, got);
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
    $display("=== Single-Cycle TB ===");
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    repeat (200) begin
      @(posedge clk);
      $display("  PC=0x%08h  INSTR=0x%08h", debug_pc, debug_instr);
    end

    $display("");
    for (int i = 0; i < 32; i++)
      if (dut.u_regfile.regs[i] != 0)
        $display("  x%0d = %0d (0x%08h)", i, dut.u_regfile.regs[i], dut.u_regfile.regs[i]);

    $display("=== Done ===");
    $finish;
  end

  initial begin
    #100000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
