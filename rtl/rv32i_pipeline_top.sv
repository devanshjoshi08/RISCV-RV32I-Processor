import pkg_riscv::*;

module rv32i_pipeline_top (
  input logic clk,
  input logic rst_n,
  output logic [31:0] debug_pc,
  output logic [31:0] debug_instr,
  output logic [31:0] debug_alu_result
);

    // hazard / forwarding control
    logic        pc_stall, if_id_stall, id_ex1_stall, ex1_ex2_stall;
    logic        if_id_flush, id_ex1_flush, ex1_ex2_flush;
    logic [1:0]  forward_a, forward_b;

    // IF stage
    logic [31:0] if_pc, if_pc_plus4, if_instr;
    logic [31:0] pc_next;
    logic        if_predict_taken;
    logic [31:0] if_predict_target;
    logic        if_predict_valid;
    logic        icache_hit;
    logic [31:0] imem_raw_instr, icache_mem_addr;

    // IF/ID outputs
    logic [31:0] id_pc, id_pc_plus4, id_instr;

    // ID stage
    logic [6:0]  id_opcode;
    logic [4:0]  id_rd, id_rs1, id_rs2;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7;
    logic [11:0] id_funct12;
    logic [31:0] id_rs1_data, id_rs2_data, id_imm;
    logic        id_reg_write, id_mem_read, id_mem_write, id_mem_to_reg;
    logic        id_alu_src, id_branch, id_jal, id_jalr, id_lui, id_auipc;
    imm_type_t   id_imm_type;
    alu_op_t     id_alu_op;
    logic        id_is_mext;
    mdu_op_t     id_mdu_op;
    csr_op_t     id_csr_op;
    logic        id_csr_zimm;
    logic        id_is_ecall, id_is_ebreak, id_is_mret;
    logic        id_illegal_instr;
    logic        id_predict_taken;
    logic [1:0]  ras_ptr_current;
    logic        id_ras_push, id_is_call, id_is_ret;

    // ID/EX1 outputs
    logic [31:0] ex1_pc, ex1_pc_plus4, ex1_rs1_data, ex1_rs2_data, ex1_imm;
    logic [4:0]  ex1_rs1_addr, ex1_rs2_addr, ex1_rd_addr;
    logic [2:0]  ex1_funct3;
    logic        ex1_reg_write, ex1_mem_read, ex1_mem_write, ex1_mem_to_reg;
    logic        ex1_alu_src, ex1_branch, ex1_jal, ex1_jalr, ex1_lui, ex1_auipc;
    alu_op_t     ex1_alu_op;
    logic        ex1_is_mext;
    mdu_op_t     ex1_mdu_op;
    csr_op_t     ex1_csr_op;
    logic        ex1_csr_zimm;
    logic [11:0] ex1_csr_addr;
    logic        ex1_is_ecall, ex1_is_ebreak, ex1_is_mret;
    logic        ex1_illegal_instr;
    logic        ex1_predicted_taken;
    logic [1:0]  ex1_ras_ptr;

    // EX1 stage (forwarding + operand select)
    logic [31:0] ex1_fwd_rs1, ex1_fwd_rs2;
    logic [31:0] ex1_alu_a, ex1_alu_b;
    logic [31:0] ex1_csr_wdata;

    // EX1/EX2 outputs
    logic [31:0] ex2_alu_a, ex2_alu_b, ex2_fwd_rs1, ex2_fwd_rs2;
    logic [31:0] ex2_pc, ex2_pc_plus4, ex2_imm;
    logic [4:0]  ex2_rd_addr;
    logic [2:0]  ex2_funct3;
    logic        ex2_reg_write, ex2_mem_read, ex2_mem_write, ex2_mem_to_reg;
    logic        ex2_branch, ex2_jal, ex2_jalr, ex2_lui;
    alu_op_t     ex2_alu_op;
    logic        ex2_is_mext;
    mdu_op_t     ex2_mdu_op;
    csr_op_t     ex2_csr_op;
    logic [11:0] ex2_csr_addr;
    logic [31:0] ex2_csr_wdata;
    logic        ex2_is_ecall, ex2_is_ebreak, ex2_is_mret;
    logic        ex2_illegal_instr;
    logic        ex2_predicted_taken;
    logic [1:0]  ex2_ras_ptr;

    // EX2 stage (ALU + branch + CSR + MDU)
    logic [31:0] ex2_alu_result;
    logic        ex2_alu_zero;
    logic [31:0] ex2_branch_target, ex2_jalr_target;
    logic        ex2_branch_taken, ex2_do_branch;
    logic        ex2_mispredict;
    logic [31:0] ex2_result;
    logic [31:0] mdu_result;
    logic        mdu_busy, mdu_valid, mdu_start;
    logic [31:0] csr_rdata, mtvec, mepc_out;
    logic        mstatus_mie;
    logic        ex2_trap;
    logic [31:0] ex2_trap_cause, ex2_trap_val;

    // EX2/MEM outputs
    logic [31:0] mem_pc_plus4, mem_alu_result, mem_rs2_data;
    logic [4:0]  mem_rd_addr;
    logic [2:0]  mem_funct3;
    logic        mem_reg_write, mem_mem_read, mem_mem_write, mem_mem_to_reg;
    logic        mem_jal, mem_jalr;
    logic        mem_is_csr;
    logic [31:0] mem_csr_rdata;

    // MEM stage
    logic [31:0] mem_read_data;

    // MEM/WB outputs
    logic [31:0] wb_pc_plus4, wb_alu_result, wb_mem_read_data;
    logic [4:0]  wb_rd_addr;
    logic        wb_reg_write, wb_mem_to_reg;
    logic        wb_jal, wb_jalr;
    logic        wb_is_csr;
    logic [31:0] wb_csr_rdata;

    // WB stage
    logic [31:0] wb_rd_data;
    logic mem_retire;
    assign mem_retire = mem_reg_write || mem_mem_write || mem_mem_read ||
                        mem_jal || mem_jalr;

    //
    // IF
    //

    assign if_pc_plus4 = if_pc + 32'd4;

    always_comb begin
        if (ex2_trap)
            pc_next = mtvec;
        else if (ex2_is_mret)
            pc_next = mepc_out;
        else if (ex2_jal)
            pc_next = ex2_branch_target;
        else if (ex2_jalr)
            pc_next = ex2_jalr_target;
        else if (ex2_do_branch && !ex2_predicted_taken)
            pc_next = ex2_branch_target;
        else if (ex2_branch && !ex2_branch_taken && ex2_predicted_taken)
            pc_next = ex2_pc_plus4;
        else if (if_predict_valid && if_predict_taken)
            pc_next = if_predict_target;
        else
            pc_next = if_pc_plus4;
    end

    assign ex2_mispredict = ex2_branch && (ex2_branch_taken != ex2_predicted_taken);

    btb_type_t bp_update_type;
    always_comb begin
        if (ex2_branch)    bp_update_type = BTB_BRANCH;
        else if (ex2_jal)  bp_update_type = BTB_JAL;
        else               bp_update_type = BTB_BRANCH;
    end

    branch_predictor u_bp (
        .clk            (clk),
        .rst_n          (rst_n),
        .pc_if          (if_pc),
        .predict_taken  (if_predict_taken),
        .predict_target (if_predict_target),
        .predict_valid  (if_predict_valid),
        .ras_push_en    (id_ras_push && !if_id_flush),
        .ras_push_addr  (id_pc_plus4),
        .update_en      (ex2_branch || ex2_jal),
        .update_pc      (ex2_pc),
        .actual_taken   (ex2_branch_taken || ex2_jal),
        .actual_target  (ex2_branch_target),
        .update_type    (bp_update_type),
        .flush          (ex2_mispredict || ex2_jal || ex2_jalr),
        .flush_ras_ptr  (ex2_ras_ptr),
        .ras_ptr_out    (ras_ptr_current)
    );

    pc u_pc (
        .clk      (clk),
        .rst_n    (rst_n),
        .pc_write (!pc_stall),
        .pc_next  (pc_next),
        .pc_out   (if_pc)
    );

    imem u_imem (
        .addr  (icache_mem_addr),
        .instr (imem_raw_instr),
        .data_addr (32'b0),
        .data_out  ()
    );

    icache u_icache (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (if_pc),
        .instr    (if_instr),
        .hit      (icache_hit),
        .mem_addr (icache_mem_addr),
        .mem_data (imem_raw_instr)
    );

    assign debug_pc    = if_pc;
    assign debug_instr = id_instr;

    //
    // IF/ID
    //

    pipe_if_id u_if_id (
        .clk               (clk),
        .rst_n             (rst_n),
        .stall             (if_id_stall),
        .flush             (if_id_flush),
        .pc_in             (if_pc),
        .pc_plus4_in       (if_pc_plus4),
        .instr_in          (if_instr),
        .predict_taken_in  (if_predict_taken && if_predict_valid),
        .pc_out            (id_pc),
        .pc_plus4_out      (id_pc_plus4),
        .instr_out         (id_instr),
        .predict_taken_out (id_predict_taken)
    );

    //
    // ID
    //

    assign id_opcode  = id_instr[6:0];
    assign id_rd      = id_instr[11:7];
    assign id_funct3  = id_instr[14:12];
    assign id_rs1     = id_instr[19:15];
    assign id_rs2     = id_instr[24:20];
    assign id_funct7  = id_instr[31:25];
    assign id_funct12 = id_instr[31:20];

    control u_control (
        .opcode(id_opcode), .funct3(id_funct3), .funct7(id_funct7), .funct12(id_funct12),
        .reg_write(id_reg_write), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .mem_to_reg(id_mem_to_reg), .alu_src(id_alu_src), .branch(id_branch),
        .jal(id_jal), .jalr(id_jalr), .lui(id_lui), .auipc(id_auipc),
        .imm_type(id_imm_type), .alu_op(id_alu_op),
        .is_mext(id_is_mext), .mdu_op(id_mdu_op),
        .csr_op(id_csr_op), .csr_zimm(id_csr_zimm),
        .is_ecall(id_is_ecall), .is_ebreak(id_is_ebreak),
        .is_mret(id_is_mret), .illegal_instr(id_illegal_instr)
    );

    imm_gen u_imm_gen (.instr(id_instr), .imm_type(id_imm_type), .imm(id_imm));

    regfile u_regfile (
        .clk(clk), .rst_n(rst_n), .we(wb_reg_write),
        .rs1_addr(id_rs1), .rs2_addr(id_rs2),
        .rd_addr(wb_rd_addr), .rd_data(wb_rd_data),
        .rs1_data(id_rs1_data), .rs2_data(id_rs2_data)
    );

    assign id_is_call = (id_jal || id_jalr) && (id_rd == 5'd1 || id_rd == 5'd5);
    assign id_is_ret  = id_jalr && (id_rs1 == 5'd1 || id_rs1 == 5'd5) && (id_rd != id_rs1);
    assign id_ras_push = id_is_call;

    //
    // ID/EX1
    //

    pipe_id_ex u_id_ex1 (
        .clk(clk), .rst_n(rst_n), .flush(id_ex1_flush), .stall(id_ex1_stall),
        .reg_write_in(id_reg_write), .mem_read_in(id_mem_read),
        .mem_write_in(id_mem_write), .mem_to_reg_in(id_mem_to_reg),
        .alu_src_in(id_alu_src), .branch_in(id_branch),
        .jal_in(id_jal), .jalr_in(id_jalr), .lui_in(id_lui), .auipc_in(id_auipc),
        .alu_op_in(id_alu_op),
        .pc_in(id_pc), .pc_plus4_in(id_pc_plus4),
        .rs1_data_in(id_rs1_data), .rs2_data_in(id_rs2_data), .imm_in(id_imm),
        .rs1_addr_in(id_rs1), .rs2_addr_in(id_rs2), .rd_addr_in(id_rd),
        .funct3_in(id_funct3), .predict_taken_in(id_predict_taken),
        .is_mext_in(id_is_mext), .mdu_op_in(id_mdu_op),
        .csr_op_in(id_csr_op), .csr_zimm_in(id_csr_zimm), .csr_addr_in(id_funct12),
        .is_ecall_in(id_is_ecall), .is_ebreak_in(id_is_ebreak),
        .is_mret_in(id_is_mret), .illegal_instr_in(id_illegal_instr),
        .ras_ptr_in(ras_ptr_current),
        .reg_write_out(ex1_reg_write), .mem_read_out(ex1_mem_read),
        .mem_write_out(ex1_mem_write), .mem_to_reg_out(ex1_mem_to_reg),
        .alu_src_out(ex1_alu_src), .branch_out(ex1_branch),
        .jal_out(ex1_jal), .jalr_out(ex1_jalr), .lui_out(ex1_lui), .auipc_out(ex1_auipc),
        .alu_op_out(ex1_alu_op),
        .pc_out(ex1_pc), .pc_plus4_out(ex1_pc_plus4),
        .rs1_data_out(ex1_rs1_data), .rs2_data_out(ex1_rs2_data), .imm_out(ex1_imm),
        .rs1_addr_out(ex1_rs1_addr), .rs2_addr_out(ex1_rs2_addr), .rd_addr_out(ex1_rd_addr),
        .funct3_out(ex1_funct3), .predict_taken_out(ex1_predicted_taken),
        .is_mext_out(ex1_is_mext), .mdu_op_out(ex1_mdu_op),
        .csr_op_out(ex1_csr_op), .csr_zimm_out(ex1_csr_zimm), .csr_addr_out(ex1_csr_addr),
        .is_ecall_out(ex1_is_ecall), .is_ebreak_out(ex1_is_ebreak),
        .is_mret_out(ex1_is_mret), .illegal_instr_out(ex1_illegal_instr),
        .ras_ptr_out(ex1_ras_ptr)
    );

    //
    // EX1: forwarding + operand select
    //

    // EX2 result for forwarding (combinational, before pipe_ex2_mem)
    logic [31:0] ex2_fwd_result;
    always_comb begin
        if (ex2_lui)         ex2_fwd_result = ex2_imm;
        else if (ex2_is_mext) ex2_fwd_result = mdu_result;
        else if (ex2_csr_op != CSR_NONE) ex2_fwd_result = csr_rdata;
        else                 ex2_fwd_result = ex2_alu_result;
    end

    // MEM result for forwarding (registered in pipe_ex2_mem)
    logic [31:0] mem_fwd_result;
    always_comb begin
        if (mem_jal || mem_jalr) mem_fwd_result = mem_pc_plus4;
        else if (mem_mem_read)   mem_fwd_result = mem_read_data;
        else if (mem_is_csr)     mem_fwd_result = mem_csr_rdata;
        else                     mem_fwd_result = mem_alu_result;
    end

    forwarding_unit u_forward (
        .ex1_rs1_addr (ex1_rs1_addr),
        .ex1_rs2_addr (ex1_rs2_addr),
        .ex2_rd_addr  (ex2_rd_addr),
        .ex2_reg_write(ex2_reg_write),
        .ex2_mem_read (ex2_mem_read),
        .ex2_is_mext  (ex2_is_mext),
        .ex2_mdu_valid(mdu_valid),
        .mem_rd_addr  (mem_rd_addr),
        .mem_reg_write(mem_reg_write),
        .wb_rd_addr   (wb_rd_addr),
        .wb_reg_write (wb_reg_write),
        .forward_a    (forward_a),
        .forward_b    (forward_b)
    );

    // fresh register file reads for EX1 (with WB bypass).
    // pipe_id_ex1 values go stale during multi-cycle stalls.
    logic [31:0] ex1_rf_rs1, ex1_rf_rs2;
    assign ex1_rf_rs1 = (ex1_rs1_addr == 5'b0) ? 32'b0 :
                         (wb_reg_write && wb_rd_addr == ex1_rs1_addr) ? wb_rd_data :
                         u_regfile.regs[ex1_rs1_addr];
    assign ex1_rf_rs2 = (ex1_rs2_addr == 5'b0) ? 32'b0 :
                         (wb_reg_write && wb_rd_addr == ex1_rs2_addr) ? wb_rd_data :
                         u_regfile.regs[ex1_rs2_addr];

    always_comb begin
        case (forward_a)
            2'b01:   ex1_fwd_rs1 = ex2_fwd_result;
            2'b10:   ex1_fwd_rs1 = mem_fwd_result;
            2'b11:   ex1_fwd_rs1 = wb_rd_data;
            default: ex1_fwd_rs1 = ex1_rf_rs1;
        endcase

        case (forward_b)
            2'b01:   ex1_fwd_rs2 = ex2_fwd_result;
            2'b10:   ex1_fwd_rs2 = mem_fwd_result;
            2'b11:   ex1_fwd_rs2 = wb_rd_data;
            default: ex1_fwd_rs2 = ex1_rf_rs2;
        endcase
    end

    assign ex1_alu_a = (ex1_auipc) ? ex1_pc : ex1_fwd_rs1;
    assign ex1_alu_b = (ex1_alu_src) ? ex1_imm : ex1_fwd_rs2;
    assign ex1_csr_wdata = ex1_csr_zimm ? {27'b0, ex1_rs1_addr} : ex1_fwd_rs1;

    //
    // EX1/EX2
    //

    logic mdu_stall;
    assign mdu_stall = ex2_is_mext && !mdu_valid;

    pipe_ex1_ex2 u_ex1_ex2 (
        .clk(clk), .rst_n(rst_n),
        .flush(ex1_ex2_flush),
        .stall(mdu_stall),
        .reg_write_in(ex1_reg_write), .mem_read_in(ex1_mem_read),
        .mem_write_in(ex1_mem_write), .mem_to_reg_in(ex1_mem_to_reg),
        .branch_in(ex1_branch), .jal_in(ex1_jal), .jalr_in(ex1_jalr), .lui_in(ex1_lui),
        .alu_op_in(ex1_alu_op),
        .alu_a_in(ex1_alu_a), .alu_b_in(ex1_alu_b),
        .fwd_rs1_in(ex1_fwd_rs1), .fwd_rs2_in(ex1_fwd_rs2),
        .pc_in(ex1_pc), .pc_plus4_in(ex1_pc_plus4), .imm_in(ex1_imm),
        .rd_addr_in(ex1_rd_addr), .funct3_in(ex1_funct3),
        .predict_taken_in(ex1_predicted_taken),
        .is_mext_in(ex1_is_mext), .mdu_op_in(ex1_mdu_op),
        .csr_op_in(ex1_csr_op), .csr_addr_in(ex1_csr_addr), .csr_wdata_in(ex1_csr_wdata),
        .is_ecall_in(ex1_is_ecall), .is_ebreak_in(ex1_is_ebreak),
        .is_mret_in(ex1_is_mret), .illegal_instr_in(ex1_illegal_instr),
        .ras_ptr_in(ex1_ras_ptr),
        .reg_write_out(ex2_reg_write), .mem_read_out(ex2_mem_read),
        .mem_write_out(ex2_mem_write), .mem_to_reg_out(ex2_mem_to_reg),
        .branch_out(ex2_branch), .jal_out(ex2_jal), .jalr_out(ex2_jalr), .lui_out(ex2_lui),
        .alu_op_out(ex2_alu_op),
        .alu_a_out(ex2_alu_a), .alu_b_out(ex2_alu_b),
        .fwd_rs1_out(ex2_fwd_rs1), .fwd_rs2_out(ex2_fwd_rs2),
        .pc_out(ex2_pc), .pc_plus4_out(ex2_pc_plus4), .imm_out(ex2_imm),
        .rd_addr_out(ex2_rd_addr), .funct3_out(ex2_funct3),
        .predict_taken_out(ex2_predicted_taken),
        .is_mext_out(ex2_is_mext), .mdu_op_out(ex2_mdu_op),
        .csr_op_out(ex2_csr_op), .csr_addr_out(ex2_csr_addr), .csr_wdata_out(ex2_csr_wdata),
        .is_ecall_out(ex2_is_ecall), .is_ebreak_out(ex2_is_ebreak),
        .is_mret_out(ex2_is_mret), .illegal_instr_out(ex2_illegal_instr),
        .ras_ptr_out(ex2_ras_ptr)
    );

    //
    // EX2: ALU + branch + CSR + MDU
    //

    alu u_alu (
        .a(ex2_alu_a), .b(ex2_alu_b), .op(ex2_alu_op),
        .result(ex2_alu_result), .zero(ex2_alu_zero)
    );

    assign mdu_start = ex2_is_mext && !mdu_busy && !mdu_valid;

    mdu u_mdu (
        .clk(clk), .rst_n(rst_n), .start(mdu_start), .op(ex2_mdu_op),
        .rs1(ex2_fwd_rs1), .rs2(ex2_fwd_rs2),
        .result(mdu_result), .busy(mdu_busy), .valid(mdu_valid)
    );

    assign ex2_trap = ex2_illegal_instr || ex2_is_ecall || ex2_is_ebreak;
    always_comb begin
        if (ex2_illegal_instr)  ex2_trap_cause = EXC_ILLEGAL_INSTR;
        else if (ex2_is_ecall)  ex2_trap_cause = EXC_ECALL_M;
        else if (ex2_is_ebreak) ex2_trap_cause = EXC_BREAKPOINT;
        else                    ex2_trap_cause = 32'b0;
    end
    assign ex2_trap_val = ex2_illegal_instr ? ex2_pc : 32'b0;

    csr_unit u_csr (
        .clk(clk), .rst_n(rst_n),
        .addr(ex2_csr_addr), .op(ex2_trap ? CSR_NONE : ex2_csr_op),
        .wdata(ex2_csr_wdata), .rdata(csr_rdata),
        .trap_en(ex2_trap), .trap_cause(ex2_trap_cause),
        .trap_pc(ex2_pc), .trap_val(ex2_trap_val),
        .mtvec_out(mtvec), .mret_en(ex2_is_mret), .mepc_out(mepc_out),
        .mstatus_mie(mstatus_mie),
        .retire_en(mem_retire), .branch_en(ex2_branch), .mispredict_en(ex2_mispredict)
    );

    always_comb begin
        if (ex2_lui)          ex2_result = ex2_imm;
        else if (ex2_is_mext) ex2_result = mdu_result;
        else                  ex2_result = ex2_alu_result;
    end

    assign ex2_branch_target = ex2_pc + ex2_imm;
    assign ex2_jalr_target   = (ex2_fwd_rs1 + ex2_imm) & ~32'b1;

    branch_unit u_branch (
        .funct3(ex2_funct3), .rs1_data(ex2_fwd_rs1), .rs2_data(ex2_fwd_rs2),
        .taken(ex2_branch_taken)
    );

    assign ex2_do_branch = ex2_branch & ex2_branch_taken;
    assign debug_alu_result = ex2_alu_result;

    //
    // hazard detection
    //

    hazard_unit u_hazard (
        .ex2_mem_read  (ex2_mem_read),
        .ex2_rd_addr   (ex2_rd_addr),
        .ex1_rs1_addr  (ex1_rs1_addr),
        .ex1_rs2_addr  (ex1_rs2_addr),
        .branch_taken  (ex2_mispredict),
        .jal_ex2       (ex2_jal),
        .jalr_ex2      (ex2_jalr),
        .mdu_busy      (mdu_stall),
        .trap_flush    (ex2_trap),
        .mret_flush    (ex2_is_mret),
        .pc_stall      (pc_stall),
        .if_id_stall   (if_id_stall),
        .id_ex1_stall  (id_ex1_stall),
        .ex1_ex2_stall (ex1_ex2_stall),
        .if_id_flush   (if_id_flush),
        .id_ex1_flush  (id_ex1_flush),
        .ex1_ex2_flush (ex1_ex2_flush)
    );

    //
    // EX2/MEM
    //

    logic ex2_suppress;
    assign ex2_suppress = ex2_trap || mdu_stall;

    pipe_ex_mem u_ex2_mem (
        .clk(clk), .rst_n(rst_n),
        .reg_write_in  (ex2_suppress ? 1'b0 : ex2_reg_write),
        .mem_read_in   (ex2_suppress ? 1'b0 : ex2_mem_read),
        .mem_write_in  (ex2_suppress ? 1'b0 : ex2_mem_write),
        .mem_to_reg_in (ex2_mem_to_reg),
        .jal_in(ex2_jal), .jalr_in(ex2_jalr),
        .pc_plus4_in(ex2_pc_plus4), .alu_result_in(ex2_result),
        .rs2_data_in(ex2_fwd_rs2), .rd_addr_in(ex2_rd_addr), .funct3_in(ex2_funct3),
        .is_csr_in(ex2_csr_op != CSR_NONE), .csr_rdata_in(csr_rdata),
        .reg_write_out(mem_reg_write), .mem_read_out(mem_mem_read),
        .mem_write_out(mem_mem_write), .mem_to_reg_out(mem_mem_to_reg),
        .jal_out(mem_jal), .jalr_out(mem_jalr),
        .pc_plus4_out(mem_pc_plus4), .alu_result_out(mem_alu_result),
        .rs2_data_out(mem_rs2_data), .rd_addr_out(mem_rd_addr), .funct3_out(mem_funct3),
        .is_csr_out(mem_is_csr), .csr_rdata_out(mem_csr_rdata)
    );

    //
    // MEM
    //

    dmem u_dmem (
        .clk(clk), .mem_read(mem_mem_read), .mem_write(mem_mem_write),
        .funct3(mem_funct3), .addr(mem_alu_result),
        .write_data(mem_rs2_data), .read_data(mem_read_data)
    );

    //
    // MEM/WB
    //

    pipe_mem_wb u_mem_wb (
        .clk(clk), .rst_n(rst_n),
        .reg_write_in(mem_reg_write), .mem_to_reg_in(mem_mem_to_reg),
        .jal_in(mem_jal), .jalr_in(mem_jalr),
        .pc_plus4_in(mem_pc_plus4), .alu_result_in(mem_alu_result),
        .mem_read_data_in(mem_read_data), .rd_addr_in(mem_rd_addr),
        .is_csr_in(mem_is_csr), .csr_rdata_in(mem_csr_rdata),
        .reg_write_out(wb_reg_write), .mem_to_reg_out(wb_mem_to_reg),
        .jal_out(wb_jal), .jalr_out(wb_jalr),
        .pc_plus4_out(wb_pc_plus4), .alu_result_out(wb_alu_result),
        .mem_read_data_out(wb_mem_read_data), .rd_addr_out(wb_rd_addr),
        .is_csr_out(wb_is_csr), .csr_rdata_out(wb_csr_rdata)
    );

    //
    // WB
    //

    always_comb begin
        if (wb_jal || wb_jalr)   wb_rd_data = wb_pc_plus4;
        else if (wb_mem_to_reg)  wb_rd_data = wb_mem_read_data;
        else if (wb_is_csr)      wb_rd_data = wb_csr_rdata;
        else                     wb_rd_data = wb_alu_result;
    end

endmodule
