// compatible with riscv-tests: x3 = 1 means pass, x3 >> 1 = failing test #
`timescale 1ns / 1ps

module rv32i_riscv_tests_tb;

  logic clk, rst_n;
  logic [31:0] debug_pc, debug_instr, debug_alu_result;

  rv32i_pipeline_top dut (.*);

  initial clk = 0;
  always #5 clk = ~clk;

  logic [31:0] gp_value;
  logic [31:0] prev_pc;
  int same_pc_count;
  logic test_done;

  assign gp_value = dut.u_regfile.regs[3];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      prev_pc <= 32'hFFFF;
      same_pc_count <= 0;
      test_done <= 0;
    end else begin
      if (debug_pc == prev_pc ||
          (debug_pc == prev_pc + 4 && debug_instr == 32'h0000006f))
        same_pc_count <= same_pc_count + 1;
      else
        same_pc_count <= 0;
      prev_pc <= debug_pc;

      if (same_pc_count > 20 && !test_done)
        test_done <= 1;
      if (debug_instr == 32'h00000073 && !test_done) // ecall
        test_done <= 1;
    end
  end

  initial begin
    $display("=== riscv-tests ===");
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;

    fork
      wait (test_done);
      repeat (10000) @(posedge clk);
    join_any
    repeat (10) @(posedge clk);

    if (gp_value == 1)
      $display("PASS");
    else if (gp_value == 0)
      $display("FAIL: test did not complete");
    else
      $display("FAIL: test %0d (gp = 0x%08h)", gp_value >> 1, gp_value);

    for (int i = 0; i < 32; i++)
      if (dut.u_regfile.regs[i] != 0)
        $display("  x%0d = 0x%08h", i, dut.u_regfile.regs[i]);

    $finish;
  end

  initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule
