`timescale 1ns / 1ps

module block_index_iterator #(
    parameter N = 80,
    parameter STEPS = 5000, // count from 0
    parameter WIDTH = $clog2(N),
    parameter STEP_WIDTH = $clog2(STEPS)
) (
    input wire clk,
    input wire rst,
    output reg [WIDTH-1:0] i,
    output reg [WIDTH-1:0] j,
    output reg [WIDTH-1:0] next_i,
    output reg [WIDTH-1:0] next_j,
    output reg initialized,
    output reg [STEP_WIDTH-1:0] step,
    output wire request_stop
);

// Internal signals
wire [WIDTH:0] s = j + i; 

assign request_stop = (j == N - 1 && i == N - 1) && (step == STEPS - 1);

reg is_first;

// Update j, i, initialized, step on clock edge
always @(posedge clk) begin
    i <= next_i;
    j <= next_j;

    if (rst) begin
        initialized <= 1'b0;
        step <= 0;
        is_first <= 1'b1;
    end else begin
        if (i == N - 1 && j == N - 1) begin
            initialized <= 1'b1;
            step <= step + 1;
        end
        if (s + 2 >= N)
            is_first <= 1'b0;
    end
end

// Update next_j, next_i with combinational logic
always @(*) begin
    if (rst) begin
        next_i = 0;
        next_j = 0;
    end else if (i > j) begin
        next_i = j;
        next_j = i;
    end else if (i + 1 < j) begin
        next_i = j - 1;
        next_j = i + 1;
    end else if (is_first) begin
        next_i = s + 1;
        next_j = 0;
    end else if (s >= N) begin
        next_i = s - N;
        next_j = 0;
    end else if (s + 2 >= N) begin
        next_i = N - 1;
        next_j = s + 2 - N;
    end else begin // s < N-2
        next_i = N - 1;
        next_j = s + 2;
    end
end

endmodule