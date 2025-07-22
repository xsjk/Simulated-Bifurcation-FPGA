`timescale 1ns / 1ps

module block_index_iterator #(
    parameter N = 80,
    parameter WIDTH = $clog2(N),
    parameter STEPS = 5000,
    parameter STEP_WIDTH = $clog2(STEPS)
) (
    input wire clk,
    input wire rst,
    output reg [WIDTH-1:0] i,
    output reg [WIDTH-1:0] j,
    output reg [STEP_WIDTH-1:0] step,
    output wire request_stop
);

// Internal signals
wire [WIDTH:0] s = j + i;
reg is_first;
assign request_stop = (i == N - 1 && j == N - 1 && step == STEPS - 1);

// Update i, j, step on clock edge
always @(posedge clk) begin
    if (rst) begin
        i <= 0;
        j <= 0;
        step <= 0;
        is_first <= 1'b1;
    end else begin
        if (i > j) begin
            i <= j;
            j <= i;
        end else if (i + 1 < j) begin
            i <= j - 1;
            j <= i + 1;
        end else if (is_first) begin
            i <= s + 1;
            j <= 0;
        end else if (s >= N) begin
            i <= s - N;
            j <= 0;
        end else if (s + 2 >= N) begin
            i <= N - 1;
            j <= s + 2 - N;
        end else begin // s < N-2
            i <= N - 1;
            j <= s + 2;
        end
        if (i == N - 1 && j == N - 1)
            step <= step + 1;
        if (s + 2 >= N)
            is_first <= 1'b0;
    end
end


endmodule