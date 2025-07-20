`timescale 1ns / 1ps

module rand #(
    parameter WIDTH = 8,
    parameter STAGE = 3
)(
    input wire clk,
    output reg [WIDTH-1:0] out
);

initial out = 0;

wire [WIDTH-1:0] ro_out;

rand_raw #(WIDTH, STAGE) rand_raw_i (
    .out    (ro_out)
);

reg [WIDTH-1:0] ro_out_reg;

always @(posedge clk) ro_out_reg <= ro_out;

wire [WIDTH-1:0] hash_out;

hash #(WIDTH) out_hash (
    .in     (ro_out_reg), 
    .out    (hash_out)
);


always @(posedge clk) begin
    `ifdef SIMULATION
        out <= $random;
    `else
        out <= out ^ hash_out;
    `endif
end
endmodule
