`timescale 1ns / 1ps

module rand_lfsr #(
    parameter WIDTH = 8,
    parameter QUEUE_WIDTH = WIDTH <= 8 ? 8 : WIDTH <= 16 ? 16 : WIDTH <= 32 ? 32 : WIDTH,
    parameter [QUEUE_WIDTH-1:0] SEED = {{(QUEUE_WIDTH-1){1'b0}}, 1'b1}
)(
    input wire clk,
    output reg [WIDTH-1:0] out
);

if (WIDTH == 0)
    $error("rand: WIDTH must be greater than zero.");
if (QUEUE_WIDTH < 2)
    $error("rand: QUEUE_WIDTH must be at least 2.");
if (QUEUE_WIDTH < WIDTH)
    $error("rand: QUEUE_WIDTH (%0d) must be >= WIDTH (%0d).", QUEUE_WIDTH, WIDTH);
if (SEED == 0)
    $error("rand: SEED must be non-zero.");

reg [QUEUE_WIDTH-1:0] q;
wire f;
wire [QUEUE_WIDTH-1:0] q_next;

generate
    if (QUEUE_WIDTH == 8) begin
        assign f = q[0] ^ q[2] ^ q[3] ^ q[4];
    end else if (QUEUE_WIDTH == 16) begin
        assign f = q[0] ^ q[1] ^ q[3] ^ q[12];
    end else if (QUEUE_WIDTH == 32) begin
        assign f = q[0] ^ q[10] ^ q[30] ^ q[31];
    end else begin
        assign f = q[0] ^ q[QUEUE_WIDTH-1];
    end
endgenerate

assign q_next = {f, q[QUEUE_WIDTH-1:1]};

initial begin
    if (WIDTH == 0)
        $error("rand_lfsr: WIDTH must be greater than zero.");
    if (QUEUE_WIDTH < 2)
        $error("rand_lfsr: QUEUE_WIDTH must be at least 2.");
    if (QUEUE_WIDTH < WIDTH)
        $error("rand_lfsr: QUEUE_WIDTH (%0d) must be >= WIDTH (%0d).", QUEUE_WIDTH, WIDTH);
    if (SEED == 0)
        $error("rand_lfsr: SEED must be non-zero.");
    q = SEED;
    out = SEED[WIDTH-1:0];
end

always @(posedge clk) begin
    q <= q_next;
    out <= q_next[WIDTH-1:0];
end

endmodule
