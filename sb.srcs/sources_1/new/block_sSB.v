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
    output reg [OUT_BRAM_DEPTH-1:0] BRAM_addr,
    output reg [OUT_BRAM_WIDTH-1:0] BRAM_din,
    output reg BRAM_en,
    output reg [3:0] BRAM_we
);

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
    .initialized    (initialized),
    .step           (step),
    .request_stop   (request_stop)
);


// When should the xy_fix_i_packed and x_hat_i_packed_new be updated?
wire should_update = initializing || (running && j == N_BLOCK_PER_ROW - 1);
wire [BLOCK_IDX_WIDTH-1:0] real_block_idx = running ? i : block_idx;


// Memory for x_fix and y_fix
wire [0:BLOCK_SIZE*(X_WIDTH+Y_WIDTH)-1] xy_fix_i_packed;
wire [0:BLOCK_SIZE*(X_WIDTH+Y_WIDTH)-1] xy_fix_i_packed_new;
lutram_gen #(
    .WIDTH      (BLOCK_SIZE * (X_WIDTH + Y_WIDTH)),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) xy_fix_mem (
    .clk    (clk),
    .addr   (real_block_idx),
    .din    (xy_fix_i_packed_new),
    .dout   (xy_fix_i_packed),
    .we     (should_update)
);

// Memory for x_hat
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed; // used for matrix multiplication
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_i_packed_new; // packed x_hat_i_new
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_i_packed; // packed x_hat_i
dual_lutram_gen #(
    .WIDTH      (BLOCK_SIZE * X_HAT_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) x_hat_mem (
    .clk    (clk),
    .addra  (real_block_idx),
    .dina   (x_hat_i_packed_new),
    .wea    (should_update),
    .douta  (x_hat_i_packed),
    .addrb  (j),
    .doutb  (x_hat_j_packed)
);


// Memory for Coefficient Matrix
wire [0:BLOCK_DATA_WIDTH-1] J_local_ij;
wire [0:BLOCK_DATA_WIDTH-1] J_local_ji;
J_block_bram_loader #(
    .N              (N),
    .BLOCK_SIZE     (BLOCK_SIZE)
) J_block_bram_loader_i (
    .clk    (clk),
    .i      (next_i),
    .j      (next_j),
    .out_ij (J_local_ij),
    .out_ji (J_local_ji)
);




// Memory for accumulated vector of the matrix multiplication
wire [0:BLOCK_SIZE*MUL_WIDTH-1] block_matmul_acc_i_packed;
wire [0:BLOCK_SIZE*MUL_WIDTH-1] block_matmul_acc_i_packed_new; // packed block_matmul_acc_i_new
lutram_gen #(
    .WIDTH      (BLOCK_SIZE * MUL_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) block_matmul_acc_mem (
    .clk    (clk),
    .addr   (i),
    .din    (block_matmul_acc_i_packed_new),
    .dout   (block_matmul_acc_i_packed),
    .we     (running)
);



// Block Matrix multiplication
wire [0:BLOCK_SIZE*BLOCK_MUL_WIDTH-1] block_matmul_out_i_packed;
matmul #(
    .N      (BLOCK_SIZE),
    .M      (BLOCK_SIZE),
    .CHUNK  (1)
) matmul_i_ji (
    .J              (J_local_ij),
    .x              (x_hat_j_packed),
    .is_diagonal    (i == j),
    .out            (block_matmul_out_i_packed)
);

wire signed [MUL_WIDTH-1:0] block_matmul_acc_i [0:BLOCK_SIZE-1]; // unpacked block_matmul_acc_i_packed
wire signed [BLOCK_MUL_WIDTH-1:0] block_matmul_out_i [0:BLOCK_SIZE-1]; // unpacked block_matmul_out_i_packed
wire signed [MUL_WIDTH-1:0] block_matmul_acc_i_new [0:BLOCK_SIZE-1]; // block_matmul_acc_i + block_matmul_out_j
generate
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : gen_next_tmp_j
        assign block_matmul_out_i[gi] = block_matmul_out_i_packed[gi*BLOCK_MUL_WIDTH +: BLOCK_MUL_WIDTH];
        assign block_matmul_acc_i[gi] = block_matmul_acc_i_packed[gi*MUL_WIDTH +: MUL_WIDTH];
        assign block_matmul_acc_i_new[gi] = j == 0 ? block_matmul_out_i[gi] : block_matmul_acc_i[gi] + block_matmul_out_i[gi];
        assign block_matmul_acc_i_packed_new[gi*MUL_WIDTH +: MUL_WIDTH] = block_matmul_acc_i_new[gi];
    end
endgenerate



