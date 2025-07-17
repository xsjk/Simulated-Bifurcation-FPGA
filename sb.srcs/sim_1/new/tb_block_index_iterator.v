`timescale 1ns / 1ps

module tb_block_index_iterator;

parameter N = 3;
parameter WIDTH = $clog2(N);
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
wire initialized;
wire [STEP_WIDTH-1:0] step;
wire request_stop;

block_index_iterator #(
    .N      (N),
    .STEPS  (STEPS)
) uut (
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


initial begin
    rst = 1;
    #10;
    rst = 0;
end

always @(posedge clk) begin
    $display("Time: %d, rst: %b, i: %d, j: %d, next_i: %d, next_j: %d, initialized: %b, step: %d, request_stop: %b",
             $time, rst, i, j, next_i, next_j, initialized, step, request_stop);
    if (request_stop) begin
        $display("Request to stop");
        $finish;
    end
end

endmodule