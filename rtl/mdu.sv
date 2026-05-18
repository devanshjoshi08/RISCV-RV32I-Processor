// multiply/divide unit: 2-cycle pipelined multiply (DSP48 friendly),
// iterative 32-cycle restoring divider.

import pkg_riscv::*;

module mdu (
  input  logic        clk, rst_n,
  input  logic        start,
  input  mdu_op_t     op,
  input  logic [31:0] rs1, rs2,
  output logic [31:0] result,
  output logic        busy,
  output logic        valid
);

  // pipelined multiply: register inputs on cycle 1, result on cycle 2.
  // lets Vivado infer DSP48 blocks with registered I/O.
  logic signed [31:0] mul_a_reg;
  logic signed [32:0] mul_b_su_reg; // 33-bit for mulhsu (unsigned rs2)
  logic        [31:0] mul_b_uu_reg;
  logic [2:0]         mul_op_reg;
  logic               mul_active;

  logic signed [63:0] mul_ss_out;
  logic signed [63:0] mul_su_out;
  logic        [63:0] mul_uu_out;
  logic               mul_valid;
  logic [2:0]         mul_op_out;

  // stage 1: register operands
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mul_a_reg <= 0;
      mul_b_su_reg <= 0;
      mul_b_uu_reg <= 0;
      mul_op_reg <= 0;
      mul_active <= 0;
    end else begin
      mul_active <= start && (op <= MDU_MULHU);
      mul_a_reg  <= $signed(rs1);
      mul_b_su_reg <= $signed({1'b0, rs2});
      mul_b_uu_reg <= rs2;
      mul_op_reg <= op;
    end
  end

  // stage 2: compute + register result
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mul_ss_out <= 0;
      mul_su_out <= 0;
      mul_uu_out <= 0;
      mul_valid  <= 0;
      mul_op_out <= 0;
    end else begin
      mul_ss_out <= mul_a_reg * $signed(mul_b_uu_reg);
      mul_su_out <= mul_a_reg * mul_b_su_reg;
      mul_uu_out <= {32'b0, $unsigned(mul_a_reg)} * {32'b0, mul_b_uu_reg};
      mul_valid  <= mul_active;
      mul_op_out <= mul_op_reg;
    end
  end

  // divider FSM
  typedef enum logic [1:0] { DIV_IDLE, DIV_RUN, DIV_DONE } div_state_t;
  div_state_t state;

  logic [4:0]  count;
  logic [31:0] dividend, divisor_reg;
  logic [31:0] quotient, remainder;
  logic        div_signed, rem_op;
  logic        negate_quot, negate_rem;

  logic [32:0] sub_result;
  assign sub_result = {remainder, dividend[31]} - {1'b0, divisor_reg};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= DIV_IDLE;
      count <= 0;
      dividend <= 0;
      divisor_reg <= 0;
      quotient <= 0;
      remainder <= 0;
      negate_quot <= 0;
      negate_rem <= 0;
      div_signed <= 0;
      rem_op <= 0;
    end else begin
      case (state)
        DIV_IDLE: begin
          if (start && (op == MDU_DIV || op == MDU_DIVU ||
                        op == MDU_REM || op == MDU_REMU)) begin
            div_signed <= (op == MDU_DIV || op == MDU_REM);
            rem_op <= (op == MDU_REM || op == MDU_REMU);

            if (rs2 == 0) begin
              quotient <= 32'hFFFFFFFF;
              remainder <= rs1;
              state <= DIV_DONE;
            end else begin
              if ((op == MDU_DIV || op == MDU_REM) && rs1[31])
                dividend <= -rs1;
              else
                dividend <= rs1;

              if ((op == MDU_DIV || op == MDU_REM) && rs2[31])
                divisor_reg <= -rs2;
              else
                divisor_reg <= rs2;

              negate_quot <= (op == MDU_DIV) && (rs1[31] ^ rs2[31]);
              negate_rem  <= (op == MDU_REM) && rs1[31];
              quotient <= 0;
              remainder <= 0;
              count <= 31;
              state <= DIV_RUN;
            end
          end
        end

        DIV_RUN: begin
          if (!sub_result[32]) begin
            remainder <= sub_result[31:0];
            quotient <= {quotient[30:0], 1'b1};
          end else begin
            remainder <= {remainder[30:0], dividend[31]};
            quotient <= {quotient[30:0], 1'b0};
          end
          dividend <= {dividend[30:0], 1'b0};

          if (count == 0)
            state <= DIV_DONE;
          else
            count <= count - 1;
        end

        DIV_DONE: begin
          state <= DIV_IDLE;
        end

        default: state <= DIV_IDLE;
      endcase
    end
  end

  logic [31:0] div_result;
  always_comb begin
    if (rem_op)
      div_result = negate_rem ? -remainder : remainder;
    else
      div_result = negate_quot ? -quotient : quotient;
  end

  // output mux
  logic [31:0] mul_result;
  always_comb begin
    case (mul_op_out)
      MDU_MUL:    mul_result = mul_ss_out[31:0];
      MDU_MULH:   mul_result = mul_ss_out[63:32];
      MDU_MULHSU: mul_result = mul_su_out[63:32];
      MDU_MULHU:  mul_result = mul_uu_out[63:32];
      default:    mul_result = 0;
    endcase
  end

  always_comb begin
    if (mul_valid) begin
      result = mul_result;
      valid = 1;
    end else if (state == DIV_DONE) begin
      result = div_result;
      valid = 1;
    end else begin
      result = 0;
      valid = 0;
    end
  end

  assign busy = (state != DIV_IDLE) || mul_active;

endmodule
