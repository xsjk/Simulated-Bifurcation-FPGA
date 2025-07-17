`timescale 1ns / 1ps

module to_flat_index #(
    parameter N = 25,
    parameter WIDTH = $clog2(N),
    parameter IDX_WIDTH = $clog2(N+N*(N-1)/2)

)(
    input [WIDTH-1:0] i,
    input [WIDTH-1:0] j,
    output [IDX_WIDTH-1:0] o
);

wire [WIDTH-1:0] d = i < j ? j - i : i - j;
wire [IDX_WIDTH-1:0] offset = N * d - (d - 1) * d / 2;
assign o = offset + (i < j ? i : j);

endmodule
