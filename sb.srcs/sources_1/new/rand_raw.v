`timescale 1ns / 1ps

module rand_raw #(
    parameter WIDTH = 8,
    parameter STAGE = 9
)(
    output wire [WIDTH-1:0] out
);

genvar i;
generate
    for (i=0; i<WIDTH; i=i+1) begin: ros
        (* DONT_TOUCH = "true" *) ring_oscillator #(STAGE) ro (out[i]);
    end
endgenerate


endmodule
