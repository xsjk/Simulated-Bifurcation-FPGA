`timescale 1ns / 1ps

// i always >= j
module block_index_iterator #(
    parameter N = 80,
    parameter STEPS = 5000, // count from 0
    parameter WIDTH = $clog2(N),
    parameter IDX_MAX = N*(N+1)/2-1,
    parameter IDX_WIDTH = $clog2(IDX_MAX+1),
    parameter STEP_WIDTH = $clog2(STEPS)
) (
    input wire clk,
    input wire rst,
    output reg [WIDTH-1:0] i,
    output reg [WIDTH-1:0] j,
    output reg [WIDTH-1:0] next_i,
    output reg [WIDTH-1:0] next_j,
    output reg [IDX_WIDTH-1:0] flat_idx,
    output reg [IDX_WIDTH-1:0] next_flat_idx,
    output reg initialized,
    output reg [STEP_WIDTH-1:0] step,
    output wire request_stop
);

assign request_stop = (flat_idx == IDX_MAX) && (step == STEPS - 1);

// Update j, i, initialized, step on clock edge
always @(posedge clk) begin
    i <= next_i;
    j <= next_j;
    flat_idx <= next_flat_idx;

    if (rst) begin
        initialized <= 1'b0;
        step <= 0;
    end else begin
        if (i == N - 1 && j == N - 1) begin
            initialized <= 1'b1;
            step <= step + 1;
        end
    end
end

// Update next_j, next_i with combinational logic
always @(*) begin
    if (rst || flat_idx == IDX_MAX) begin
        next_i = 0;
        next_j = 0;
        next_flat_idx = 0;
    end else if (i == N - 1) begin
        next_i = j + 1;
        next_j = j + 1;
        next_flat_idx = flat_idx + 1;
    end else begin
        next_i = i + 1;
        next_j = j;
        next_flat_idx = flat_idx + 1;
    end
end

endmodule