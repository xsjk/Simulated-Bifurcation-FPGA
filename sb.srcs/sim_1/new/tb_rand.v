`timescale 1ns / 1ps

module tb_rand;

reg clk;
initial clk = 0;
always #5 clk = ~clk;

wire [4:0] rand_out;
rand #(5) uut (clk, rand_out);


always @(posedge clk) begin
    $display("%d", rand_out);
end

initial begin
    #100
    $finish;
end

endmodule
