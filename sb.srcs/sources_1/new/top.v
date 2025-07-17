`timescale 1ns / 1ps

module top (
    input wire BTNU,
    input wire BTNR,
    input wire BTND,
    input wire BTNC,
    input wire BTNL,
    input wire [7:0] SWITCH,
    output wire [7:0] LED
);

wire clk;
wire rst;

wire stopped;

wire [9:0]BRAM_addr;
wire [31:0]BRAM_din;
wire BRAM_en;
wire [3:0]BRAM_we;
wire CLK;

assign request_start = BTNC;
assign rst = BTNR;
assign LED = {7'b1111111, stopped};

block_sSB block_sSB_i (
    .clk            (clk),
    .rst            (rst),
    .request_start  (request_start),
    .stopped        (stopped),

    .BRAM_addr      (BRAM_addr),
    .BRAM_din       (BRAM_din),
    .BRAM_en        (BRAM_en),
    .BRAM_we        (BRAM_we)
);

ps_with_bram ps_with_bram_i (
    .BRAM_addr  (BRAM_addr),
    .BRAM_clk   (BRAM_clk),
    .BRAM_din   (BRAM_din),
    .BRAM_dout  (),
    .BRAM_en    (BRAM_en),
    .BRAM_we    (BRAM_we),
    .CLK        (CLK)
);

endmodule