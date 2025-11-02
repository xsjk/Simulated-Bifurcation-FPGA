`timescale 1ns / 1ps

// Random discretize the input IN to OUT
module rand_near #(
    parameter WIDTH = 8,
    parameter RAND_WIDTH = 6,
    parameter OUT_WIDTH = WIDTH - RAND_WIDTH
)(
    input wire clk,
    input wire [WIDTH-1:0] in,
    output wire [OUT_WIDTH-1:0] out
);

if (WIDTH < RAND_WIDTH) begin
    $error("WIDTH (%d) must be greater than or equal to RAND_WIDTH (%d)", WIDTH, RAND_WIDTH);
end else if (WIDTH == OUT_WIDTH) begin
    assign out = in;
end else begin

    wire [RAND_WIDTH-1:0] rng;
    // Generate Random instances
    rand #(
        .WIDTH  (RAND_WIDTH)
    ) rand_i (
        .clk    (clk),
        .out    (rng)
    );
    assign out = (in[RAND_WIDTH-1:0] > rng) ? (in[WIDTH-1:RAND_WIDTH] + 1) : in[WIDTH-1:RAND_WIDTH];
end

endmodule
