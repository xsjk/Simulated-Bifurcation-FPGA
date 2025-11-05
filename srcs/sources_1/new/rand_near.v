`timescale 1ns / 1ps

// Random discretize the input IN to OUT
module rand_near #(
    parameter WIDTH = 8,
    parameter RAND_WIDTH = 6,
    parameter OUT_WIDTH = WIDTH - RAND_WIDTH,
    parameter METHOD = 0, // 0 for ro 1 for lfsr
    parameter SEED = 1
)(
    input wire clk,
    input wire [WIDTH-1:0] in,
    output wire [OUT_WIDTH-1:0] out
);

if (RAND_WIDTH + OUT_WIDTH != WIDTH)
    $error("Error: RAND_WIDTH + OUT_WIDTH must equal WIDTH");

if (WIDTH < RAND_WIDTH)
    $error("WIDTH (%d) must be greater than or equal to RAND_WIDTH (%d)", WIDTH, RAND_WIDTH);
else if (WIDTH == OUT_WIDTH)
    assign out = in;
else begin

    wire [RAND_WIDTH-1:0] rng;
    // Generate Random instances
    if (METHOD == 0)
        rand #(
            .WIDTH  (RAND_WIDTH),
            .SEED   (SEED)
        ) rand_i (
            .clk    (clk),
            .out    (rng)
        );
    else 
        rand_lfsr #(
            .WIDTH  (RAND_WIDTH),
            .SEED   (SEED)
        ) rand_lfsr_i (
            .clk    (clk),
            .out    (rng)
        );
    
    assign out = (in[RAND_WIDTH-1:0] > rng) ? (in[WIDTH-1:RAND_WIDTH] + 1) : in[WIDTH-1:RAND_WIDTH];
end

endmodule
