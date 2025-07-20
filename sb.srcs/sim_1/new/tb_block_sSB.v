`timescale 1ns / 1ps

module tb_block_sSB #(
    parameter CLOCK_PERIOD = 10
);

// Clock generation
reg clk = 0;
always #(CLOCK_PERIOD / 2) clk = ~clk;

// Testbench signals
reg request_start = 0;
wire stopped;
wire [9:0] BRAM_addr;
wire [31:0] BRAM_din;
wire BRAM_en;
wire [3:0] BRAM_we;

wire [31:0] read_data;


localparam READ_INDEX_MAX = (2000 - 1) / 32;
reg signed [9:0] read_index;
wire [9:0] read_index_next = read_index + 1;

blk_mem_gen_0 out_bram (
    .clka   (clk),
    .ena    (BRAM_en),
    .wea    (BRAM_we),
    .addra  (BRAM_addr),
    .dina   (BRAM_din),
    .douta  (),
    .clkb   (clk),
    .enb    (1'b1),
    .web    (4'b0000),
    .addrb  (read_index_next),
    .dinb   (0),
    .doutb  (read_data)
);

// Instantiate the block_sSB module
block_sSB #(
    .STEPS   (50),
    .K_BETA  (1),
    .K_XI    (0),
    .K_ETA   (1),
    .K_X     (1),
    .K_Y     (8),
    .K_G     (9)
//   .STEPS   (1000),
//   .K_BETA  (9),
//   .K_XI    (6),
//   .K_ETA   (1),
//   .K_X     (1),
//   .K_Y     (3),
//   .K_G     (3)
) uut (
    .clk            (clk),
    .request_start  (request_start),
    .stopped        (stopped),

    .BRAM_addr      (BRAM_addr),
    .BRAM_din       (BRAM_din),
    .BRAM_en        (BRAM_en),
    .BRAM_we        (BRAM_we)
);

reg wait_for_stop;

initial begin
    // Initialize inputs
    request_start = 0;


    // Wait for a few clock cycles
    #(CLOCK_PERIOD * 2);
    #(CLOCK_PERIOD * 2);
    request_start = 1; // Start the block_sSB operation
    #(CLOCK_PERIOD * 10); // Wait for some time to observe behavior
    request_start = 0; // Stop the block_sSB operation
    #(CLOCK_PERIOD * 80); // Wait for some time to observe behavior
    // Finish simulation
    wait_for_stop = 1;

end


reg is_reading = 0;
always @(posedge clk) begin
    read_index <= -1; // Reset read index
    if (wait_for_stop && stopped && !is_reading) begin
        // Scan the BRAM contents
        $display("BRAM contents after processing:");
        is_reading <= 1;
        read_index <= 0;
    end else if (is_reading) begin
        if (read_index <= READ_INDEX_MAX) begin // Assuming BRAM has 64 entries
            $display("BRAM[%02d]: %b", read_index, read_data);
            read_index <= read_index_next;
        end else begin
            is_reading <= 0; // Stop reading after 64 entries
            $finish; // End simulation
        end
    end
end



endmodule