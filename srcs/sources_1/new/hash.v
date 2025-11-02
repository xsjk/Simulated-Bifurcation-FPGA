`timescale 1ns / 1ps
module hash #(
    parameter WIDTH = 32
)(
    input wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out 
);

localparam MAX_SHIFT = $clog2(WIDTH);

wire [2*WIDTH-1:0] sum_bus [0:MAX_SHIFT];
wire [2*WIDTH-1:0] shifted [0:MAX_SHIFT];

genvar i;
generate
    for (i = 0; i <= MAX_SHIFT; i = i + 1) begin : shift_add
        localparam POS = (1 << i) - 1;
        assign shifted[i] = in << POS;
        if (i == 0) begin
            assign sum_bus[i] = shifted[0];
        end else begin
            assign sum_bus[i] = sum_bus[i-1] ^ shifted[i];
        end
    end
endgenerate

wire [2*WIDTH-1:0] final_sum = sum_bus[MAX_SHIFT];
assign out = final_sum[2*WIDTH-1:WIDTH] ^ final_sum[WIDTH-1:0];

endmodule
