// A virtual memory module for x_hat with two read ports and one read/write port
module x_hat_mem #(
    parameter BLOCK_SIZE = 80,
    parameter N_BLOCK_PER_ROW = 25,
    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW),
    parameter X_HAT_WIDTH = 2
)
(
    input wire clk,
    input wire [BLOCK_IDX_WIDTH-1:0] i, // real read-only port that directly accesses lutram
    input wire [BLOCK_IDX_WIDTH-1:0] j, // virtual read-only port that actrually accesses registered value thanks to the traversal order of (i,j)
    input wire [BLOCK_IDX_WIDTH-1:0] k, // write port
    output wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] dout_i,
    output wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] dout_j,
    input wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] din_k,
    output wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] dout_k,
    input wire we_k
);

// Memory for x_hat
dual_lutram_gen #(
    .WIDTH      (BLOCK_SIZE * X_HAT_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) dual_lutram_gen_i (
    .clk    (clk),
    .addra  (k),
    .wea    (we_k),
    .dina   (din_k),
    .douta  (dout_k),
    .addrb  (i),
    .doutb  (dout_i)
);


reg [0:BLOCK_SIZE*X_HAT_WIDTH-1] col_reg;
always @(posedge clk) if (i == j) col_reg <= dout_i;
assign dout_j = (i == j) ? dout_i : col_reg;


endmodule