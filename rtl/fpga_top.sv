module fpga_top (
  input logic clk,
  input logic rst_btn,      // basys 3 buttons are active-high
  input logic [15:0] switches,
  output logic [15:0] leds,
  output logic uart_tx
);

  // invert the button since everything internally uses active-low reset
  logic rst_n;
  assign rst_n = ~rst_btn;

  // 2-stage reset synchronizer
  logic rst_sync_0, rst_sync_1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_sync_0 <= 0;
      rst_sync_1 <= 0;
    end else begin
      rst_sync_0 <= 1;
      rst_sync_1 <= rst_sync_0;
    end
  end
  logic sys_rst_n;
  assign sys_rst_n = rst_sync_1;

  logic uart_start, uart_busy;
  logic [7:0] uart_din;
  logic [31:0] debug_pc, debug_instr, debug_alu_result;

  (* dont_touch = "true" *) rv32i_pipeline_mmio_top u_cpu (
    .clk(clk), .rst_n(sys_rst_n),
    .switches(switches), .leds(leds),
    .uart_start(uart_start), .uart_din(uart_din), .uart_busy(uart_busy),
    .debug_pc(debug_pc), .debug_instr(debug_instr),
    .debug_alu_result(debug_alu_result)
  );

  uart_tx u_uart (
    .clk(clk), .rst_n(sys_rst_n),
    .start(uart_start), .din(uart_din),
    .tx(uart_tx), .busy(uart_busy)
  );

endmodule
