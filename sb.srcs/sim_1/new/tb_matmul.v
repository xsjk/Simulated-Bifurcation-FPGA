`timescale 1ns / 1ps

module tb_matmul;

parameter N = 2;
parameter M = 3;
parameter WIDTH = 11;

reg [0:M*2-1] x;
reg [0:N*M*1-1] J;
wire [0:N*WIDTH-1] out;
reg clk;

matmul #(
    .N      (N),
    .M      (M),
    .WIDTH  (WIDTH)
) uut (
    .clk    (clk),
    .x      (x),
    .J      (J),
    .out    (out)
);
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end 

integer i;

initial begin
    #5;
        
    x = 6'b011100;  // [1,-1,0]
    J = 6'b110010;  // [[-1,-1,1],[1,-1,1]]
    #5; // first clk
    #5;
    
    J = 6'b010000;  // [[1,-1,1],[1,1,1]]
    #5; // second clk
    #5;
    
    
    x = 6'b010100;  // [1,1,0]
    J = 6'b111010;  // [[-1,-1,-1],[1,-1,1]]
    #5; // third clk
    #5;
    
    J = 6'b010000;  // [[1,-1,1],[1,1,1]]
    #5; // fourth clk
    #5;
    
    #5; // fifth clk
    #5;
    
    #5;
    $finish;

end

integer t;
initial begin

    #6;

    for (t = 0; t < 10; t = t + 1) begin
        $write("t=%d, out=[", t);
        for (i = 0; i < N; i = i+1) begin
            $write("%d,", $signed(out[i*WIDTH +: WIDTH]));
        end
        $write("]\n");

        #10;
    end

end

endmodule