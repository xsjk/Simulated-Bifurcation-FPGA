`timescale 1ns / 1ps

module dual_lutram_gen #(
    parameter WIDTH = 1,
    parameter DEPTH = 64,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input wire [ADDR_WIDTH-1:0] addra,
    input wire [ADDR_WIDTH-1:0] addrb,
    input wire clk,
    input wire [WIDTH-1:0] dina,
    output wire [WIDTH-1:0] douta,
    output wire [WIDTH-1:0] doutb,
    input wire wea
);

localparam UNIT_DEPTH = 64;
localparam UNIT_ADDR_WIDTH = $clog2(UNIT_DEPTH);
if (DEPTH > UNIT_DEPTH) begin
    $error("Error: DEPTH (%d) must be less than or equal to %d", DEPTH, UNIT_DEPTH);
end

genvar i;
generate
    for (i = 0; i < WIDTH; i = i + 1) begin : gen_bram_units
        dual_lutram_unit dual_lutram_unit_i (
            .a      ({{(UNIT_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, addra}),
            .dpra   ({{(UNIT_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, addrb}),
            .clk    (clk),
            .d      (dina[i]),
            .spo    (douta[i]),
            .dpo    (doutb[i]),
            .we     (wea)
        );
    end
endgenerate

endmodule