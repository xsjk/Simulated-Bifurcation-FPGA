`timescale 1ns / 1ps

module top (
    input wire CLK,
    input wire BTNU,
    input wire BTNR,
    input wire BTND,
    input wire BTNC,
    input wire BTNL,
    input wire [7:0] SWITCH,
    output wire [7:0] LED
);

wire rst;

wire stopped;

wire BRAM_ena;
wire BRAM_clka;
wire [11:0]BRAM_addra;
wire [3:0]BRAM_wea;
wire [31:0]BRAM_dina;
wire [31:0]BRAM_douta;

wire BRAM_enb;
wire BRAM_clkb;
wire [9:0]BRAM_addrb;
wire [3:0]BRAM_web;
wire [31:0]BRAM_dinb;
wire [31:0]BRAM_doutb;


wire blink_wire;

assign rst = BTNC;
assign LED = {6'b111111, blink_wire, stopped};

ps_with_bram ps_with_bram_i (
    .BRAM_addr  (BRAM_addra),
    .BRAM_clk   (BRAM_clka),
    .BRAM_din   (BRAM_dina),
    .BRAM_dout  (BRAM_douta),
    .BRAM_en    (BRAM_ena),
    .BRAM_we    (BRAM_wea)
);

block_sSB block_sSB_i (
    .clk            (CLK),
    .request_start  (rst),
    .stopped        (stopped),

    .BRAM_clk       (BRAM_clkb),
    .BRAM_addr      (BRAM_addrb),
    .BRAM_din       (BRAM_dinb),
    .BRAM_dout      (BRAM_doutb),
    .BRAM_en        (BRAM_enb),
    .BRAM_we        (BRAM_web)
);

ps_pl_shared_bram ps_pl_shared_bram_i (
    .A_clk  (BRAM_clka),
    .A_en   (BRAM_ena),
    .A_we   (BRAM_wea),
    .A_addr (BRAM_addra[11:2]),
    .A_din  (BRAM_dina),
    .A_dout (BRAM_douta),
    .B_clk  (BRAM_clkb),
    .B_en   (BRAM_enb),
    .B_we   (BRAM_web),
    .B_addr (BRAM_addrb),
    .B_din  (BRAM_dinb),
    .B_dout (BRAM_doutb)
);

blink blink_i (
    .clk    (CLK),
    .rst    (rst),
    .out    (blink_wire)
);

endmodule