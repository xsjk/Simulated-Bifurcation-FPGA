// A virtual memory module for x_hat with two read/write ports.
module L_mem #(
    parameter BLOCK_SIZE = 80,
    parameter N_BLOCK_PER_ROW = 25,
    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW),
    parameter DELTA_WIDTH = 0, // should be externally set
    parameter DATA_WIDTH = 0, // should be externally set
    parameter ENABLE_OUTREG = 0
)
(
    input wire clk,
    input wire en,
    input wire [BLOCK_IDX_WIDTH-1:0] i, // real port that directly accesses a single port lutram
    input wire [BLOCK_IDX_WIDTH-1:0] j, // virtual port that actrually accesses registered value thanks to the traversal order of (i,j)
    input wire [0:DELTA_WIDTH*BLOCK_SIZE-1] delta_i, // the offset to be added to L_i
    input wire [0:DELTA_WIDTH*BLOCK_SIZE-1] delta_j, // the offset to be added to L_j
    output reg [0:DATA_WIDTH*BLOCK_SIZE-1] dout_i, // updated L_i
    output reg [0:DATA_WIDTH*BLOCK_SIZE-1] dout_j // updated L_j
);

if (DELTA_WIDTH == 0 || DATA_WIDTH == 0) begin
    $error("Error: DELTA_WIDTH and DATA_WIDTH must be explicitly set");
end

wire [0:DATA_WIDTH*BLOCK_SIZE-1] L_i_packed;
reg [0:DATA_WIDTH*BLOCK_SIZE-1] L_j_packed;

genvar gi;
wire signed [DATA_WIDTH-1:0] L_i [0:BLOCK_SIZE-1];
wire signed [DATA_WIDTH-1:0] L_j [0:BLOCK_SIZE-1];
wire signed [DELTA_WIDTH-1:0] delta_L_i [0:BLOCK_SIZE-1];
wire signed [DELTA_WIDTH-1:0] delta_L_j [0:BLOCK_SIZE-1];
wire signed [DATA_WIDTH-1:0] L_i_new [0:BLOCK_SIZE-1];
wire signed [DATA_WIDTH-1:0] L_j_new [0:BLOCK_SIZE-1];
wire [0:DATA_WIDTH*BLOCK_SIZE-1] L_i_packed_new;
wire [0:DATA_WIDTH*BLOCK_SIZE-1] L_j_packed_new;
generate
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : gen_next_tmp_j
        assign delta_L_i[gi] = delta_i[gi*DELTA_WIDTH +: DELTA_WIDTH];
        assign delta_L_j[gi] = delta_j[gi*DELTA_WIDTH +: DELTA_WIDTH];
        assign L_i[gi] = L_i_packed[gi*DATA_WIDTH +: DATA_WIDTH];
        assign L_j[gi] = L_j_packed[gi*DATA_WIDTH +: DATA_WIDTH];
        assign L_i_new[gi] = en ? $signed(j == 0 ? delta_L_i[gi] : L_i[gi] + delta_L_i[gi]) : {DATA_WIDTH{1'b0}};
        assign L_j_new[gi] = en ? $signed(i == j ? L_i_new[gi] : L_j[gi] + delta_L_j[gi]) : {DATA_WIDTH{1'b0}};
        assign L_i_packed_new[gi*DATA_WIDTH +: DATA_WIDTH] = L_i_new[gi];
        assign L_j_packed_new[gi*DATA_WIDTH +: DATA_WIDTH] = L_j_new[gi];
    end
endgenerate


// lutram for L_i
lutram_gen #(
    .WIDTH          (BLOCK_SIZE * DATA_WIDTH),
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

// output register
if (ENABLE_OUTREG) 
    always @(posedge clk) begin
        dout_i <= L_i_packed_new;
        dout_j <= L_j_packed_new;
    end
else 
    always @(*) begin
        dout_i = L_i_packed_new;
        dout_j = L_j_packed_new;
    end

endmodule