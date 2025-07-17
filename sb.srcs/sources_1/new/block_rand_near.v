`timescale 1ns / 1ps

module block_rand_near #(
    parameter BLOCK_SIZE = 4,
    parameter X_WIDTH = 8,
    parameter K_ETA = 6,
    parameter X_HAT_WIDTH = X_WIDTH - K_ETA
)(
    input wire clk,
    input wire [BLOCK_SIZE*X_WIDTH-1:0] x_fix_i,
    input wire [BLOCK_SIZE*X_WIDTH-1:0] x_fix_j,
    output wire [BLOCK_SIZE*X_HAT_WIDTH-1:0] x_hat_i,
    output wire [BLOCK_SIZE*X_HAT_WIDTH-1:0] x_hat_j
);



endmodule