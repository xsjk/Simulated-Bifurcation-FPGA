`timescale 1ns / 1ps

module block_sSB  #(
    parameter N = 2000,
    parameter BLOCK_SIZE = 80,
    parameter STEPS = 50000,
        
    parameter K_N = $clog2(N+1),                // Width for N
    parameter K_BLOCK = $clog2(BLOCK_SIZE+1),   // Width for block size
    parameter K_BETA = 14,                      // beta = 2^(-K_BETA)
    parameter K_XI = 6,                         // xi = 2^(-K_XI)
    parameter K_ETA = 1,                        // eta = 2^(-K_ETA)
    parameter K_X = 1,                          // |x| < 2^(K_X)
    parameter K_Y = 3,                          // |y| < 2^(K_Y)
    parameter K_G = 3,                          // |g| < 2^(K_G)
    parameter K_ALPHA = 2,                      // |sum(J_ij * x_i)| < 2^(-K_ALPHA) * N

    parameter ENABLE_G_HAT = 1, // Enable stocastic update of g
    parameter ENABLE_Y_HAT = 1, // Enable stocastic update of y

    parameter BLOCK_MATMUL_LEVEL1 = 12,
    parameter BLOCK_MATMUL_LEVEL2 = 4,

    parameter OUT_BRAM_WIDTH = 32,  // Width of output BRAM
    parameter OUT_BRAM_DEPTH = 10,   // Depth of output BRAM

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

// Derived parameters
localparam N_BLOCK_PER_ROW = N / BLOCK_SIZE; // Number of blocks per row

localparam BLOCK_MUL_WIDTH = 1 + K_BLOCK; // Width for sum(J_ij * x_i) on block level
localparam MUL_WIDTH = 1 + K_N - K_ALPHA; // Width for sum(J_ij * x_i)

localparam G_DECIMAL = 2*K_ETA + K_BETA;
localparam Y_DECIMAL = ENABLE_G_HAT ? K_ETA : G_DECIMAL + K_ETA;
localparam X_DECIMAL = ENABLE_Y_HAT ? K_ETA : Y_DECIMAL + K_BETA;
localparam X_WIDTH = 1 + K_X + X_DECIMAL;   // Width for x
localparam Y_WIDTH = 1 + K_Y + Y_DECIMAL;   // Width for y
localparam G_WIDTH = 1 + K_G + G_DECIMAL;   // Width for g
localparam X_ABS_MAX = 1 << X_DECIMAL;      // Maximum absolute value for x
localparam X_HAT_WIDTH = 1 + K_X;           // Width for x_hat
localparam Y_HAT_WIDTH = 1 + K_Y;           // Width for y_hat
localparam G_HAT_WIDTH = 1 + K_G;           // Width for g_hat
localparam X_DELTA_WIDTH = ENABLE_Y_HAT ? Y_HAT_WIDTH : Y_WIDTH;
localparam Y_DELTA_WIDTH = ENABLE_G_HAT ? G_HAT_WIDTH : G_WIDTH;
localparam X_NEXT_WIDTH = 1 + ((X_WIDTH > X_DELTA_WIDTH) ? X_WIDTH : X_DELTA_WIDTH); // Width for x + eta y
localparam Y_NEXT_WIDTH = 1 + ((Y_WIDTH > Y_DELTA_WIDTH) ? Y_WIDTH : Y_DELTA_WIDTH); // Width for y + eta g

localparam BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW);    // Width for block indices
localparam BLOCK_DATA_WIDTH = BLOCK_SIZE * BLOCK_SIZE;   // Width for flattened block data
localparam LOCAL_IDX_WIDTH = $clog2(BLOCK_SIZE);         // Width for inner block index
localparam STEP_WIDTH = $clog2(STEPS);                   // Width for step

localparam WRITE_INDEX_MAX = (N-1)/OUT_BRAM_WIDTH;          // Maximum number of write indices
localparam WRITE_INDEX_WIDTH = $clog2(WRITE_INDEX_MAX+1);   // Width for write index


// State definitions 
localparam STOPPED = 0;
localparam INIT = 1;
localparam RUNNING = 2;
localparam WRITE = 3;

genvar gi;


// Write index for output BRAM
reg [WRITE_INDEX_WIDTH-1:0] out_idx;

// Read addr of x_hat_j during writing phase 
// Also gives the write address for x_fix, y_fix, x_hat during initialization phase
reg [BLOCK_IDX_WIDTH-1:0] block_idx;


// State variables
reg [1:0] state;
assign stopped = (state == STOPPED);
assign initializing = (state == INIT);
assign running = (state == RUNNING);
assign writing = (state == WRITE);

localparam BLOCK_FLAT_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW*(N_BLOCK_PER_ROW+1)/2);

// Block Index 
localparam MAX_STAGE = 12;
wire [BLOCK_IDX_WIDTH-1:0] i;
wire [BLOCK_IDX_WIDTH-1:0] j;
wire [BLOCK_FLAT_IDX_WIDTH-1:0] flat_idx;
wire request_stop;

reg [BLOCK_IDX_WIDTH-1:0] stage_i [0:MAX_STAGE];
reg [BLOCK_IDX_WIDTH-1:0] stage_j [0:MAX_STAGE];
reg [BLOCK_FLAT_IDX_WIDTH-1:0] stage_flat_idx [0:MAX_STAGE];
reg stage_is_diagonal [0:MAX_STAGE];
reg stage_request_stop [0:MAX_STAGE];
always @(*) begin
    stage_i[0] = i;
    stage_j[0] = j;
    stage_flat_idx[0] = flat_idx;
    stage_request_stop[0] = request_stop;
    stage_is_diagonal[0] = (i == j);
end


wire [STEP_WIDTH-1:0] step;
reg idx_iterator_rst;
block_index_iterator #(
    .N      (N_BLOCK_PER_ROW),
    .STEPS  (STEPS)
) block_index_iterator_i (
    .clk            (clk),
    .rst            (idx_iterator_rst),
    .i              (i), // row of the block
    .j              (j), // col of the block
    .flat_idx       (flat_idx), // flat index for J memory access
    .step           (step), // number of iterations completed
    .request_stop   (request_stop) // signal when step == STEPS
);
genvar gs;
generate
    for (gs = 0; gs < MAX_STAGE; gs = gs + 1) begin : gen_stage_reg
        always @(posedge clk) begin
            stage_i[gs+1] <= stage_i[gs];
            stage_j[gs+1] <= stage_j[gs];
            stage_flat_idx[gs+1] <= stage_flat_idx[gs];
            stage_request_stop[gs+1] <= stage_request_stop[gs];
            stage_is_diagonal[gs+1] <= stage_is_diagonal[gs];
        end
    end
endgenerate


localparam BLOCK_MATMUL_PROGREG = 1;
localparam BLOCK_MATMUL_LEVEL1REG = 1;
localparam BLOCK_MATMUL_LEVEL2REG = 1;
localparam BLOCK_MATMUL_OUTREG = 1;

localparam STAGE_X_LOAD = 6;
localparam STAGE_Y_LOAD = 6;
localparam STAGE_X_HAT_LOAD = 2;
localparam STAGE_J_LOAD = 1; 

localparam STAGE_X_ARRIVE = STAGE_X_LOAD;
localparam STAGE_Y_ARRIVE = STAGE_Y_LOAD;
localparam STAGE_X_HAT_ARRIVE = STAGE_X_HAT_LOAD;
localparam STAGE_J_ARRIVE = STAGE_J_LOAD + 1;

// Block Matrix multiplication
if (STAGE_J_ARRIVE != STAGE_X_HAT_ARRIVE) begin
    $error("Error: Input stages of J * x_hat doesnot match");
end

localparam STAGE_MATMUL_OUT = STAGE_J_ARRIVE + BLOCK_MATMUL_PROGREG + BLOCK_MATMUL_LEVEL1REG + BLOCK_MATMUL_LEVEL2REG + BLOCK_MATMUL_OUTREG;
localparam STAGE_L_ARRIVE = STAGE_MATMUL_OUT;

if (STAGE_L_ARRIVE != STAGE_X_ARRIVE) begin
    $error("Error: Input stages of g = g(L, x) doesnot match");
end

localparam STAGE_G_ARRIVE = STAGE_L_ARRIVE;
localparam STAGE_G_HAT_ARRIVE = STAGE_G_ARRIVE;

if (STAGE_G_HAT_ARRIVE != STAGE_Y_ARRIVE) begin
    $error("Error: Input stages of y += g_hat doesnot match");
end

localparam STAGE_Y_NEXT_ARRIVE = STAGE_Y_ARRIVE; 
localparam STAGE_Y_SGN_ARRIVE = STAGE_Y_NEXT_ARRIVE;

if (STAGE_Y_SGN_ARRIVE != STAGE_X_ARRIVE) begin
    $error("Error: Input stages of x += y_sgn doesnot match");
end

localparam STAGE_X_NEXT_ARRIVE = STAGE_Y_SGN_ARRIVE;
localparam STAGE_OOB_ARRIVE = STAGE_X_NEXT_ARRIVE;

if (STAGE_OOB_ARRIVE != STAGE_X_NEXT_ARRIVE) begin
    $error("Error: Input stages of x_new = oob ? -1/+1 : x_next doesnot match");
end
localparam STAGE_X_NEW_ARRIVE = STAGE_OOB_ARRIVE;

if (STAGE_OOB_ARRIVE != STAGE_X_NEXT_ARRIVE) begin
    $error("Error: Input stages of y_new = oob ? 0 : y_next doesnot match");
end
localparam STAGE_Y_NEW_ARRIVE = STAGE_OOB_ARRIVE;

localparam STAGE_X_HAT_NEW_ARRIVE = STAGE_X_NEW_ARRIVE;


// Stage indices for the block index iterator
// store multi stages of block_idx to handle different storing stage of x_fix, y_fix, x_hat during initialization phase
reg [BLOCK_IDX_WIDTH-1:0] stage_init_block_idx [STAGE_X_NEXT_ARRIVE:STAGE_X_HAT_NEW_ARRIVE]; 
always @(*) stage_init_block_idx[STAGE_X_NEXT_ARRIVE] = block_idx;
generate
    for (gs = STAGE_X_NEXT_ARRIVE; gs < STAGE_X_HAT_NEW_ARRIVE; gs = gs + 1) begin : gen_stage_block_idx
        always @(posedge clk) stage_init_block_idx[gs+1] <= stage_init_block_idx[gs];
    end
endgenerate



// Memory for x_fix and y_fix
wire [0:BLOCK_SIZE*X_WIDTH-1] x_fix_j_packed;
wire [0:BLOCK_SIZE*X_WIDTH-1] x_fix_j_packed_new;
lutram_gen #(
    .WIDTH      (BLOCK_SIZE * X_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) x_fix_mem (
    .clk    (clk),
    .addr   (initializing ? stage_init_block_idx[STAGE_X_NEXT_ARRIVE] : // writes when x_next arrives
             running ? stage_j[STAGE_X_LOAD] : 
             0), // unused during writing phase
    .din    (x_fix_j_packed_new),
    .dout   (x_fix_j_packed),
    .we     (initializing ? 1'b1 : // write during initialization
             running ? stage_i[STAGE_X_LOAD] == N_BLOCK_PER_ROW - 1 : // write only at the last block of the column
             1'b0) // disabled during writing phase
);

wire [0:BLOCK_SIZE*Y_WIDTH-1] y_fix_j_packed;
wire [0:BLOCK_SIZE*Y_WIDTH-1] y_fix_j_packed_new;
lutram_gen #(
    .WIDTH      (BLOCK_SIZE * Y_WIDTH),
    .DEPTH      (N_BLOCK_PER_ROW),
    .ADDR_WIDTH (BLOCK_IDX_WIDTH)
) y_fix_mem (
    .clk    (clk),
    .addr   (initializing ? stage_init_block_idx[STAGE_Y_NEXT_ARRIVE] : // writes when x_next arrives
             running ? stage_j[STAGE_Y_LOAD] : 
             0), // unused during writing phase
    .din    (y_fix_j_packed_new),
    .dout   (y_fix_j_packed),
    .we     (initializing ? 1'b1 : // always write during initialization
             running ? stage_i[STAGE_Y_LOAD] == N_BLOCK_PER_ROW - 1 : // write only at the last block of the column
             1'b0) // disabled during writing phase
);

// Memory for x_hat
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_i_packed; // packed x_hat_i
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed; // packed x_hat_j
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_k_packed; // packed x_hat_k
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed_new; // packed x_hat_j_new
x_hat_mem #(
    .BLOCK_SIZE         (BLOCK_SIZE),
    .N_BLOCK_PER_ROW    (N_BLOCK_PER_ROW),
    .BLOCK_IDX_WIDTH    (BLOCK_IDX_WIDTH),
    .X_HAT_WIDTH        (X_HAT_WIDTH)
) x_hat_mem_i (
    .clk    (clk),
    .i      (stage_i[STAGE_X_HAT_LOAD]),
    .j      (stage_j[STAGE_X_HAT_LOAD]),
    .k      (initializing ? stage_init_block_idx[STAGE_X_HAT_NEW_ARRIVE] : 
             running ? stage_j[STAGE_X_HAT_NEW_ARRIVE] : 
             block_idx), // during writing phase, read based on block_idx
    .we_k   (initializing ? 1'b1 : // always write during initialization phase
             running ? stage_i[STAGE_X_HAT_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1 : // write only at the last block of the column
             writing ? 1'b0 : // always read during writing phase
             1'b0),
    .dout_i (x_hat_i_packed), // used as input for matrix multiplication
    .dout_j (x_hat_j_packed), // used as input for matrix multiplication
    .din_k  (x_hat_j_packed_new), // provided by dynamics update
    .dout_k (x_hat_k_packed) // used as input during writing phase
);

// Memory for Coefficient Matrix
wire [0:BLOCK_DATA_WIDTH-1] J_local_ij;
wire [0:BLOCK_DATA_WIDTH-1] J_local_ji;
J_mem #(
    .N              (N),
    .BLOCK_SIZE     (BLOCK_SIZE)
) J_mem_i (
    .clk            (clk),
    .idx            (stage_flat_idx[STAGE_J_LOAD]),
    .lower_block    (J_local_ij),
    .upper_block    (J_local_ji)
);

wire [0:BLOCK_SIZE*BLOCK_MUL_WIDTH-1] block_matmul_out_i_packed;
wire [0:BLOCK_SIZE*BLOCK_MUL_WIDTH-1] block_matmul_out_j_packed;
matmul #(
    .N                  (BLOCK_SIZE),
    .M                  (BLOCK_SIZE),
    .LEVEL1_GROUPS      (BLOCK_MATMUL_LEVEL1),
    .LEVEL2_GROUPS      (BLOCK_MATMUL_LEVEL2),
    .ENABLE_PRODREG     (BLOCK_MATMUL_PROGREG),
    .ENABLE_LEVEL1REG   (BLOCK_MATMUL_LEVEL1REG),
    .ENABLE_LEVEL2REG   (BLOCK_MATMUL_LEVEL2REG),
    .ENABLE_OUTREG      (BLOCK_MATMUL_OUTREG)
) matmul_ij (
    .clk            (clk), 
    .J              (J_local_ij),
    .x              (x_hat_j_packed),
    .is_diagonal    (stage_is_diagonal[STAGE_J_ARRIVE]),
    .out            (block_matmul_out_i_packed)
);
matmul #(
    .N                  (BLOCK_SIZE),
    .M                  (BLOCK_SIZE),
    .LEVEL1_GROUPS      (BLOCK_MATMUL_LEVEL1),
    .LEVEL2_GROUPS      (BLOCK_MATMUL_LEVEL2),
    .ENABLE_PRODREG     (BLOCK_MATMUL_PROGREG),
    .ENABLE_LEVEL1REG   (BLOCK_MATMUL_LEVEL1REG),
    .ENABLE_LEVEL2REG   (BLOCK_MATMUL_LEVEL2REG),
    .ENABLE_OUTREG      (BLOCK_MATMUL_OUTREG)
) matmul_ji (
    .clk            (clk), 
    .J              (J_local_ji),
    .x              (x_hat_i_packed),
    .is_diagonal    (stage_is_diagonal[STAGE_J_ARRIVE]),
    .out            (block_matmul_out_j_packed)
);

wire [0:BLOCK_SIZE*MUL_WIDTH-1] L_i_packed; // packed L_i 
wire [0:BLOCK_SIZE*MUL_WIDTH-1] L_j_packed; // packed L_j
L_mem #(
    .BLOCK_SIZE         (BLOCK_SIZE),
    .N_BLOCK_PER_ROW    (N_BLOCK_PER_ROW),
    .BLOCK_IDX_WIDTH    (BLOCK_IDX_WIDTH),
    .DELTA_WIDTH        (BLOCK_MUL_WIDTH),
    .DATA_WIDTH         (MUL_WIDTH)
) L_mem_i (
    .clk        (clk),
    .en         (running),
    .i          (stage_i[STAGE_MATMUL_OUT]),
    .j          (stage_j[STAGE_MATMUL_OUT]),
    .delta_i    (block_matmul_out_i_packed), // provided by matmul
    .delta_j    (block_matmul_out_j_packed), // provided by matmul
    .dout_i     (L_i_packed), // unused
    .dout_j     (L_j_packed)  // used as input for dynamics update
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
wire signed [X_NEXT_WIDTH-1:0] x_fix_j_next [0:BLOCK_SIZE-1];
wire signed [X_WIDTH-1:0] x_fix_j_new [0:BLOCK_SIZE-1];
wire signed [X_HAT_WIDTH-1:0] x_hat_j_new [0:BLOCK_SIZE-1];

wire signed [Y_WIDTH-1:0] y_fix_j [0:BLOCK_SIZE-1];
wire signed [Y_NEXT_WIDTH-1:0] y_fix_j_next [0:BLOCK_SIZE-1];
wire signed [Y_WIDTH-1:0] y_fix_j_new [0:BLOCK_SIZE-1];
wire signed [Y_HAT_WIDTH-1:0] y_hat_j [0:BLOCK_SIZE-1];

wire signed [G_WIDTH-1:0] g_fix_j [0:BLOCK_SIZE-1];
wire signed [G_HAT_WIDTH-1:0] g_hat_j [0:BLOCK_SIZE-1];

wire right_out_of_bounds [0:BLOCK_SIZE-1];
wire left_out_of_bounds [0:BLOCK_SIZE-1];

generate 
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : calculate_dynamics

        // Initialization of x_fix_j_init_sign
        if (RANDOM_INIT)
            rand #(
                .WIDTH  (1)
            ) r_x_init (
                .clk    (clk),
                .out    (x_fix_j_init_sign[gi])
            );
        else
            assign x_fix_j_init_sign[gi] = 1'b0; // Default to positive 


        // g_fix_j calculation
        assign g_fix_j[gi] = ($signed({1'b0, step}) - (1 << (G_DECIMAL - K_ETA))) * x_fix_j[gi] + 
                              $signed({L_j[gi], {(G_DECIMAL - K_XI){1'b0}}});

        // g_hat_j generation
        if (ENABLE_G_HAT)
            rand_near #(
                .WIDTH      (G_WIDTH),
                .OUT_WIDTH  (G_HAT_WIDTH),
                .RAND_WIDTH (G_DECIMAL)
            ) r_g_i (
                .clk        (clk),
                .in         (g_fix_j[gi]),
                .out        (g_hat_j[gi])
            );


        // y_fix_j fetch
        assign y_fix_j[gi] = y_fix_j_packed[gi*Y_WIDTH +: Y_WIDTH];
        if (ENABLE_G_HAT)   assign y_fix_j_next[gi] = y_fix_j[gi] + g_hat_j[gi];
        else                assign y_fix_j_next[gi] = y_fix_j[gi] + g_fix_j[gi];

        // y_hat_j generation
        if (ENABLE_Y_HAT)
            rand_near #(
                .WIDTH      (Y_WIDTH),
                .OUT_WIDTH  (Y_HAT_WIDTH),
                .RAND_WIDTH (Y_DECIMAL)
            ) r_y_i (
                .clk        (clk),
                .in         (y_fix_j_next[gi]),
                .out        (y_hat_j[gi])
            );


        // x_fix_j fetch 
        assign x_fix_j[gi] = x_fix_j_packed[gi*X_WIDTH +: X_WIDTH];
        if (ENABLE_Y_HAT)   assign x_fix_j_next[gi] = x_fix_j[gi] + y_hat_j[gi];
        else                assign x_fix_j_next[gi] = x_fix_j[gi] + y_fix_j_next[gi];

        assign right_out_of_bounds[gi] = x_fix_j_next[gi] > X_ABS_MAX;
        assign left_out_of_bounds[gi] = x_fix_j_next[gi] < -X_ABS_MAX;

        assign x_fix_j_new[gi] = 
            initializing ? (x_fix_j_init_sign[gi] ? -X_ABS_MAX : X_ABS_MAX) : 
            right_out_of_bounds[gi] ? X_ABS_MAX :
            left_out_of_bounds[gi] ? -X_ABS_MAX :
            x_fix_j_next[gi];
            
        assign y_fix_j_new[gi] = 
            initializing ? 0 :
            right_out_of_bounds[gi] || left_out_of_bounds[gi] ? 0 :
            y_fix_j_next[gi];


        // x_hat_i_new generation
        rand_near #(
            .WIDTH      (X_WIDTH),
            .OUT_WIDTH  (X_HAT_WIDTH),
            .RAND_WIDTH (X_DECIMAL)
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

localparam X_HAT_LATENCY = 0;
reg [$clog2(X_HAT_LATENCY):0] block_loading; // since ENABLE_OUTREG of x_hat_mem may be enabled

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

    idx_iterator_rst <= 0;
end

integer k;
always @(posedge clk) begin

    idx_iterator_rst <= 1'b0;
    
    // State machine
    case (state)
        STOPPED: begin
            if (request_start) begin
                state <= INIT;
                block_idx <= 0;
            end
        end

        INIT: begin
            if (stage_init_block_idx[STAGE_X_HAT_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
                state <= RUNNING;
            end else begin
                block_idx <= block_idx + 1;
                idx_iterator_rst <= 1'b1; 
            end
        end
        
        RUNNING: begin;

            // $display("(i, j) = (%2d, %2d)", stage_i[STAGE_X_HAT_ARRIVE], stage_j[STAGE_X_HAT_ARRIVE]);

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
            // if (stage_j[STAGE_X_HAT_ARRIVE] == 0) begin
            //     if (stage_i[STAGE_X_HAT_ARRIVE] == 0) begin
            //         $write("x_hat = [");
            //     end
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //         $write("%2d,", $signed(x_hat_i_packed[k*X_HAT_WIDTH +: X_HAT_WIDTH]));
            //     if (stage_i[STAGE_X_HAT_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
            //         $write("]");
            //     end
            //     $write("\n");
            // end

            // // Display L
            // if (stage_i[STAGE_L_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
            //     if (stage_j[STAGE_L_ARRIVE] == 0) begin
            //         $write("L = [");
            //     end
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //         $write("%3d,", $signed(L_j[k]));
            //     if (stage_j[STAGE_L_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
            //         $write("]");
            //     end
            //     $write("\n");
            // end 


            if (stage_request_stop[STAGE_X_HAT_NEW_ARRIVE]) begin
                state <= WRITE;
                            
                read_begin <= 0;
                write_begin <= 0;
                read_offset <= 0;

                block_idx <= 0;
                block_loading <= X_HAT_LATENCY;
                out_idx <= 0;

                BRAM_addr <= 0;
                BRAM_din <= 0;
                BRAM_en <= 0;
                BRAM_we <= 0;
            end

        end
        
        WRITE: begin  
        
            if (block_loading > 0) 
                block_loading <= block_loading - 1;
            else begin

                // Fetch the sign of x and pack to BRAM_din
                for (k = 0; k < OUT_BRAM_WIDTH; k = k + 1) begin
                    if (write_begin + k < read_begin)
                        BRAM_din[k] <= BRAM_din[k]; // Keep the previous value
                    else if (write_begin + k < read_end)
                        BRAM_din[k] <= x_hat_k_packed[(read_offset + k) * X_HAT_WIDTH];
                    else
                        BRAM_din[k] <= 0; // Fill the rest with zeros
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
        end
    endcase

end


endmodule
