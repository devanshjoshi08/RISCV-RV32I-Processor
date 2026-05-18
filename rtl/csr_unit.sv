// M-mode CSR register file with performance counters.
// read/write in EX stage; trap handling is synchronous.

import pkg_riscv::*;

module csr_unit (
  input  logic        clk, rst_n,

  // read/write port (EX stage)
  input  logic [11:0] addr,
  input  csr_op_t     op,
  input  logic [31:0] wdata,
  output logic [31:0] rdata,

  // trap interface
  input  logic        trap_en,
  input  logic [31:0] trap_cause,
  input  logic [31:0] trap_pc,
  input  logic [31:0] trap_val,
  output logic [31:0] mtvec_out,

  // mret
  input  logic        mret_en,
  output logic [31:0] mepc_out,
  output logic        mstatus_mie,

  // perf counter events
  input  logic        retire_en,
  input  logic        branch_en,
  input  logic        mispredict_en
);

  // registers
  logic [31:0] mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip;
  logic [63:0] mcycle, minstret;
  logic [63:0] hpmcnt3, hpmcnt4; // mispredictions, total branches

  assign mtvec_out    = mtvec;
  assign mepc_out     = mepc;
  assign mstatus_mie  = mstatus[3]; // MIE bit

  // CSR read
  always_comb begin
    case (addr)
      CSR_MSTATUS:   rdata = mstatus;
      CSR_MIE:       rdata = mie;
      CSR_MTVEC:     rdata = mtvec;
      CSR_MSCRATCH:  rdata = mscratch;
      CSR_MEPC:      rdata = mepc;
      CSR_MCAUSE:    rdata = mcause;
      CSR_MTVAL:     rdata = mtval;
      CSR_MIP:       rdata = mip;
      CSR_MCYCLE:    rdata = mcycle[31:0];
      CSR_MCYCLEH:   rdata = mcycle[63:32];
      CSR_MINSTRET:  rdata = minstret[31:0];
      CSR_MINSTRETH: rdata = minstret[63:32];
      CSR_MHPMCNT3:  rdata = hpmcnt3[31:0];
      CSR_MHPMCNT3H: rdata = hpmcnt3[63:32];
      CSR_MHPMCNT4:  rdata = hpmcnt4[31:0];
      CSR_MHPMCNT4H: rdata = hpmcnt4[63:32];
      default:       rdata = 32'b0;
    endcase
  end

  // compute new value for read-modify-write
  logic [31:0] csr_new;
  always_comb begin
    case (op)
      CSR_RW:  csr_new = wdata;
      CSR_RS:  csr_new = rdata | wdata;
      CSR_RC:  csr_new = rdata & ~wdata;
      default: csr_new = rdata;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus  <= 32'h0000_1800; // MPP=M
      mie      <= 0;
      mtvec    <= 0;
      mscratch <= 0;
      mepc     <= 0;
      mcause   <= 0;
      mtval    <= 0;
      mip      <= 0;
      mcycle   <= 0;
      minstret <= 0;
      hpmcnt3  <= 0;
      hpmcnt4  <= 0;
    end else begin
      // cycle counter always increments
      mcycle <= mcycle + 1;

      // instruction retire counter
      if (retire_en)
        minstret <= minstret + 1;

      // branch perf counters
      if (branch_en)
        hpmcnt4 <= hpmcnt4 + 1;
      if (mispredict_en)
        hpmcnt3 <= hpmcnt3 + 1;

      // trap takes priority over CSR writes
      if (trap_en) begin
        mepc    <= trap_pc;
        mcause  <= trap_cause;
        mtval   <= trap_val;
        mstatus[7]  <= mstatus[3]; // MPIE = MIE
        mstatus[3]  <= 1'b0;       // MIE = 0
      end else if (mret_en) begin
        mstatus[3]  <= mstatus[7]; // MIE = MPIE
        mstatus[7]  <= 1'b1;       // MPIE = 1
      end else if (op != CSR_NONE) begin
        case (addr)
          CSR_MSTATUS:   mstatus  <= csr_new;
          CSR_MIE:       mie      <= csr_new;
          CSR_MTVEC:     mtvec    <= csr_new;
          CSR_MSCRATCH:  mscratch <= csr_new;
          CSR_MEPC:      mepc     <= csr_new & ~32'b1; // mepc[0] always 0
          CSR_MCAUSE:    mcause   <= csr_new;
          CSR_MTVAL:     mtval    <= csr_new;
          CSR_MCYCLE:    mcycle[31:0]   <= csr_new;
          CSR_MCYCLEH:   mcycle[63:32]  <= csr_new;
          CSR_MINSTRET:  minstret[31:0]  <= csr_new;
          CSR_MINSTRETH: minstret[63:32] <= csr_new;
          CSR_MHPMCNT3:  hpmcnt3[31:0]  <= csr_new;
          CSR_MHPMCNT3H: hpmcnt3[63:32] <= csr_new;
          CSR_MHPMCNT4:  hpmcnt4[31:0]  <= csr_new;
          CSR_MHPMCNT4H: hpmcnt4[63:32] <= csr_new;
          default: ;
        endcase
      end
    end
  end

endmodule
