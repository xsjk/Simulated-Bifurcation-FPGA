`timescale 1ns / 1ps

module J_mem #(
    parameter N = 2000,
    parameter BLOCK_SIZE = 80,
    parameter N_BLOCK_PER_ROW = N/BLOCK_SIZE,
    parameter BLOCK_DATA_WIDTH = BLOCK_SIZE*BLOCK_SIZE,
    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW),
    parameter BLOCK_FLAT_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW*(N_BLOCK_PER_ROW+1)/2),
        
    // Parameters of the Block RAM Generator IP core, should not be changed from outside
    parameter BRAM_DATA_WIDTH = 89 * 36,
    parameter BRAM_ADDR_DEPTH = 1024,
    parameter BRAM_ADDR_WIDTH = $clog2(BRAM_ADDR_DEPTH),

    parameter ENABLE_OUTREG = 0
)
(
    input wire clk,
    input wire [BLOCK_FLAT_IDX_WIDTH-1:0] idx,
    output reg [0:BLOCK_DATA_WIDTH-1] upper_block,
    output reg [0:BLOCK_DATA_WIDTH-1] lower_block
);

if (N_BLOCK_PER_ROW * BLOCK_SIZE != N) begin
    $error("N_BLOCK_PER_ROW (%d) * BLOCK_SIZE (%d) must equal N (%d)", N_BLOCK_PER_ROW, BLOCK_SIZE, N);
end
if (BLOCK_DATA_WIDTH > BRAM_DATA_WIDTH * 2) begin
    $error("BLOCK_DATA_WIDTH (%d) exceeds BRAM_DATA_WIDTH (%d) * 2, not enough bandwidth", BLOCK_DATA_WIDTH, BRAM_DATA_WIDTH);
end

wire [0:BRAM_DATA_WIDTH-1] douta;
wire [0:BRAM_DATA_WIDTH-1] doutb;
wire [0:BLOCK_DATA_WIDTH-1] lower_block_unreg;
wire [0:BLOCK_DATA_WIDTH-1] upper_block_unreg;

if (BLOCK_FLAT_IDX_WIDTH+1 > BRAM_ADDR_WIDTH) begin
    $error("BRAM_ADDR_WIDTH (%d) is not enough to hold idx (%d) + 1", BRAM_ADDR_WIDTH, BLOCK_FLAT_IDX_WIDTH);
end 

J_bram bram_i (
    .A_clk  (clk),
    .A_addr ({idx, 1'b0}),
    .A_dout (douta),
    .B_clk  (clk),
    .B_addr ({idx, 1'b1}),
    .B_dout (doutb)
);


// Concatenate the two BRAM outputs to form the block data
if (BLOCK_DATA_WIDTH <= BRAM_DATA_WIDTH) begin
    assign lower_block_unreg = douta[BLOCK_DATA_WIDTH-1:0];
    $info("BLOCK_DATA_WIDTH (%d) is less than or equal to BRAM_DATA_WIDTH (%d), using only douta", BLOCK_DATA_WIDTH, BRAM_DATA_WIDTH);
end else if (BLOCK_DATA_WIDTH <= BRAM_DATA_WIDTH * 2) begin
    assign lower_block_unreg = {douta, doutb[0:BLOCK_DATA_WIDTH-BRAM_DATA_WIDTH-1]};
    $info("BLOCK_DATA_WIDTH (%d) is less than or equal to 2 * BRAM_DATA_WIDTH (%d), using doutb and douta", BLOCK_DATA_WIDTH, BRAM_DATA_WIDTH);
end else begin
    $error("BLOCK_DATA_WIDTH (%d) exceeds the combined width of two BRAM outputs (%d)", BLOCK_DATA_WIDTH, BRAM_DATA_WIDTH * 2);
end


transpose #(
    .N  (BLOCK_SIZE),
    .M  (BLOCK_SIZE),
    .W  (1)
) transpose_i (
    .in     (lower_block_unreg),
    .out    (upper_block_unreg)
);

if (ENABLE_OUTREG)
    always @(posedge clk) begin
        upper_block <= upper_block_unreg;
        lower_block <= lower_block_unreg;
    end
else
    always @(*) begin
        upper_block = upper_block_unreg;
        lower_block = lower_block_unreg;
    end


endmodule
