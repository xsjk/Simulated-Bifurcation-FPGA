`timescale 1ns / 1ps

module block_sSB  #(
    parameter N = 2000,
    parameter BLOCK_SIZE = 80,
    parameter STEPS = 50000,
    
    parameter N_BLOCK_PER_ROW = N / BLOCK_SIZE, // Number of blocks per row
    
    parameter K_N = $clog2(N+1),                // Width for N
    parameter K_BLOCK = $clog2(BLOCK_SIZE+1),   // Width for block size
    parameter K_BETA = 14,                      // beta = 2^(-K_BETA)
    parameter K_XI = 6,                         // xi = 2^(-K_XI)
    parameter K_ETA = 1,                        // eta = 2^(-K_ETA)
    parameter K_X = 1,                          // |x| < 2^(K_X)
    parameter K_Y = 3,                          // |y| < 2^(K_Y)
    parameter K_G = 3,                          // |g| < 2^(K_G)
    parameter K_ALPHA = 2,                      // |sum(J_ij * x_i)| < 2^(-K_ALPHA) * N

    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW),    // Width for block indices
    parameter BLOCK_DATA_WIDTH = BLOCK_SIZE * BLOCK_SIZE,   // Width for flattened block data
    parameter LOCAL_IDX_WIDTH = $clog2(BLOCK_SIZE),         // Width for inner block index
    parameter STEP_WIDTH = $clog2(STEPS),                   // Width for step
    parameter BLOCK_MUL_WIDTH = 1 + K_BLOCK,                // Width for sum(J_ij * x_i) on block level
    parameter MUL_WIDTH = 1 + K_N - K_ALPHA,                // Width for sum(J_ij * x_i)
    parameter X_WIDTH = 1 + K_X + K_ETA,                    // Width for x
    parameter Y_WIDTH = 1 + K_Y + K_ETA,                    // Width for y
    parameter G_WIDTH = 1 + K_G + (2*K_ETA+K_BETA),         // Width for g
    parameter X_HAT_WIDTH = 1 + K_X,                        // Width for x_hat
    parameter Y_HAT_WIDTH = 1 + K_Y,                        // Width for y_hat
    parameter G_HAT_WIDTH = 1 + K_G,                        // Width for g_hat
    
    parameter X_NEXT_WIDTH = 1 + ((X_HAT_WIDTH > Y_HAT_WIDTH) ? X_HAT_WIDTH : Y_HAT_WIDTH), // Width for x + y_hat

    parameter OUT_BRAM_WIDTH = 32,  // Width of output BRAM
    parameter OUT_BRAM_DEPTH = 10,   // Depth of output BRAM

    parameter WRITE_INDEX_MAX = (N-1)/OUT_BRAM_WIDTH, // Maximum number of write indices
    parameter WRITE_INDEX_WIDTH = $clog2(WRITE_INDEX_MAX+1), // Width for write index

    parameter RANDOM_INIT = 0 // Random initialization of x_fix
)(
    input wire clk,
    input wire request_start,
    output wire stopped,
    output wire BRAM_clk, 
    output reg [OUT_BRAM_DEPTH-1:0] BRAM_addr,
    output reg [OUT_BRAM_WIDTH-1:0] BRAM_din,
    input wire [OUT_BRAM_WIDTH-1:0] BRAM_dout, // unused
    output reg BRAM_en,
    output reg [3:0] BRAM_we
);

assign BRAM_clk = clk;

if (2*K_ETA + K_BETA < K_XI) begin
    $error("2*K_ETA + K_BETA (%d) must be greater than or equal to K_XI (%d)", 2*K_ETA + K_BETA, K_XI);
end

if (OUT_BRAM_DEPTH < WRITE_INDEX_WIDTH) begin
    $error("OUT_BRAM_DEPTH (%d) must be greater than or equal to WRITE_INDEX_WIDTH (%d)", OUT_BRAM_DEPTH, WRITE_INDEX_WIDTH);
end

if (K_X != 1) begin
    $error("K_X (%d) must be equal to 1 since x is always in the range [-1, 1]", K_X);
end

if (OUT_BRAM_DEPTH < $clog2((N-1)/OUT_BRAM_WIDTH+1)) begin
    $error("OUT_BRAM_DEPTH (%d) is not sufficient for N (%d) bits.", OUT_BRAM_DEPTH, N);
end

if (BLOCK_SIZE < OUT_BRAM_WIDTH) begin
    $error("BLOCK_SIZE (%d) must be greater than or equal to OUT_BRAM_WIDTH (%d)", BLOCK_SIZE, OUT_BRAM_WIDTH);
end


// State definitions 
localparam STOPPED = 0;
localparam INIT = 1;
localparam RUNNING = 2;
localparam WRITE = 3;

genvar gi;


// Write index for output BRAM
reg [WRITE_INDEX_WIDTH-1:0] out_idx;

reg [BLOCK_IDX_WIDTH-1:0] block_idx;


// State variables
reg [1:0] state;
assign stopped = (state == STOPPED);
assign running = (state == RUNNING);
assign initializing = (state == INIT);
reg block_idx_rst;

// Block Index 
wire [BLOCK_IDX_WIDTH-1:0] i;
wire [BLOCK_IDX_WIDTH-1:0] j;
wire [BLOCK_IDX_WIDTH-1:0] next_i;
wire [BLOCK_IDX_WIDTH-1:0] next_j;
reg [BLOCK_IDX_WIDTH-1:0] prev_i;
reg [BLOCK_IDX_WIDTH-1:0] prev_j;

always @(posedge clk) begin
    prev_i <= i;
    prev_j <= j;
end

localparam BLOCK_FLAT_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW*(N_BLOCK_PER_ROW+1)/2);
wire [BLOCK_FLAT_IDX_WIDTH-1:0] flat_idx;
wire [BLOCK_FLAT_IDX_WIDTH-1:0] next_flat_idx;

wire initialized;
wire [STEP_WIDTH-1:0] step;
wire request_stop;
block_index_iterator #(
    .N      (N_BLOCK_PER_ROW),
    .STEPS  (STEPS)
) block_index_iterator_i (
    .clk            (clk),
    .rst            (block_idx_rst),
    .i              (i),
    .j              (j),
    .next_i         (next_i),
    .next_j         (next_j),
    .flat_idx       (flat_idx),
    .next_flat_idx  (next_flat_idx),
    .initialized    (initialized),
    .step           (step),
    .request_stop   (request_stop)
);


// When should the x_fix_j_packed and y_fix_j_packed and x_hat_j_packed_new be updated?
wire should_update = initializing || (running && i == N_BLOCK_PER_ROW - 1);
wire [BLOCK_IDX_WIDTH-1:0] real_block_idx = running ? j : block_idx;


// Memory for x_fix and y_fix
wire [0:BLOCK_SIZE*X_WIDTH-1] x_fix_j_packed;
wire [0:BLOCK_SIZE*X_WIDTH-1] x_fix_j_packed_new;
lutram_gen #(
    .WIDTH      (BLOCK_SIZE * X_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) x_fix_mem (
    .clk    (clk),
    .addr   (real_block_idx),
    .din    (x_fix_j_packed_new),
    .dout   (x_fix_j_packed),
    .we     (should_update)
);

wire [0:BLOCK_SIZE*Y_WIDTH-1] y_fix_j_packed;
wire [0:BLOCK_SIZE*Y_WIDTH-1] y_fix_j_packed_new;
lutram_gen #(
    .WIDTH      (BLOCK_SIZE * Y_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) y_fix_mem (
    .clk    (clk),
    .addr   (real_block_idx),
    .din    (y_fix_j_packed_new),
    .dout   (y_fix_j_packed),
    .we     (should_update)
);

// Memory for x_hat
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed; // used for matrix multiplication
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed_new; // packed x_hat_i_new
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_i_packed; // packed x_hat_i
dual_lutram_gen #(
    .WIDTH      (BLOCK_SIZE * X_HAT_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) x_hat_mem (
    .clk    (clk),
    .addra  (real_block_idx),
    .dina   (x_hat_j_packed_new),
    .wea    (should_update),
    .douta  (x_hat_j_packed),
    .addrb  (i),
    .doutb  (x_hat_i_packed)
);


// Memory for Coefficient Matrix
wire [0:BLOCK_DATA_WIDTH-1] J_local_ij;
wire [0:BLOCK_DATA_WIDTH-1] J_local_ji;
J_mem #(
    .N              (N),
    .BLOCK_SIZE     (BLOCK_SIZE)
) J_mem_i (
    .clk            (clk),
    .idx            (next_flat_idx),
    .lower_block    (J_local_ij), // TODO
    .upper_block    (J_local_ji)
);


// Block Matrix multiplication
wire [0:BLOCK_SIZE*BLOCK_MUL_WIDTH-1] block_matmul_out_i_packed;
wire [0:BLOCK_SIZE*BLOCK_MUL_WIDTH-1] block_matmul_out_j_packed;
matmul #(
    .N      (BLOCK_SIZE),
    .M      (BLOCK_SIZE),
    .CHUNK  (1)
) matmul_ij (
    .J              (J_local_ij),
    .x              (x_hat_j_packed),
    .is_diagonal    (i == j),
    .out            (block_matmul_out_i_packed)
);
matmul #(
    .N      (BLOCK_SIZE),
    .M      (BLOCK_SIZE),
    .CHUNK  (1)
) matmul_ji (
    .J              (J_local_ji),
    .x              (x_hat_i_packed),
    .is_diagonal    (i == j),
    .out            (block_matmul_out_j_packed)
);

wire [0:BLOCK_SIZE*MUL_WIDTH-1] L_i_packed; // packed L_i 
wire [0:BLOCK_SIZE*MUL_WIDTH-1] L_j_packed; // packed L_j
L_mem #(
    .N                  (N),
    .BLOCK_SIZE         (BLOCK_SIZE),
    .N_BLOCK_PER_ROW    (N_BLOCK_PER_ROW),
    .BLOCK_IDX_WIDTH    (BLOCK_IDX_WIDTH),
    .BLOCK_MUL_WIDTH    (BLOCK_MUL_WIDTH),
    .MUL_WIDTH          (MUL_WIDTH)
) L_mem_i (
    .clk                (clk),
    .en                 (running),
    .i                  (i),
    .j                  (j),
    .next_i             (next_i),
    .next_j             (next_j),
    .delta_L_i_packed   (block_matmul_out_i_packed),
    .delta_L_j_packed   (block_matmul_out_j_packed),
    .L_i_packed_new     (L_i_packed),  // unused
    .L_j_packed_new     (L_j_packed)
);

// unpacked L_j
wire signed [0:MUL_WIDTH-1] L_j [0:BLOCK_SIZE-1];
wire signed [0:MUL_WIDTH-1] L_i [0:BLOCK_SIZE-1];
generate
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : unpack_L_j
        assign L_i[gi] = L_i_packed[gi*MUL_WIDTH +: MUL_WIDTH];
        assign L_j[gi] = L_j_packed[gi*MUL_WIDTH +: MUL_WIDTH];
    end
endgenerate


// Combinational logic for dynamics update
wire x_fix_j_init_sign [0:BLOCK_SIZE-1]; // 0 for positive, 1 for negative
wire signed [X_WIDTH-1:0] x_fix_j [0:BLOCK_SIZE-1];
wire signed [X_NEXT_WIDTH:0] x_fix_j_next [0:BLOCK_SIZE-1];
wire signed [X_WIDTH-1:0] x_fix_j_new [0:BLOCK_SIZE-1];
wire signed [X_HAT_WIDTH-1:0] x_hat_j_new [0:BLOCK_SIZE-1];

wire signed [Y_WIDTH-1:0] y_fix_j [0:BLOCK_SIZE-1];
wire signed [Y_WIDTH-1:0] y_fix_j_new [0:BLOCK_SIZE-1];
wire signed [Y_HAT_WIDTH-1:0] y_hat_j [0:BLOCK_SIZE-1];

wire signed [G_WIDTH-1:0] g_fix_j [0:BLOCK_SIZE-1];
wire signed [G_HAT_WIDTH-1:0] g_hat_j [0:BLOCK_SIZE-1];

wire right_out_of_bounds [0:BLOCK_SIZE-1];
wire left_out_of_bounds [0:BLOCK_SIZE-1];

generate 
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : calculate_dynamics

        // Initialization of x_fix_j_init_sign
        if (RANDOM_INIT) begin
            rand #(
                .WIDTH  (1)
            ) r_x_init (
                .clk    (clk),
                .out    (x_fix_j_init_sign[gi])
            );
        end else begin
            assign x_fix_j_init_sign[gi] = 1'b0; // Default to positive 
        end

        // g_fix_j calculation
        assign g_fix_j[gi] = ($signed({1'b0, step}) - (1 << (K_BETA + K_ETA))) * x_fix_j[gi] + 
                              $signed({L_j[gi], {(K_BETA + 2*K_ETA - K_XI){1'b0}}});

        // g_hat_j generation
        rand_near #(
            .WIDTH      (G_WIDTH),
            .OUT_WIDTH  (G_HAT_WIDTH),
            .RAND_WIDTH (2*K_ETA+K_BETA)
        ) r_g_i (
            .clk        (clk),
            .in         (g_fix_j[gi]),
            .out        (g_hat_j[gi])
        );

        // y_fix_j fetch
        assign y_fix_j[gi] = y_fix_j_packed[gi*Y_WIDTH +: Y_WIDTH];

        // y_hat_j generation
        rand_near #(
            .WIDTH      (Y_WIDTH),
            .OUT_WIDTH  (Y_HAT_WIDTH),
            .RAND_WIDTH (K_ETA)
        ) r_y_i (
            .clk        (clk),
            .in         (y_fix_j[gi]),
            .out        (y_hat_j[gi])
        );

        // x_fix_j fetch 
        assign x_fix_j[gi] = x_fix_j_packed[gi*X_WIDTH +: X_WIDTH];
        assign x_fix_j_next[gi] = x_fix_j[gi] + y_hat_j[gi];

        assign right_out_of_bounds[gi] = x_fix_j_next[gi] > (1 << K_ETA);
        assign left_out_of_bounds[gi] = x_fix_j_next[gi] < -(1 << K_ETA);

        assign x_fix_j_new[gi] = 
            initializing ? (x_fix_j_init_sign[gi] ? -1 : 1) : 
            right_out_of_bounds[gi] ? 1 << K_ETA :
            left_out_of_bounds[gi] ? -1 << K_ETA :
            x_fix_j_next[gi];
            
        assign y_fix_j_new[gi] = 
            initializing ? 0 :
            right_out_of_bounds[gi] || left_out_of_bounds[gi] ? 0 :
            y_fix_j[gi] + g_hat_j[gi];


        // x_hat_i_new generation
        rand_near #(
            .WIDTH      (X_WIDTH),
            .OUT_WIDTH  (X_HAT_WIDTH),
            .RAND_WIDTH  (K_ETA)
        ) r_x_i (
            .clk        (clk),
            .in         (x_fix_j_new[gi]),
            .out        (x_hat_j_new[gi])
        );


        // assign packed wires
        assign y_fix_j_packed_new[gi*Y_WIDTH +: Y_WIDTH] = y_fix_j_new[gi];
        assign x_fix_j_packed_new[gi*X_WIDTH +: X_WIDTH] = x_fix_j_new[gi];
        assign x_hat_j_packed_new[gi*X_HAT_WIDTH +: X_HAT_WIDTH] = x_hat_j_new[gi];

    end
endgenerate



// Sequential logic of the state machine

reg [K_N-1:0] read_begin;
reg [K_N-1:0] write_begin;
wire [K_N:0] read_end = read_begin + BLOCK_SIZE;
wire [K_N:0] write_end = write_begin + OUT_BRAM_WIDTH;
reg signed [LOCAL_IDX_WIDTH:0] read_offset;

initial begin
    state <= STOPPED;
    block_idx <= 0;
    out_idx <= 0;

    read_begin <= 0;
    write_begin <= 0;
    read_offset <= 0;

    BRAM_addr <= 0;
    BRAM_din <= 0;
    BRAM_en <= 0;
    BRAM_we <= 0;

    block_idx_rst <= 0;
end

integer k;
always @(posedge clk) begin

    block_idx_rst <= 1'b0;
    
    // State machine
    case (state)
        STOPPED: begin
            if (request_start) begin
                state <= INIT;
                block_idx <= 0;
            end
        end

        INIT: begin
            if (block_idx == N_BLOCK_PER_ROW - 1) begin
                state <= RUNNING;
            end else begin
                block_idx <= block_idx + 1;
                block_idx_rst <= 1'b1; 
            end
        end
        
        RUNNING: begin

            // $display("(i, j) = (%2d, %2d)", i, j);

            // // Display x_hat_j_packed and x_hat_i_packed
            // $write("x_hat_i = [");
            // for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //     $write("%2d,", $signed(x_hat_i_packed[k*X_HAT_WIDTH +: X_HAT_WIDTH]));
            // $write("]\n");
            // $write("x_hat_j = [");
            // for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //     $write("%2d,", $signed(x_hat_j_packed[k*X_HAT_WIDTH +: X_HAT_WIDTH]));
            // $write("]\n");

            // // Display the matmul output
            // $write("delta_L_i = Jij x_hat_j = [");
            // for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //     $write("%3d,", $signed(block_matmul_out_i_packed[k*BLOCK_MUL_WIDTH +: BLOCK_MUL_WIDTH]));
            // $write("]\n");
            // $write("delta_L_j = Jji x_hat_i = [");
            // for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //     $write("%3d,", $signed(block_matmul_out_j_packed[k*BLOCK_MUL_WIDTH +: BLOCK_MUL_WIDTH]));
            // $write("]\n");

            // // Display the updated L_i and L_j
            // $write("Updated L_i = [");
            // for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //     $write("%3d,", $signed(L_i[k]));
            // $write("]\n");
            // $write("Updated L_j = [");
            // for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //     $write("%3d,", $signed(L_j[k]));
            // $write("]\n");

            // $write("\n");
                

            // // Display x_hat
            // if (j == 0) begin
            //     if (i == 0) begin
            //         $write("x_hat = [");
            //     end
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //         $write("%2d,", $signed(x_hat_i_packed[k*X_HAT_WIDTH +: X_HAT_WIDTH]));
            //     if (i == N_BLOCK_PER_ROW - 1) begin
            //         $write("]");
            //     end
            //     $write("\n");
            // end

            // // Display L
            // if (i == N_BLOCK_PER_ROW - 1) begin
            //     if (j == 0) begin
            //         $write("L = [");
            //     end
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //         $write("%3d,", $signed(L_j[k]));
            //     if (j == N_BLOCK_PER_ROW - 1) begin
            //         $write("]");
            //     end
            //     $write("\n");
            // end 
            

            if (i == N_BLOCK_PER_ROW - 1 && j == N_BLOCK_PER_ROW - 1 && request_stop) begin
                state <= WRITE;
                            
                read_begin <= 0;
                write_begin <= 0;
                read_offset <= 0;
                block_idx <= 0;
                out_idx <= 0;

                BRAM_addr <= 0;
                BRAM_din <= 0;
                BRAM_en <= 0;
                BRAM_we <= 0;
            end

        end
        
        WRITE: begin  
            
            // Fetch the sign of x and pack to BRAM_din
            for (k = 0; k < OUT_BRAM_WIDTH; k = k + 1) begin
                if (write_begin + k < read_begin) begin
                    BRAM_din[k] <= BRAM_din[k]; // Keep the previous value
                end else if (write_begin + k < read_end) begin
                    BRAM_din[k] <= x_hat_j_packed[(read_offset + k) * X_HAT_WIDTH];
                end else begin
                    BRAM_din[k] <= 0; // Fill the rest with zeros
                end
            end

            if (out_idx > WRITE_INDEX_MAX) begin
                state <= STOPPED; // Stop after writing the last block
            end
            
            // Default values for BRAM
            BRAM_addr <= out_idx;
            BRAM_we <= 4'b1111;
            BRAM_en <= 1;

            if (write_end > read_end) begin
                /*
                 *  read:  |<------------------->|
                 *  write:              |<--------->|
                 */
                // Next read block
                block_idx <= block_idx + 1;
                read_begin <= read_begin + BLOCK_SIZE;
                read_offset <= read_offset - BLOCK_SIZE;

                // Don't write to BRAM at this moment, since BRAM_din is not completely filled
                BRAM_we <= 0;
                
            end else if (write_begin < read_begin) begin
                /*
                 *  read:      |<------------------->|
                 *  write: |<--------->|
                 */
                // Next write index
                out_idx <= out_idx + 1;
                write_begin <= write_begin + OUT_BRAM_WIDTH;
                read_offset <= read_offset + OUT_BRAM_WIDTH;

            end else begin
                /*
                 *  read:  |<------------------->|
                 *  write:     |<--------->|
                 */
                // Next write index
                out_idx <= out_idx + 1;
                write_begin <= write_begin + OUT_BRAM_WIDTH;
                read_offset <= read_offset + OUT_BRAM_WIDTH;
            end
        end
    endcase

end


endmodule
