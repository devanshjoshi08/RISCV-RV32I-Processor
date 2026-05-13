import pkg_riscv::*;

module control (
  input logic [6:0] opcode,
  input logic [2:0] funct3,
  input logic [6:0] funct7,
  output logic reg_write,
  output logic mem_read,
  output logic mem_write,
  output logic mem_to_reg, // 1 = load data -> rd
  output logic alu_src,    // 0 = rs2, 1 = imm
  output logic branch,
  output logic jal,
  output logic jalr,
  output logic lui,
  output logic auipc,
  output imm_type_t imm_type,
  output alu_op_t alu_op
);

  always_comb begin
    reg_write = 0;
    mem_read = 0;
    mem_write = 0;
    mem_to_reg = 0;
    alu_src = 0;
    branch = 0;
    jal = 0;
    jalr = 0;
    lui = 0;
    auipc = 0;
    imm_type = IMM_I;
    alu_op = ALU_ADD;

    case (opcode)
      OP_REG: begin
        reg_write = 1;
        case (funct3)
          3'b000: alu_op = (funct7[5]) ? ALU_SUB : ALU_ADD;
          3'b001: alu_op = ALU_SLL;
          3'b010: alu_op = ALU_SLT;
          3'b011: alu_op = ALU_SLTU;
          3'b100: alu_op = ALU_XOR;
          3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
          3'b110: alu_op = ALU_OR;
          3'b111: alu_op = ALU_AND;
          default: alu_op = ALU_ADD;
        endcase
      end

      OP_IMM: begin
        reg_write = 1;
        alu_src = 1;
        imm_type = IMM_I;
        case (funct3)
          3'b000: alu_op = ALU_ADD;
          3'b001: alu_op = ALU_SLL;
          3'b010: alu_op = ALU_SLT;
          3'b011: alu_op = ALU_SLTU;
          3'b100: alu_op = ALU_XOR;
          3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
          3'b110: alu_op = ALU_OR;
          3'b111: alu_op = ALU_AND;
          default: alu_op = ALU_ADD;
        endcase
      end

      OP_LOAD: begin
        reg_write = 1;
        mem_read = 1;
        mem_to_reg = 1;
        alu_src = 1;
        imm_type = IMM_I;
        alu_op = ALU_ADD;
      end

      OP_STORE: begin
        mem_write = 1;
        alu_src = 1;
        imm_type = IMM_S;
        alu_op = ALU_ADD;
      end

      OP_BRANCH: begin
        branch = 1;
        imm_type = IMM_B;
        alu_op = ALU_SUB;
      end

      OP_JAL: begin
        reg_write = 1;
        jal = 1;
        imm_type = IMM_J;
      end

      OP_JALR: begin
        reg_write = 1;
        jalr = 1;
        alu_src = 1;
        imm_type = IMM_I;
        alu_op = ALU_ADD;
      end

      OP_LUI: begin
        reg_write = 1;
        lui = 1;
        imm_type = IMM_U;
      end

      OP_AUIPC: begin
        reg_write = 1;
        auipc = 1;
        alu_src = 1;
        imm_type = IMM_U;
      end

      default: begin end
    endcase
  end

endmodule
