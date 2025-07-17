`timescale 1ns / 1ps

module bram_gen #(
    parameter WIDTH = 36,
    parameter DEPTH = 1024,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input wire [ADDR_WIDTH-1:0] addra,
    input wire clka,
    input wire [WIDTH-1:0] dina,
    output wire [WIDTH-1:0] douta,
    input wire ena,
    input wire wea,
    input wire [ADDR_WIDTH-1:0] addrb,
    input wire clkb,
    input wire [WIDTH-1:0] dinb,
    output wire [WIDTH-1:0] doutb,
    input wire enb,
    input wire web
);

localparam UNIT_WIDTH = 36;
localparam UNIT_DEPTH = 1024;
localparam UNIT_ADDR_WIDTH = $clog2(UNIT_DEPTH);
localparam N_UNITS = (WIDTH + UNIT_WIDTH - 1) / UNIT_WIDTH; // Round up to the nearest unit

// Add missing wire declarations
wire [UNIT_ADDR_WIDTH-1:0] addras [0:N_UNITS-1];
wire [UNIT_ADDR_WIDTH-1:0] addrbs [0:N_UNITS-1];
wire [UNIT_WIDTH-1:0] dinas [0:N_UNITS-1];
wire [UNIT_WIDTH-1:0] dinbs [0:N_UNITS-1];
wire [UNIT_WIDTH-1:0] doutas [0:N_UNITS-1];
wire [UNIT_WIDTH-1:0] doutbs [0:N_UNITS-1];

if (DEPTH > UNIT_DEPTH) begin
    $error("Error: DEPTH (%d) must be less than or equal to %d", DEPTH, UNIT_DEPTH);
end

genvar i;
generate
    for (i = 0; i < N_UNITS; i = i + 1) begin : gen_bram_units
        // Connect addresses directly
        assign addras[i] = addra;
        assign addrbs[i] = addrb;
        
        // Connect data inputs based on width slices
        if (i == N_UNITS-1 && WIDTH % UNIT_WIDTH != 0) begin
            // Last unit with partial width
            localparam REMAINING_BITS = WIDTH % UNIT_WIDTH;
            assign dinas[i][REMAINING_BITS-1:0] = dina[WIDTH-1:i*UNIT_WIDTH];
            assign dinas[i][UNIT_WIDTH-1:REMAINING_BITS] = 0;
            assign dinbs[i][REMAINING_BITS-1:0] = dinb[WIDTH-1:i*UNIT_WIDTH];
            assign dinbs[i][UNIT_WIDTH-1:REMAINING_BITS] = 0;
            assign douta[WIDTH-1:i*UNIT_WIDTH] = doutas[i][REMAINING_BITS-1:0];
            assign doutb[WIDTH-1:i*UNIT_WIDTH] = doutbs[i][REMAINING_BITS-1:0];
        end else begin
            // Full width units
            assign dinas[i] = dina[i*UNIT_WIDTH +: UNIT_WIDTH];
            assign dinbs[i] = dinb[i*UNIT_WIDTH +: UNIT_WIDTH];
            assign douta[i*UNIT_WIDTH +: UNIT_WIDTH] = doutas[i];
            assign doutb[i*UNIT_WIDTH +: UNIT_WIDTH] = doutbs[i];
        end
        
        bram_unit bram_unit_inst (
            .addra  (addras[i]),
            .clka   (clka),
            .dina   (dinas[i]),
            .douta  (doutas[i]),
            .ena    (ena),
            .wea    (wea),
            .addrb  (addrbs[i]),
            .clkb   (clkb),
            .dinb   (dinbs[i]),
            .doutb  (doutbs[i]),
            .enb    (enb),
            .web    (web)
        );
    end
endgenerate

endmodule