// single-cycle version, kept around for testing
import pkg_riscv::*;

module rv32i_top (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] debug_pc,       // for testbench / FPGA observation
    output logic [31:0] debug_instr,
    output logic [31:0] debug_alu_result
);

    // ----- Internal wires -----
    logic [31:0] pc_current, pc_plus4, pc_next;
    logic [31:0] instr;
    logic [31:0] rs1_data, rs2_data, rd_data;
    logic [31:0] imm;
    logic [31:0] alu_a, alu_b, alu_result;
    logic        alu_zero;
    logic [31:0] mem_read_data;
    logic [31:0] branch_target, jal_target, jalr_target;

    // Control signals
    logic        reg_write, mem_read, mem_write, mem_to_reg;
    logic        alu_src, branch, jal, jalr_sig, lui, auipc;
    imm_type_t   imm_type;
    alu_op_t     alu_op;

    // Branch decision
    logic        branch_taken;
    logic        do_branch;

    // ----- Instruction field extraction -----
    logic [6:0]  opcode;
    logic [4:0]  rd, rs1, rs2;
    logic [2:0]  funct3;
    logic [6:0]  funct7;

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    // ----- PC + 4 -----
    assign pc_plus4 = pc_current + 32'd4;

    // ----- Branch / Jump targets -----
    assign branch_target = pc_current + imm;        // B-type: PC + imm
    assign jal_target    = pc_current + imm;        // JAL:    PC + imm
    assign jalr_target   = (rs1_data + imm) & ~32'b1; // JALR: (rs1 + imm) & ~1

    // ----- Branch decision -----
    assign do_branch = branch & branch_taken;

    // ----- Next PC mux -----
    always_comb begin
        if (jal)
            pc_next = jal_target;
        else if (jalr_sig)
            pc_next = jalr_target;
        else if (do_branch)
            pc_next = branch_target;
        else
            pc_next = pc_plus4;
    end

    // ----- ALU input muxes -----
    assign alu_a = (auipc) ? pc_current : rs1_data;
    assign alu_b = (alu_src) ? imm : rs2_data;

    // ----- Write-back mux -----
    always_comb begin
        if (lui)
            rd_data = imm;                  // LUI: load upper immediate
        else if (jal || jalr_sig)
            rd_data = pc_plus4;             // JAL/JALR: save return address
        else if (mem_to_reg)
            rd_data = mem_read_data;        // Load: data from memory
        else
            rd_data = alu_result;           // ALU result
    end

    // ----- Debug outputs -----
    assign debug_pc         = pc_current;
    assign debug_instr      = instr;
    assign debug_alu_result = alu_result;

    // modules

    //
    pc u_pc (
        .clk      (clk),
        .rst_n    (rst_n),
        .pc_write (1'b1),       // always write in single-cycle
        .pc_next  (pc_next),
        .pc_out   (pc_current)
    );

    // Instruction Memory
    imem u_imem (
        .addr  (pc_current),
        .instr (instr),
        .data_addr (32'b0),
        .data_out  ()
    );

    // Control Unit
    control u_control (
        .opcode    (opcode),
        .funct3    (funct3),
        .funct7    (funct7),
        .funct12   (instr[31:20]),
        .reg_write (reg_write),
        .mem_read  (mem_read),
        .mem_write (mem_write),
        .mem_to_reg(mem_to_reg),
        .alu_src   (alu_src),
        .branch    (branch),
        .jal       (jal),
        .jalr      (jalr_sig),
        .lui       (lui),
        .auipc     (auipc),
        .imm_type  (imm_type),
        .alu_op    (alu_op),
        .is_mext   (),
        .mdu_op    (),
        .csr_op    (),
        .csr_zimm  (),
        .is_ecall  (),
        .is_ebreak (),
        .is_mret   (),
        .illegal_instr ()
    );

    // Immediate Generator
    imm_gen u_imm_gen (
        .instr    (instr),
        .imm_type (imm_type),
        .imm      (imm)
    );

    // Register File
    regfile u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .we       (reg_write),
        .rs1_addr (rs1),
        .rs2_addr (rs2),
        .rd_addr  (rd),
        .rd_data  (rd_data),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    // ALU
    alu u_alu (
        .a      (alu_a),
        .b      (alu_b),
        .op     (alu_op),
        .result (alu_result),
        .zero   (alu_zero)
    );

    // Branch Unit
    branch_unit u_branch (
        .funct3   (funct3),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .taken    (branch_taken)
    );

    // Data Memory
    dmem u_dmem (
        .clk        (clk),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .funct3     (funct3),
        .addr       (alu_result),
        .write_data (rs2_data),
        .read_data  (mem_read_data)
    );

endmodule
