`timescale 1ns / 1ps

module tb_rand_near;

reg clk;
reg rst;
reg [2:0] din;
wire [1:0] dout;

rand_near #(
    .WIDTH      (3),
    .RAND_WIDTH (1)
) uut (
    .clk    (clk),
    .rst    (rst),
    .din    (din),
    .dout   (dout)
);

integer i;
initial begin
    clk = 0;
    din = 0;
    rst = 1;
    #10;
    rst = 0;

    din = 3'b111;
    for (i = 0; i < 10; i = i + 1) begin
        #10;
        $display("Output when din = 111: %b", dout);
    end

    din = 3'b000;
    for (i = 0; i < 10; i = i + 1) begin
        #10;
        $display("Output when din = 000: %b", dout);
    end
    #10;

    // Finish simulation
    $finish;
end

always #5 clk = ~clk;

endmodule