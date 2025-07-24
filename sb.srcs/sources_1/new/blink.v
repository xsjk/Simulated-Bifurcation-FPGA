`timescale 1ns / 1ps

module blink#(
    parameter PERIOD = 'd100_000_000
)(
    input wire clk,
    input wire rst,
    output reg out
);

reg [$clog2(PERIOD+1)-1:0] counter;

initial begin
    out = 0;
    counter = 0;
end

always @(posedge clk) begin
    if (rst) begin
        out <= 0;
        counter <= 0;
    end else if (counter == PERIOD) begin
        out <= ~out;
        counter <= 0;
    end else begin
        counter <= counter + 1;
    end
end

endmodule

