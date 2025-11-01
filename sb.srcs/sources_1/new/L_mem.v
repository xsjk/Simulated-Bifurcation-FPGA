module L_mem #(
    parameter N = 2000,
    parameter BLOCK_SIZE = 80,
    parameter N_BLOCK_PER_ROW = N / BLOCK_SIZE,
    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW),
    parameter BLOCK_MUL_WIDTH = 1 + $clog2(BLOCK_SIZE + 1),
    parameter MUL_WIDTH = 1 + $clog2(N+1) - 2
)
(
    input wire clk,
    input wire en,
    input wire [BLOCK_IDX_WIDTH-1:0] i,
    input wire [BLOCK_IDX_WIDTH-1:0] j,
    input wire [BLOCK_IDX_WIDTH-1:0] next_i,
    input wire [BLOCK_IDX_WIDTH-1:0] next_j,
    input wire [0:BLOCK_MUL_WIDTH*BLOCK_SIZE-1] delta_L_i_packed,
    input wire [0:BLOCK_MUL_WIDTH*BLOCK_SIZE-1] delta_L_j_packed,
    output wire [0:MUL_WIDTH*BLOCK_SIZE-1] L_i_packed_new,
    output wire [0:MUL_WIDTH*BLOCK_SIZE-1] L_j_packed_new
);

wire [0:MUL_WIDTH*BLOCK_SIZE-1] L_i_packed;
reg [0:MUL_WIDTH*BLOCK_SIZE-1] L_j_packed;

genvar gi;
wire signed [MUL_WIDTH-1:0] L_i [0:BLOCK_SIZE-1];
wire signed [MUL_WIDTH-1:0] L_j [0:BLOCK_SIZE-1];
wire signed [BLOCK_MUL_WIDTH-1:0] delta_L_i [0:BLOCK_SIZE-1];
wire signed [BLOCK_MUL_WIDTH-1:0] delta_L_j [0:BLOCK_SIZE-1];
wire signed [MUL_WIDTH-1:0] L_i_new [0:BLOCK_SIZE-1];
wire signed [MUL_WIDTH-1:0] L_j_new [0:BLOCK_SIZE-1];
generate
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : gen_next_tmp_j
        assign delta_L_i[gi] = delta_L_i_packed[gi*BLOCK_MUL_WIDTH +: BLOCK_MUL_WIDTH];
        assign delta_L_j[gi] = delta_L_j_packed[gi*BLOCK_MUL_WIDTH +: BLOCK_MUL_WIDTH];
        assign L_i[gi] = L_i_packed[gi*MUL_WIDTH +: MUL_WIDTH];
        assign L_j[gi] = L_j_packed[gi*MUL_WIDTH +: MUL_WIDTH];
        assign L_i_new[gi] = j == 0 ? delta_L_i[gi] : L_i[gi] + delta_L_i[gi];
        assign L_j_new[gi] = i == j ? L_i_new[gi] : L_j[gi] + delta_L_j[gi];
        assign L_i_packed_new[gi*MUL_WIDTH +: MUL_WIDTH] = en ? L_i_new[gi] : {MUL_WIDTH{1'b0}};
        assign L_j_packed_new[gi*MUL_WIDTH +: MUL_WIDTH] = en ? L_j_new[gi] : {MUL_WIDTH{1'b0}};
    end
endgenerate


// lutram for L_i
lutram_gen #(
    .WIDTH          (BLOCK_SIZE * MUL_WIDTH),
    .DEPTH          (N_BLOCK_PER_ROW),
    .ADDR_WIDTH     (BLOCK_IDX_WIDTH)
) lutram_gen_i (
    .clk            (clk),
    .addr           (i),
    .din            (L_i_packed_new),
    .dout           (L_i_packed),
    .we             (en)
);

// reg for L_j
always @(posedge clk) begin
    L_j_packed <= L_j_packed_new;
end

// `ifdef SIMULATION
//     integer dbg_idx;
//     always @(posedge clk)
//         if (!rst) begin
//             $write("[L_mem] i=%0d j=%0d delta_i={", i, j);
//             for (dbg_idx = 0; dbg_idx < BLOCK_SIZE; dbg_idx = dbg_idx + 1)
//                 $write("%2d%s", delta_L_i[dbg_idx], (dbg_idx == BLOCK_SIZE-1) ? "" : ",");
//             $write("} delta_j={");
//             for (dbg_idx = 0; dbg_idx < BLOCK_SIZE; dbg_idx = dbg_idx + 1)
//                 $write("%2d%s", delta_L_j[dbg_idx], (dbg_idx == BLOCK_SIZE-1) ? "" : ",");
//             $write("} L_i_new={");
//             for (dbg_idx = 0; dbg_idx < BLOCK_SIZE; dbg_idx = dbg_idx + 1)
//                 $write("%2d%s", L_i_new[dbg_idx], (dbg_idx == BLOCK_SIZE-1) ? "" : ",");
//             $write("} L_j_new={");
//             for (dbg_idx = 0; dbg_idx < BLOCK_SIZE; dbg_idx = dbg_idx + 1)
//                 $write("%2d%s", L_j_new[dbg_idx], (dbg_idx == BLOCK_SIZE-1) ? "" : ",");
//             $display("}");
//         end
// `endif

endmodule