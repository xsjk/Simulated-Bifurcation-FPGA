`timescale 1ns / 1ps

// Random discretize the input IN to OUT
module rand_near #(
    parameter WIDTH = 8,
    parameter RAND_WIDTH = 6,
    parameter OUT_WIDTH = WIDTH - RAND_WIDTH,
    parameter ENABLE_OUTREG = 0
)(
    input wire clk,
    input wire [WIDTH-1:0] in,
    output reg [OUT_WIDTH-1:0] out
);

if (WIDTH < RAND_WIDTH) begin
    $error("WIDTH (%d) must be greater than or equal to RAND_WIDTH (%d)", WIDTH, RAND_WIDTH);
end else if (WIDTH == OUT_WIDTH) begin
    if (ENABLE_OUTREG) begin
        always @(posedge clk) out <= in;
    end else begin
        always @(*) out = in;
    end
end else begin

    wire [RAND_WIDTH-1:0] rng;
    // Generate Random instances
    rand #(
        .WIDTH  (RAND_WIDTH)
    ) rand_i (
        .clk    (clk),
        .out    (rng)
    );
    if (ENABLE_OUTREG) begin
        always @(posedge clk) begin
            if (in[RAND_WIDTH-1:0] > rng)
                out <= in[WIDTH-1:RAND_WIDTH] + 1;
            else
                out <= in[WIDTH-1:RAND_WIDTH];
        end
    end else begin
        always @(*) begin
            if (in[RAND_WIDTH-1:0] > rng)
                out = in[WIDTH-1:RAND_WIDTH] + 1;
            else 
                out = in[WIDTH-1:RAND_WIDTH];
        end
    end
end

endmodule