// Combinational logic for dynamics update
wire x_fix_i_init_sign [0:BLOCK_SIZE-1]; // 0 for positive, 1 for negative
wire signed [X_WIDTH-1:0] x_fix_i [0:BLOCK_SIZE-1];
wire signed [X_NEXT_WIDTH:0] x_fix_i_next [0:BLOCK_SIZE-1];
wire signed [X_WIDTH-1:0] x_fix_i_new [0:BLOCK_SIZE-1];
wire signed [X_HAT_WIDTH-1:0] x_hat_i_new [0:BLOCK_SIZE-1];

wire signed [Y_WIDTH-1:0] y_fix_i [0:BLOCK_SIZE-1];
wire signed [Y_WIDTH-1:0] y_fix_i_new [0:BLOCK_SIZE-1];
wire signed [Y_HAT_WIDTH-1:0] y_hat_i [0:BLOCK_SIZE-1];

wire signed [G_WIDTH-1:0] g_fix_i [0:BLOCK_SIZE-1];
wire signed [G_HAT_WIDTH-1:0] g_hat_i [0:BLOCK_SIZE-1];

wire right_out_of_bounds [0:BLOCK_SIZE-1];
wire left_out_of_bounds [0:BLOCK_SIZE-1];

generate 
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : calculate_dynamics

        // Initialization of x_fix_i_init_sign
        if (RANDOM_INIT) begin
            rand #(
                .WIDTH  (1)
            ) r_x_init (
                .clk    (clk),
                .out    (x_fix_i_init_sign[gi])
            );
        end else begin
            assign x_fix_i_init_sign[gi] = 1'b0; // Default to positive 
        end

        // g_fix_i calculation
        assign g_fix_i[gi] = ($signed({1'b0, step}) - (1 << (K_BETA + K_ETA))) * x_fix_i[gi] + 
                             $signed({block_matmul_acc_i_new[gi], {(K_BETA + 2*K_ETA - K_XI){1'b0}}});

        // g_hat_i generation
        rand_near #(
            .WIDTH      (G_WIDTH),
            .OUT_WIDTH  (G_HAT_WIDTH),
            .RAND_WIDTH (2*K_ETA+K_BETA)
        ) r_g_i (
            .clk        (clk),
            .in         (g_fix_i[gi]),
            .out        (g_hat_i[gi])
        );

        // y_fix_i fetch
        assign y_fix_i[gi] = xy_fix_i_packed[gi*(X_WIDTH + Y_WIDTH) + X_WIDTH +: Y_WIDTH];

        // y_hat_i generation
        rand_near #(
            .WIDTH      (Y_WIDTH),
            .OUT_WIDTH  (Y_HAT_WIDTH),
            .RAND_WIDTH (K_ETA)
        ) r_y_i (
            .clk        (clk),
            .in         (y_fix_i[gi]),
            .out        (y_hat_i[gi])
        );

        // x_fix_i fetch 
        assign x_fix_i[gi] = xy_fix_i_packed[gi*(X_WIDTH + Y_WIDTH) +: X_WIDTH];
        assign x_fix_i_next[gi] = x_fix_i[gi] + y_hat_i[gi];

        assign right_out_of_bounds[gi] = x_fix_i_next[gi] > (1 << K_ETA);
        assign left_out_of_bounds[gi] = x_fix_i_next[gi] < -(1 << K_ETA);

        assign x_fix_i_new[gi] = 
            initializing ? (x_fix_i_init_sign[gi] ? -1 : 1) : 
            right_out_of_bounds[gi] ? 1 << K_ETA :
            left_out_of_bounds[gi] ? -1 << K_ETA :
            x_fix_i_next[gi];
            
        assign y_fix_i_new[gi] = 
            initializing ? 0 :
            right_out_of_bounds[gi] || left_out_of_bounds[gi] ? 0 :
            y_fix_i[gi] + g_hat_i[gi];


        // x_hat_i_new generation
        rand_near #(
            .WIDTH      (X_WIDTH),
            .OUT_WIDTH  (X_HAT_WIDTH),
            .RAND_WIDTH  (K_ETA)
        ) r_x_i (
            .clk        (clk),
            .in         (x_fix_i_new[gi]),
            .out        (x_hat_i_new[gi])
        );


        // assign xy_fix_i_packed_new
        assign xy_fix_i_packed_new[gi*(X_WIDTH + Y_WIDTH) +: X_WIDTH] = x_fix_i_new[gi];
        assign xy_fix_i_packed_new[gi*(X_WIDTH + Y_WIDTH) + X_WIDTH +: Y_WIDTH] = y_fix_i_new[gi];
        assign x_hat_i_packed_new[gi*X_HAT_WIDTH +: X_HAT_WIDTH] = x_hat_i_new[gi];

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
                    BRAM_din[k] <= x_hat_i_packed[(read_offset + k) * X_HAT_WIDTH];
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
