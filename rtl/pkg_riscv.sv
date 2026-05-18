package pkg_riscv;

  typedef enum logic [6:0] {
    OP_LUI    = 7'b0110111,
    OP_AUIPC  = 7'b0010111,
    OP_JAL    = 7'b1101111,
    OP_JALR   = 7'b1100111,
    OP_BRANCH = 7'b1100011,
    OP_LOAD   = 7'b0000011,
    OP_STORE  = 7'b0100011,
    OP_IMM    = 7'b0010011,
    OP_REG    = 7'b0110011,
    OP_FENCE  = 7'b0001111,
    OP_SYSTEM = 7'b1110011
  } opcode_t;

  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0000,
    ALU_SUB  = 4'b0001,
    ALU_AND  = 4'b0010,
    ALU_OR   = 4'b0011,
    ALU_XOR  = 4'b0100,
    ALU_SLT  = 4'b0101,
    ALU_SLTU = 4'b0110,
    ALU_SLL  = 4'b0111,
    ALU_SRL  = 4'b1000,
    ALU_SRA  = 4'b1001
  } alu_op_t;

  typedef enum logic [2:0] {
    MDU_MUL    = 3'b000,
    MDU_MULH   = 3'b001,
    MDU_MULHSU = 3'b010,
    MDU_MULHU  = 3'b011,
    MDU_DIV    = 3'b100,
    MDU_DIVU   = 3'b101,
    MDU_REM    = 3'b110,
    MDU_REMU   = 3'b111
  } mdu_op_t;

  typedef enum logic [1:0] {
    CSR_NONE = 2'b00,
    CSR_RW   = 2'b01,
    CSR_RS   = 2'b10,
    CSR_RC   = 2'b11
  } csr_op_t;

  typedef enum logic [2:0] {
    IMM_I = 3'b000,
    IMM_S = 3'b001,
    IMM_B = 3'b010,
    IMM_U = 3'b011,
    IMM_J = 3'b100
  } imm_type_t;

  typedef enum logic [2:0] {
    F3_BEQ  = 3'b000,
    F3_BNE  = 3'b001,
    F3_BLT  = 3'b100,
    F3_BGE  = 3'b101,
    F3_BLTU = 3'b110,
    F3_BGEU = 3'b111
  } branch_funct3_t;

  typedef enum logic [2:0] {
    F3_BYTE  = 3'b000,
    F3_HALF  = 3'b001,
    F3_WORD  = 3'b010,
    F3_BYTEU = 3'b100,
    F3_HALFU = 3'b101
  } mem_funct3_t;

  typedef enum logic [1:0] {
    BTB_BRANCH = 2'b00,
    BTB_JAL    = 2'b01,
    BTB_CALL   = 2'b10,
    BTB_RET    = 2'b11
  } btb_type_t;

  // M-mode CSR addresses
  localparam logic [11:0] CSR_MSTATUS   = 12'h300;
  localparam logic [11:0] CSR_MIE       = 12'h304;
  localparam logic [11:0] CSR_MTVEC     = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH  = 12'h340;
  localparam logic [11:0] CSR_MEPC      = 12'h341;
  localparam logic [11:0] CSR_MCAUSE    = 12'h342;
  localparam logic [11:0] CSR_MTVAL     = 12'h343;
  localparam logic [11:0] CSR_MIP       = 12'h344;
  localparam logic [11:0] CSR_MCYCLE    = 12'hB00;
  localparam logic [11:0] CSR_MINSTRET  = 12'hB02;
  localparam logic [11:0] CSR_MCYCLEH   = 12'hB80;
  localparam logic [11:0] CSR_MINSTRETH = 12'hB82;
  localparam logic [11:0] CSR_MHPMCNT3  = 12'hB03; // branch mispredictions
  localparam logic [11:0] CSR_MHPMCNT4  = 12'hB04; // total branches
  localparam logic [11:0] CSR_MHPMCNT3H = 12'hB83;
  localparam logic [11:0] CSR_MHPMCNT4H = 12'hB84;

  // mcause values
  localparam logic [31:0] EXC_INSTR_MISALIGN = 32'd0;
  localparam logic [31:0] EXC_ILLEGAL_INSTR  = 32'd2;
  localparam logic [31:0] EXC_BREAKPOINT     = 32'd3;
  localparam logic [31:0] EXC_LOAD_MISALIGN  = 32'd4;
  localparam logic [31:0] EXC_STORE_MISALIGN = 32'd6;
  localparam logic [31:0] EXC_ECALL_M        = 32'd11;

endpackage
