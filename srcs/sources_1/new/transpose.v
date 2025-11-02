`timescale 1ns / 1ps

module transpose #(
    parameter N = 80,
    parameter M = 80,
    parameter W = 1
)(
    input wire [N*M*W-1:0] in,
    output wire [N*M*W-1:0] out
);
genvar i, j;

generate
    for (i = 0; i < N; i = i + 1) begin : row_loop
        for (j = 0; j < M; j = j + 1) begin : col_loop
            assign out[(j*N + i)*W +: W] = in[(i*M + j)*W +: W];
        end
    end
endgenerate

endmodule
