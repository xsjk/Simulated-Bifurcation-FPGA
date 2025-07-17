`timescale 1ns / 1ps

module tb_J_block_bram_loader;

parameter N = 2000; // 2000x2000 matrix
parameter BLOCK_SIZE = 80; // 80x80 blocks
parameter BLOCK_DATA_WIDTH = BLOCK_SIZE*BLOCK_SIZE;
parameter N_BLOCK_PER_ROW = N / BLOCK_SIZE; // 3 blocks per row for a 12x12 matrix
parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW);
parameter CLK_PERIOD = 10;

parameter STEPS = 2;
parameter STEP_WIDTH = $clog2(STEPS);

reg clk;
reg rst;
wire [0:BLOCK_DATA_WIDTH-1] block_data;
wire [0:BLOCK_DATA_WIDTH-1] block_data_T;

initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end


// Block Index 
wire [BLOCK_IDX_WIDTH-1:0] i;
wire [BLOCK_IDX_WIDTH-1:0] j;
wire [BLOCK_IDX_WIDTH-1:0] next_i;
wire [BLOCK_IDX_WIDTH-1:0] next_j;
wire initialized;
wire [STEP_WIDTH-1:0] step;
wire request_stop;
wire is_diagonal = (i == j);
block_index_iterator #(
    .N          (N_BLOCK_PER_ROW),
    .STEPS      (STEPS)
) block_index_iterator_i (
    .clk            (clk),
    .rst            (rst),
    .i              (i),
    .j              (j),
    .next_i         (next_i),
    .next_j         (next_j),
    .initialized    (initialized),
    .step           (step),
    .request_stop   (request_stop)
);


J_block_bram_loader #(
    .N              (N),
    .BLOCK_SIZE     (BLOCK_SIZE)
) uut (
    .clk    (clk),
    .rst    (rst),
    .i      (next_i),
    .j      (next_j),
    .out_ij (block_data),
    .out_ji (block_data_T)
);



integer k;
initial begin
    rst = 1;
    #(CLK_PERIOD * 5);
    rst = 0;
    #(CLK_PERIOD);
    for (k = 0; k < N_BLOCK_PER_ROW * N_BLOCK_PER_ROW; k = k + 1) begin
        #(CLK_PERIOD);
        $display("block[%d][%d] = %b", i, j, block_data);
        $display("block[%d][%d].T = %b", i, j, block_data_T);
    end
    $finish;
end

endmodule
