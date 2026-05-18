import pkg_riscv::*;

module control (
  input logic [6:0] opcode,
  input logic [2:0] funct3,
  input logic [6:0] funct7,
  input logic [11:0] funct12,
  output logic reg_write,
  output logic mem_read,
  output logic mem_write,
  output logic mem_to_reg,
  output logic alu_src,
  output logic branch,
  output logic jal,
  output logic jalr,
  output logic lui,
  output logic auipc,
  output imm_type_t imm_type,
  output alu_op_t alu_op,
  output logic is_mext,
  output mdu_op_t mdu_op,
  output csr_op_t csr_op,
  output logic csr_zimm,
  output logic is_ecall,
  output logic is_ebreak,
  output logic is_mret,
  output logic illegal_instr
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
    is_mext = 0;
    mdu_op = MDU_MUL;
    csr_op = CSR_NONE;
    csr_zimm = 0;
    is_ecall = 0;
    is_ebreak = 0;
    is_mret = 0;
    illegal_instr = 0;

    case (opcode)
      OP_REG: begin
        reg_write = 1;
        if (funct7 == 7'b0000001) begin
          // M extension
          is_mext = 1;
          mdu_op = mdu_op_t'(funct3);
        end else begin
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

      OP_FENCE: begin
        // NOP for single-core in-order pipeline
      end

      OP_SYSTEM: begin
        if (funct3 == 3'b000) begin
          // ecall / ebreak / mret
          case (funct12)
            12'h000: is_ecall  = 1;
            12'h001: is_ebreak = 1;
            12'h302: is_mret   = 1;
            default: illegal_instr = 1;
          endcase
        end else begin
          // CSR instructions
          reg_write = 1;
          case (funct3)
            3'b001: csr_op = CSR_RW; // CSRRW
            3'b010: csr_op = CSR_RS; // CSRRS
            3'b011: csr_op = CSR_RC; // CSRRC
            3'b101: begin csr_op = CSR_RW; csr_zimm = 1; end // CSRRWI
            3'b110: begin csr_op = CSR_RS; csr_zimm = 1; end // CSRRSI
            3'b111: begin csr_op = CSR_RC; csr_zimm = 1; end // CSRRCI
            default: illegal_instr = 1;
          endcase
        end
      end

      default: begin
        illegal_instr = 1;
      end
    endcase
  end

endmodule
