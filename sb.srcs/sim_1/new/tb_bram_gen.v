`timescale 1ns / 1ps

module tb_bram_gen;

    // Parameters
    parameter WIDTH = 64;      // Changed from 72 to 64
    parameter DEPTH = 1024;
    parameter ADDR_WIDTH = $clog2(DEPTH);
    
    // Clock period
    parameter CLK_PERIOD = 10;
    
    // Test tracking
    integer pass_count = 0;
    integer fail_count = 0;
    integer error_count = 0;
    integer addr = 0;
    
    // Clock generation
    reg clk;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Test signals
    reg [ADDR_WIDTH-1:0] addra;
    reg [WIDTH-1:0] dina;
    wire [WIDTH-1:0] douta;
    reg ena;
    reg wea;
    reg [ADDR_WIDTH-1:0] addrb;
    reg [WIDTH-1:0] dinb;
    wire [WIDTH-1:0] doutb;
    reg enb;
    reg web;
    
    // Instantiate the unit under test
    bram_gen #(
        .WIDTH      (WIDTH),
        .DEPTH      (DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) uut (
        .addra  (addra),
        .clka   (clk),
        .dina   (dina),
        .douta  (douta),
        .ena    (ena),
        .wea    (wea),
        .addrb  (addrb),
        .clkb   (clk),
        .dinb   (dinb),
        .doutb  (doutb),
        .enb    (enb),
        .web    (web)
    );
    
    
    // Test sequence
    initial begin
        // Initialize signals
        clk = 0;
        addra = 0;
        dina = 0;
        ena = 0;
        wea = 0;
        addrb = 0;
        dinb = 0;
        enb = 0;
        web = 0;
        
        // Wait for several clock cycles
        #(CLK_PERIOD * 5);
        
        $display("=== Starting BRAM Test ===");
        
        // Test 1: Port A write and read
        $display("Test 1: Port A write and read");
        ena = 1;
        wea = 1;
        addra = 10;
        dina = {WIDTH{1'b1}}; // All 1s data
        #CLK_PERIOD;
        
        wea = 0;
        #CLK_PERIOD;
        if (douta == {WIDTH{1'b1}}) begin
            $display("PASS: Port A read correct data");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Port A read error, expected: %h, actual: %h", {WIDTH{1'b1}}, douta);
            fail_count = fail_count + 1;
        end
        
        // Test 2: Port B write and read
        $display("Test 2: Port B write and read");
        enb = 1;
        web = 1;
        addrb = 20;
        // Use alternating 1 and 0 pattern
        dinb = 0;
        repeat (WIDTH) begin
            dinb = (dinb << 1) | (dinb[WIDTH-1] ^ 1'b1);
        end
        #CLK_PERIOD;
        
        web = 0;
        #CLK_PERIOD;
        if (doutb == dinb) begin
            $display("PASS: Port B read correct data");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Port B read error, expected: %h, actual: %h", dinb, doutb);
            fail_count = fail_count + 1;
        end
        
        // Test 3: Simultaneous access to different addresses
        $display("Test 3: Dual port simultaneous access to different addresses");
        ena = 1; enb = 1;
        wea = 1; web = 1;
        addra = 100; addrb = 200;
        dina = 64'hAAAA_AAAA_AAAA_AAAA;
        dinb = 64'h5555_5555_5555_5555;
        #CLK_PERIOD;
        
        wea = 0; web = 0;
        #CLK_PERIOD;
        
        if (douta == 64'hAAAA_AAAA_AAAA_AAAA && doutb == 64'h5555_5555_5555_5555) begin
            $display("PASS: Both ports read correct data");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Dual port access error");
            $display("  Port A - expected: %h, actual: %h", 64'hAAAA_AAAA_AAAA_AAAA, douta);
            $display("  Port B - expected: %h, actual: %h", 64'h5555_5555_5555_5555, doutb);
            fail_count = fail_count + 1;
        end
        
        // Test 4: Boundary address test
        $display("Test 4: Boundary address test");
        wea = 1;
        addra = DEPTH - 1; // Maximum address
        dina = 64'h5555_5555_5555_5555;
        #CLK_PERIOD;
        
        wea = 0;
        #CLK_PERIOD;
        if (douta == 64'h5555_5555_5555_5555) begin
            $display("PASS: Maximum address (%d) read correct data", DEPTH-1);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Maximum address read error, expected: %h, actual: %h", 64'h5555_5555_5555_5555, douta);
            fail_count = fail_count + 1;
        end
        
        // Test 5: Enable signal test
        $display("Test 5: Enable signal test");
        // First write a known value
        ena = 1;
        wea = 1;
        addra = 50;
        dina = 64'hDEAD_BEEF_DEAD_BEEF;
        #CLK_PERIOD;
        wea = 0;
        #CLK_PERIOD;
        
        // Now disable and try to read
        ena = 0; // Disable port A
        #CLK_PERIOD;
        
        // Re-enable and verify
        ena = 1;
        #CLK_PERIOD;
        if (douta == 64'hDEAD_BEEF_DEAD_BEEF) begin
            $display("PASS: Port A correctly reads after re-enable");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Port A read after re-enable error, expected: %h, actual: %h", 64'hDEAD_BEEF_DEAD_BEEF, douta);
            fail_count = fail_count + 1;
        end
        
        // Test 6: Consecutive address test
        $display("Test 6: Consecutive address test");
        ena = 1;
        wea = 1;
        for (addr = 0; addr < 10; addr = addr + 1) begin
            addra = addr;
            dina = addr * 64'h1111_1111_1111_1111;
            #CLK_PERIOD;
        end
        
        wea = 0;
        error_count = 0;
        for (addr = 0; addr < 10; addr = addr + 1) begin
            addra = addr;
            #CLK_PERIOD;
            if (douta != addr * 64'h1111_1111_1111_1111) begin
                $display("  Address %d: FAIL - expected: %h, actual: %h", addr, addr * 64'h1111_1111_1111_1111, douta);
                error_count = error_count + 1;
            end
        end
        
        if (error_count == 0) begin
            $display("PASS: All consecutive addresses read correct data");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: %d errors in consecutive address test", error_count);
            fail_count = fail_count + 1;
        end
        
        // Summary of test results
        $display("=== BRAM Test Complete ===");
        $display("SUMMARY: %d tests PASSED, %d tests FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");
            
        #(CLK_PERIOD * 10);
        $finish;
    end
    
    // Monitor signal changes
    initial begin
        $monitor("Time=%t, ena=%b, wea=%b, addra=%d, dina=%h, douta=%h, enb=%b, web=%b, addrb=%d, dinb=%h, doutb=%h",
                 $time, ena, wea, addra, dina, douta, enb, web, addrb, dinb, doutb);
    end

endmodule
