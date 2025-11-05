`timescale 1ns / 1ps

module tb_rand_lfsr;

reg clk = 0;
always #5 clk = ~clk;


wire [7:0]  out_default;
wire [11:0] out_w12;
wire [4:0]  out_w5;
integer i;


rand_lfsr #(
    .WIDTH  (8),
    .SEED   (1)
) default_lfsr (
    .clk    (clk),
    .out    (out_default)
);

rand_lfsr #(
    .WIDTH  (12),
    .SEED   (12'hACE)
) lfsr_w12 (
    .clk    (clk),
    .out    (out_w12)
);

rand_lfsr #(
    .WIDTH          (5),
    .QUEUE_WIDTH    (8),
    .SEED           (8'h5A)
) lfsr_w5 (
    .clk(clk),
    .out(out_w5)
);

// Stimulus
initial begin
    $display("time\tdefault \tw12         \tw5");
    for (i = 0; i < 16; i = i + 1) begin
        @(posedge clk);
        $display("%0t\t%08b\t%012b\t%05b", $time, out_default, out_w12, out_w5);
    end
    $finish;
end

endmodule
