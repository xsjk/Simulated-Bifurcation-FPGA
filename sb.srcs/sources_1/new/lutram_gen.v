`timescale 1ns / 1ps

module lutram_gen #(
    parameter WIDTH = 1,
    parameter DEPTH = 64,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input wire [ADDR_WIDTH-1:0] addr,
    input wire clk,
    input wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout,
    input wire we
);

localparam UNIT_DEPTH = 64;
if (DEPTH > UNIT_DEPTH) begin
    $error("Error: DEPTH (%d) must be less than or equal to %d", DEPTH, UNIT_DEPTH);
end

genvar i;
generate
    for (i = 0; i < WIDTH; i = i + 1) begin : gen_bram_units
        lutram_unit lutram_unit_inst (
            .a      (addr),
            .clk    (clk),
            .d      (din[i]),
            .spo    (dout[i]),
            .we     (we),
        );
    end
endgenerate

endmodule