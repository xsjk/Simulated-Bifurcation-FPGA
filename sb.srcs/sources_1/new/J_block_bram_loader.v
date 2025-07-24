`timescale 1ns / 1ps

module J_block_bram_loader #(
    parameter N = 2000,
    parameter BLOCK_SIZE = 80,
    parameter N_BLOCK_PER_ROW = N/BLOCK_SIZE,
    parameter BLOCK_DATA_WIDTH = BLOCK_SIZE*BLOCK_SIZE,
    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW),
    parameter BLOCK_FLAT_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW+N_BLOCK_PER_ROW*(N_BLOCK_PER_ROW-1)/2),
        
    // Parameters of the Block RAM Generator IP core, should not be changed from outside
    parameter BRAM_DATA_WIDTH = 90 * 36,
    parameter BRAM_ADDR_DEPTH = 1024,
    parameter BRAM_ADDR_WIDTH = $clog2(BRAM_ADDR_DEPTH),

    parameter ENABLE_OUTREG = 0
)
(
    input wire clk,
    input wire [BLOCK_IDX_WIDTH-1:0] i,
    input wire [BLOCK_IDX_WIDTH-1:0] j,
    input wire [BLOCK_FLAT_IDX_WIDTH-1:0] flat_idx,
    output wire [0:BLOCK_DATA_WIDTH-1] out_ij,
    output wire [0:BLOCK_DATA_WIDTH-1] out_ji
);

if (N_BLOCK_PER_ROW * BLOCK_SIZE != N) begin
    $error("N_BLOCK_PER_ROW (%d) * BLOCK_SIZE (%d) must equal N (%d)", N_BLOCK_PER_ROW, BLOCK_SIZE, N);
end
if (BLOCK_DATA_WIDTH > BRAM_DATA_WIDTH * 2) begin
    $error("BLOCK_DATA_WIDTH (%d) exceeds BRAM_DATA_WIDTH (%d) * 2, not enough bandwidth", BLOCK_DATA_WIDTH, BRAM_DATA_WIDTH);
end

wire [0:BRAM_DATA_WIDTH-1] douta;
wire [0:BRAM_DATA_WIDTH-1] doutb;

if (BLOCK_FLAT_IDX_WIDTH+1 > BRAM_ADDR_WIDTH) begin
    $error("BRAM_ADDR_WIDTH (%d) is not enough to hold flat_idx (%d) + 1", BRAM_ADDR_WIDTH, BLOCK_FLAT_IDX_WIDTH);
end 

J_block_bram bram_i (
    .clka   (clk),
    .addra  ({flat_idx, 1'b0}),
    .douta  (douta),
    .clkb   (clk),
    .addrb  ({flat_idx, 1'b1}),
    .doutb  (doutb)
);


wire [0:BLOCK_DATA_WIDTH-1] upper_block;
wire [0:BLOCK_DATA_WIDTH-1] lower_block;


// Concatenate the two BRAM outputs to form the block data
if (BLOCK_DATA_WIDTH <= BRAM_DATA_WIDTH) begin
    assign lower_block = douta[BLOCK_DATA_WIDTH-1:0];
    $info("BLOCK_DATA_WIDTH (%d) is less than or equal to BRAM_DATA_WIDTH (%d), using only douta", BLOCK_DATA_WIDTH, BRAM_DATA_WIDTH);
end else if (BLOCK_DATA_WIDTH <= BRAM_DATA_WIDTH * 2) begin
    assign lower_block = {douta, doutb[0:BLOCK_DATA_WIDTH-BRAM_DATA_WIDTH-1]};
    $info("BLOCK_DATA_WIDTH (%d) is less than or equal to 2 * BRAM_DATA_WIDTH (%d), using doutb and douta", BLOCK_DATA_WIDTH, BRAM_DATA_WIDTH);
end else begin
    $error("BLOCK_DATA_WIDTH (%d) exceeds the combined width of two BRAM outputs (%d)", BLOCK_DATA_WIDTH, BRAM_DATA_WIDTH * 2);
end


reg is_lower_block;
always @(posedge clk) begin
    is_lower_block <= (i > j);
end

transpose #(
    .N  (BLOCK_SIZE),
    .M  (BLOCK_SIZE),
    .W  (1)
) transpose_i (
    .in     (lower_block),
    .out    (upper_block)
);

if (ENABLE_OUTREG) begin
    reg [0:BLOCK_DATA_WIDTH-1] out_ij_reg;
    reg [0:BLOCK_DATA_WIDTH-1] out_ji_reg;
    always @(posedge clk) begin
        out_ij_reg <= is_lower_block ? lower_block : upper_block;
        out_ji_reg <= is_lower_block ? upper_block : lower_block;
    end
    assign out_ij = out_ij_reg;
    assign out_ji = out_ji_reg;
end else begin
    assign out_ij = is_lower_block ? lower_block : upper_block;
    assign out_ji = is_lower_block ? upper_block : lower_block;
end

endmodule
