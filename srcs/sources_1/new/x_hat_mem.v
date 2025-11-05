// A virtual memory module for x_hat with two read ports and one read/write port
module x_hat_mem #(
    parameter BLOCK_SIZE = 80,
    parameter N_BLOCK_PER_ROW = 25,
    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW),
    parameter DATA_WIDTH = 2,
    parameter ENABLE_OUTREG_I = 0,
    parameter ENABLE_OUTREG_J = 0,
    parameter ENABLE_OUTREG_K = 0
)
(
    input wire clk,
    input wire [BLOCK_IDX_WIDTH-1:0] i, // real read-only port that directly accesses lutram
    input wire [BLOCK_IDX_WIDTH-1:0] j, // virtual read-only port that actrually accesses registered value thanks to the traversal order of (i,j)
    input wire [BLOCK_IDX_WIDTH-1:0] k, // write port
    output reg [0:BLOCK_SIZE*DATA_WIDTH-1] dout_i,
    output reg [0:BLOCK_SIZE*DATA_WIDTH-1] dout_j,
    input wire [0:BLOCK_SIZE*DATA_WIDTH-1] din_k,
    output reg [0:BLOCK_SIZE*DATA_WIDTH-1] dout_k,
    input wire we_k
);

// Memory for x_hat
wire [0:BLOCK_SIZE*DATA_WIDTH-1] douta;
wire [0:BLOCK_SIZE*DATA_WIDTH-1] doutb;
dual_lutram_gen #(
    .WIDTH      (BLOCK_SIZE * DATA_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) dual_lutram_gen_i (
    .clk    (clk),
    .addra  (k),
    .wea    (we_k),
    .dina   (din_k),
    .douta  (douta),
    .addrb  (i),
    .doutb  (doutb)
);

reg [0:BLOCK_SIZE*DATA_WIDTH-1] col_reg;
always @(posedge clk) if (i == j) col_reg <= doutb;

if (ENABLE_OUTREG_I) always @(posedge clk) dout_i <= doutb;
else                 always @(*) dout_i = doutb;

if (ENABLE_OUTREG_J) always @(posedge clk) dout_j <= (i == j) ? doutb : col_reg;
else                 always @(*) dout_j = (i == j) ? doutb : col_reg; 

if (ENABLE_OUTREG_K) always @(posedge clk) dout_k <= douta;
else                 always @(*) dout_k = douta;


endmodule