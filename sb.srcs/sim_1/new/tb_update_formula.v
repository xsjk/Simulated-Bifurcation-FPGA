`timescale 1ns / 1ps

module tb_update_formula;


parameter CLK_PERIOD = 10;
reg clk;
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end



parameter X_WIDTH = 4;
parameter Y_WIDTH = 6;
parameter G_WIDTH = 10; 
parameter STEP_WIDTH = 15; 
parameter MUL_WIDTH = 11;
parameter SHIFT_ETA = 2;
parameter SHIFT_BETA = 11;
parameter SHIFT_XI = 7; 

parameter BLOCK_SIZE = 80; // Size of the block

signed reg [X_WIDTH-1:0] x_local_j;
signed reg [Y_WIDTH-1:0] y_local_j;
signed reg [G_WIDTH-1:0] g_local_j;
reg [STEP_WIDTH-1:0] step;


initial begin
    // Initialize the registers
    x_local_j = 0;
    y_local_j = 0;
    g_local_j = 0;
    step = 0;
end


always @(*) begin
    // Update g_local_j based on the formula
    // g = -(1 - beta * t) * x_local_j + xi * y_local_j
                
    // where beta is assumed to be 1 for simplicity in this example
    // and xi is assumed to be 1 for simplicity in this example


    // g_ = -(1 - beta * t) * x[idx] + xi * tmp[idx]  # maybe use assign?
    // x_ = x[idx] + y[idx] * eta  # maybe use assign?

    // tmp[idx] = 0

    // if x_ > 1:
    //     x[idx] = 1
    //     y[idx] = 0
    // elif x_ < -1:
    //     x[idx] = -1
    //     y[idx] = 0
    // else:
    //     x[idx] = x_
    //     y[idx] = y[idx] + g_

    g_local_j = (($signed(1 << (SHIFT_ETA + SHIFT_BETA)) - $signed(step)) // (SHIFT_ETA + SHIFT_BETA) decimal
                 * $signed(x_local_j) >> (SHIFT_ETA + SHIFT_BETA)) // (SHIFT_ETA) decimal
                + ($signed(y_local_j >> SHIFT_XI)); // (SHIFT_ETA) decimal



    // Ensure g_local_j does not exceed its maximum value

    // Display the updated value of g_local_j
    $display("g_local_j: %b", g_local_j);

end




initial begin
    x_local_j = 4'b1010; // Example value for x_local_j
    y_local_j = 6'b110011; // Example value for y_local_j
    g_local_j = 10'b0000000001; // Example value for g_local_j
    step = 15'b000000000000001; // Example value for step

    #1

    $display
end




endmodule