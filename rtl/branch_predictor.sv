// gshare predictor + direct-mapped BTB + 4-entry return address stack.
// gshare: 128-entry PHT indexed by PC[8:2] XOR GHR.
// BTB: 64 entries, stores target + type (branch/jal/call/ret).
// RAS: push on call (rd=x1/x5), pop on return (rs1=x1/x5).

import pkg_riscv::*;

module branch_predictor #(
  parameter PHT_DEPTH  = 64,
  parameter BTB_DEPTH  = 32,
  parameter RAS_DEPTH  = 4
)(
  input  logic        clk, rst_n,

  // IF stage: prediction
  input  logic [31:0] pc_if,
  output logic        predict_taken,
  output logic [31:0] predict_target,
  output logic        predict_valid, // BTB hit, target is meaningful

  // ID stage: RAS push (decoded call)
  input  logic        ras_push_en,
  input  logic [31:0] ras_push_addr,

  // EX stage: update on resolution
  input  logic        update_en,
  input  logic [31:0] update_pc,
  input  logic        actual_taken,
  input  logic [31:0] actual_target,
  input  btb_type_t   update_type,

  // flush: restore RAS pointer on mispredict
  input  logic        flush,
  input  logic [1:0]  flush_ras_ptr,

  // expose current RAS pointer for pipeline checkpointing
  output logic [1:0]  ras_ptr_out
);

  localparam PHT_IDX  = $clog2(PHT_DEPTH);
  localparam BTB_IDX  = $clog2(BTB_DEPTH);
  localparam BTB_TAG  = 32 - BTB_IDX - 2;

  // GHR: updated non-speculatively on branch resolution
  logic [PHT_IDX-1:0] ghr;

  // PHT: 2-bit saturating counters
  logic [1:0] pht [0:PHT_DEPTH-1];

  // BTB
  logic              btb_valid [0:BTB_DEPTH-1];
  logic [BTB_TAG-1:0] btb_tag [0:BTB_DEPTH-1];
  logic [31:0]       btb_target[0:BTB_DEPTH-1];
  btb_type_t         btb_type  [0:BTB_DEPTH-1];

  // RAS
  logic [31:0] ras [0:RAS_DEPTH-1];
  logic [1:0]  ras_ptr;
  assign ras_ptr_out = ras_ptr;

  // prediction indexing
  logic [PHT_IDX-1:0] pht_predict_idx;
  logic [BTB_IDX-1:0] btb_predict_idx;
  logic [BTB_TAG-1:0] btb_predict_tag;

  assign pht_predict_idx = pc_if[PHT_IDX+1:2] ^ ghr;
  assign btb_predict_idx = pc_if[BTB_IDX+1:2];
  assign btb_predict_tag = pc_if[31:BTB_IDX+2];

  logic btb_hit;
  assign btb_hit = btb_valid[btb_predict_idx] &&
                   (btb_tag[btb_predict_idx] == btb_predict_tag);

  logic pht_taken;
  assign pht_taken = pht[pht_predict_idx][1]; // MSB of 2-bit counter

  // prediction outputs
  always_comb begin
    predict_valid = btb_hit;
    if (btb_hit && btb_type[btb_predict_idx] == BTB_RET) begin
      predict_taken  = 1'b1; // always predict return taken
      predict_target = ras[ras_ptr - 2'd1]; // TOS
    end else if (btb_hit && (btb_type[btb_predict_idx] == BTB_JAL ||
                              btb_type[btb_predict_idx] == BTB_CALL)) begin
      predict_taken  = 1'b1; // unconditional jump always taken
      predict_target = btb_target[btb_predict_idx];
    end else begin
      predict_taken  = btb_hit & pht_taken;
      predict_target = btb_target[btb_predict_idx];
    end
  end

  // update indexing
  logic [PHT_IDX-1:0] pht_update_idx;
  logic [BTB_IDX-1:0] btb_update_idx;
  logic [BTB_TAG-1:0] btb_update_tag;

  assign pht_update_idx = update_pc[PHT_IDX+1:2] ^ ghr;
  assign btb_update_idx = update_pc[BTB_IDX+1:2];
  assign btb_update_tag = update_pc[31:BTB_IDX+2];

  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ghr <= 0;
      ras_ptr <= 0;
      for (i = 0; i < PHT_DEPTH; i++)
        pht[i] <= 2'b01; // weakly not-taken
      for (i = 0; i < BTB_DEPTH; i++)
        btb_valid[i] <= 0;
      for (i = 0; i < RAS_DEPTH; i++)
        ras[i] <= 0;
    end else begin
      // RAS push from ID stage
      if (ras_push_en) begin
        ras[ras_ptr] <= ras_push_addr;
        ras_ptr <= ras_ptr + 1;
      end

      // RAS pointer restore on mispredict
      if (flush) begin
        ras_ptr <= flush_ras_ptr;
      end

      // update from EX stage
      if (update_en) begin
        // GHR shift
        ghr <= {ghr[PHT_IDX-2:0], actual_taken};

        // PHT update
        if (actual_taken && pht[pht_update_idx] < 2'b11)
          pht[pht_update_idx] <= pht[pht_update_idx] + 1;
        else if (!actual_taken && pht[pht_update_idx] > 2'b00)
          pht[pht_update_idx] <= pht[pht_update_idx] - 1;

        // BTB update (allocate on taken, keep on not-taken if entry exists)
        if (actual_taken) begin
          btb_valid [btb_update_idx] <= 1;
          btb_tag   [btb_update_idx] <= btb_update_tag;
          btb_target[btb_update_idx] <= actual_target;
          btb_type  [btb_update_idx] <= update_type;
        end
      end
    end
  end

endmodule
