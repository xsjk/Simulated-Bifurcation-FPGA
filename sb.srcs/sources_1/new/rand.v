`timescale 1ns / 1ps

module rand #(
    parameter WIDTH = 8,
    parameter STAGE = 3,
    parameter ENABLE_REG = 1,
    parameter ENABLE_HASH = 1,
    parameter ENABLE_XOR = 1
)(
    input wire clk,
    output wire [WIDTH-1:0] out
);

wire [WIDTH-1:0] ro_out_raw;

rand_raw #(WIDTH, STAGE) rand_raw_i (
    .out    (ro_out_raw)
);

wire [WIDTH-1:0] ro_out;

if (ENABLE_REG) begin
    reg [WIDTH-1:0] ro_out_reg;
    always @(posedge clk) ro_out_reg <= ro_out_raw;
    assign ro_out = ro_out_reg;
end else begin
    assign ro_out = ro_out_raw;
end

wire [WIDTH-1:0] ro_out_hashed;

if (ENABLE_HASH) begin
    hash #(WIDTH) out_hash (
        .in     (ro_out), 
        .out    (ro_out_hashed)
    );
end else begin
    assign ro_out_hashed = ro_out;
end

wire [WIDTH-1:0] ro_out_xored;

if (ENABLE_XOR) begin
    reg [WIDTH-1:0] xor_out;
    always @(posedge clk) xor_out <= xor_out ^ ro_out_hashed;
    assign ro_out_xored = xor_out;
end else begin
    assign ro_out_xored = ro_out_hashed;
end

`ifdef SIMULATION
    reg [WIDTH-1:0] out_reg;
    always @(posedge clk) out_reg <= $random;
    assign out = out_reg;
`else
    assign out = ro_out_xored;
`endif

endmodule
