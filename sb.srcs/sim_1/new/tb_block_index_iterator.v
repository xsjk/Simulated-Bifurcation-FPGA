`timescale 1ns / 1ps

module tb_block_index_iterator;

parameter N = 4;
parameter WIDTH = $clog2(N);
parameter FLAT_WIDTH = $clog2(N*(N+1)/2);
parameter STEPS = 3;
parameter STEP_WIDTH = $clog2(STEPS);

reg clk;
initial clk = 0;
always #5 clk = ~clk;

reg rst;
wire [WIDTH-1:0] i;
wire [WIDTH-1:0] j;
wire [WIDTH-1:0] next_i;
wire [WIDTH-1:0] next_j;
wire [FLAT_WIDTH-1:0] flat_idx;
wire [FLAT_WIDTH-1:0] next_flat_idx;
wire initialized;
wire [STEP_WIDTH-1:0] step;
wire request_stop;

block_index_iterator #(
    .N      (N),
    .STEPS  (STEPS)
) block_index_iterator_i (
    .clk            (clk),
    .rst            (rst),
    .i              (i),
    .j              (j),
    .next_i         (next_i),
    .next_j         (next_j),
    .flat_idx       (flat_idx),
    .next_flat_idx  (next_flat_idx),
    .initialized    (initialized),
    .step           (step),
    .request_stop   (request_stop)
);


initial begin
    rst = 1;
    #10;
    rst = 0;
end

always @(posedge clk) begin
    $display("Time: %0d, rst: %b, i: %0d, j: %0d, next_i: %0d, next_j: %0d, flat_idx: %0d, next_flat_idx: %0d, initialized: %b, step: %0d, request_stop: %b",
             $time, rst, i, j, next_i, next_j, flat_idx, next_flat_idx, initialized, step, request_stop);
    if (request_stop) begin
        $display("Request to stop");
        $finish;
    end
end

endmodule