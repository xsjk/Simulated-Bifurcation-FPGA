`timescale 1ns / 1ps

module ring_oscillator #(
    parameter STAGE = 3 // must be odd
)(
	output OUT
);

(* dont_touch = "true" *) wire [STAGE:0] w;

assign w[0] = w[STAGE];
genvar i;
generate
    for (i=1; i<=STAGE; i=i+1) begin: pass
        assign w[i] = ~w[i-1];
    end    
endgenerate
assign OUT = w[0];

endmodule

