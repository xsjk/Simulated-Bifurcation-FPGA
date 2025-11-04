`timescale 1ns / 1ps

module block_sSB  #(
    parameter N = 2000,
    parameter BLOCK_SIZE = 80,
    parameter STEPS = 50000,
        
    parameter K_N = $clog2(N+1),                // Width for N
    parameter K_BLOCK = $clog2(BLOCK_SIZE+1),   // Width for block size
    parameter K_BETA = 8,                      // beta = 2^(-K_BETA)
    parameter K_XI = 6,                         // xi = 2^(-K_XI)
    parameter K_ETA = 0,                        // eta = 2^(-K_ETA)
    parameter K_X = 1,                          // |x| < 2^(K_X)
    parameter K_Y = 3,                          // |y| < 2^(K_Y)
    parameter K_G = 3,                          // |g| < 2^(K_G)
    parameter K_ALPHA = 2,                      // |sum(J_ij * x_i)| < 2^(-K_ALPHA) * N

    // Quantization mode
    parameter COUPLE_MODE = 2,      // the mode to calculate J @ x
    parameter UPDATE_MODE_Y = 0,    // the mode to update y += eta * g
    parameter UPDATE_MODE_X = 1,    // the mode to update x += eta * y
    
    parameter BLOCK_MATMUL_LEVEL1 = 12,
    parameter BLOCK_MATMUL_LEVEL2 = 4,

    parameter OUT_BRAM_WIDTH = 32,  // Width of output BRAM
    parameter OUT_BRAM_DEPTH = 10,   // Depth of output BRAM

    parameter RANDOM_INIT = 1, // Random initialization of x_fix
    
    parameter RANDOM_METHOD = 0 // 0 for ro, 1 for lfsr

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

if (2*K_ETA + K_BETA < K_XI)
    $error("2*K_ETA + K_BETA (%d) must be greater than or equal to K_XI (%d)", 2*K_ETA + K_BETA, K_XI);

if (OUT_BRAM_DEPTH < WRITE_INDEX_WIDTH)
    $error("OUT_BRAM_DEPTH (%d) must be greater than or equal to WRITE_INDEX_WIDTH (%d)", OUT_BRAM_DEPTH, WRITE_INDEX_WIDTH);

if (K_X != 1)
    $error("K_X (%d) must be equal to 1 since x is always in the range [-1, 1]", K_X);

if (OUT_BRAM_DEPTH < $clog2((N-1)/OUT_BRAM_WIDTH+1))
    $error("OUT_BRAM_DEPTH (%d) is not sufficient for N (%d) bits.", OUT_BRAM_DEPTH, N);

if (BLOCK_SIZE < OUT_BRAM_WIDTH)
    $error("BLOCK_SIZE (%d) must be greater than or equal to OUT_BRAM_WIDTH (%d)", BLOCK_SIZE, OUT_BRAM_WIDTH);

if (!(0 <= UPDATE_MODE_X <= 2))
    $error("UPDATE_MODE_X (%d) must be DEFAULT/SIGN/RANDOM (0/1/2)", UPDATE_MODE_X);

if (!(0 <= UPDATE_MODE_Y <= 2))
    $error("UPDATE_MODE_Y (%d) must be DEFAULT/SIGN/RANDOM (0/1/2)", UPDATE_MODE_Y);

if (!(1 <= COUPLE_MODE <= 2))
    $error("COUPLE_MODE (%d) must be in SIGN/RANDOM (1/2)", COUPLE_MODE);


// State definitions 
localparam STOPPED = 0;
localparam INIT = 1;
localparam RUNNING = 2;
localparam WRITE = 3;


// Quantization schemes enums
localparam DEFAULT = 0; // no quantization, e.g. y += eta * g
localparam SIGN = 1; // use signed quantization, e.g. y += eta * sign(g)
localparam RANDOM = 2; // use random quantization, e.g. y += eta * g_hat

localparam ENABLE_G_HAT = UPDATE_MODE_Y == RANDOM;
localparam ENABLE_Y_HAT = UPDATE_MODE_X == RANDOM;
localparam ENABLE_X_HAT = COUPLE_MODE == RANDOM; // sSB

localparam ENABLE_G_SGN = UPDATE_MODE_Y == SIGN;
localparam ENABLE_Y_SGN = UPDATE_MODE_X == SIGN;
localparam ENABLE_X_SGN = COUPLE_MODE == SIGN; // dSB


// Derived parameters
localparam N_BLOCK_PER_ROW = N / BLOCK_SIZE; // Number of blocks per row

localparam BLOCK_MUL_WIDTH = 1 + K_BLOCK; // Width for sum(J_ij * x_i) on block level
localparam MUL_WIDTH = 1 + K_N - K_ALPHA; // Width for sum(J_ij * x_i)

localparam G_DECIMAL = 2*K_ETA + K_BETA;
localparam Y_DECIMAL = UPDATE_MODE_Y == DEFAULT ? G_DECIMAL + K_ETA : K_ETA;
localparam X_DECIMAL = UPDATE_MODE_X == DEFAULT ? Y_DECIMAL + K_ETA : K_ETA;
localparam X_WIDTH = 1 + K_X + X_DECIMAL;   // Width for x
localparam Y_WIDTH = 1 + K_Y + Y_DECIMAL;   // Width for y
localparam G_WIDTH = 1 + K_G + G_DECIMAL;   // Width for g
localparam X_HAT_WIDTH = 1 + K_X;           // Width for x_hat
localparam Y_HAT_WIDTH = 1 + K_Y;           // Width for y_hat
localparam G_HAT_WIDTH = 1 + K_G;           // Width for g_hat
localparam X_ABS_MAX = 1 << X_DECIMAL; // Maximum absolute value for x
localparam Y_DELTA_WIDTH = UPDATE_MODE_Y == DEFAULT ? G_WIDTH :
                           UPDATE_MODE_Y == RANDOM  ? G_HAT_WIDTH : 
                           UPDATE_MODE_Y == SIGN ? 2 : 0;
localparam Y_NEXT_WIDTH = 1 + ((Y_WIDTH > Y_DELTA_WIDTH) ? Y_WIDTH : Y_DELTA_WIDTH);
localparam X_DELTA_WIDTH = UPDATE_MODE_X == DEFAULT ? Y_NEXT_WIDTH :
                           UPDATE_MODE_X == RANDOM  ? Y_HAT_WIDTH : 
                           UPDATE_MODE_X == SIGN ? 2 : 0;
localparam X_NEXT_WIDTH = 1 + ((X_WIDTH > X_DELTA_WIDTH) ? X_WIDTH : X_DELTA_WIDTH);

localparam BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW);    // Width for block indices
localparam BLOCK_DATA_WIDTH = BLOCK_SIZE * BLOCK_SIZE;   // Width for flattened block data
localparam LOCAL_IDX_WIDTH = $clog2(BLOCK_SIZE);         // Width for inner block index
localparam STEP_WIDTH = $clog2(STEPS);                   // Width for step

localparam WRITE_INDEX_MAX = (N-1)/OUT_BRAM_WIDTH;          // Maximum number of write indices
localparam WRITE_INDEX_WIDTH = $clog2(WRITE_INDEX_MAX+1);   // Width for write index

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
localparam MAX_STAGE = N_BLOCK_PER_ROW;
wire [BLOCK_IDX_WIDTH-1:0] i;
wire [BLOCK_IDX_WIDTH-1:0] j;
wire [STEP_WIDTH-1:0] step;
wire [BLOCK_FLAT_IDX_WIDTH-1:0] flat_idx;
wire request_stop;

reg [BLOCK_IDX_WIDTH-1:0] stage_i [0:MAX_STAGE];
reg [BLOCK_IDX_WIDTH-1:0] stage_j [0:MAX_STAGE];
reg [STEP_WIDTH-1:0] stage_step [0:MAX_STAGE];
reg [BLOCK_FLAT_IDX_WIDTH-1:0] stage_flat_idx [0:MAX_STAGE];
reg stage_is_diagonal [0:MAX_STAGE];
reg stage_request_stop [0:MAX_STAGE];
always @(*) begin
    stage_i[0] = i;
    stage_j[0] = j;
    stage_step[0] = step;
    stage_flat_idx[0] = flat_idx;
    stage_request_stop[0] = request_stop;
    stage_is_diagonal[0] = (i == j);
end


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
            stage_step[gs+1] <= stage_step[gs];
            stage_flat_idx[gs+1] <= stage_flat_idx[gs];
            stage_request_stop[gs+1] <= stage_request_stop[gs];
            stage_is_diagonal[gs+1] <= stage_is_diagonal[gs];
        end
    end
endgenerate

// Reg enables for block matrix multiplication 
localparam BLOCK_MATMUL_PROGREG     = 1;
localparam BLOCK_MATMUL_LEVEL1REG   = 1;
localparam BLOCK_MATMUL_LEVEL2REG   = 1;
localparam BLOCK_MATMUL_OUTREG      = 1;

// Reg enables for various signals
localparam J_ADDR_REG               = 1;
localparam J_REG                    = 1;
localparam X_HAT_REG                = 1;
localparam X_HAT_K_REG              = 1;
localparam X_HAT_K_ADDR_REG         = 1;
localparam L_REG                    = 1;
localparam L_STORE_REG              = 1;
localparam X_REG                    = 1;
localparam Y_REG                    = 1;
localparam G_LHS_REG                = 1;
localparam G_REG                    = 1;
localparam G_HAT_REG                = 1;
localparam Y_DELTA_REG              = 1;
localparam Y_NEXT_REG               = 1;
localparam Y_WRITE_ADDR_REG         = 1;
localparam Y_HAT_REG                = 1;
localparam X_DELTA_REG              = 1;
localparam X_NEXT_REG               = 1;
localparam X_WRITE_ADDR_REG         = 1;
localparam OOB_REG                  = 1;
localparam Y_NEW_REG                = 1;
localparam X_NEW_REG                = 1;
localparam X_HAT_NEW_REG            = 1;

// Input stages
localparam STAGE_J_LOAD = 1; 
localparam STAGE_X_HAT_LOAD = STAGE_J_LOAD + J_ADDR_REG + 1 + J_REG - X_HAT_REG; 
localparam STAGE_L_LOAD = STAGE_X_HAT_LOAD + X_HAT_REG + BLOCK_MATMUL_PROGREG + BLOCK_MATMUL_LEVEL1REG + BLOCK_MATMUL_LEVEL2REG + BLOCK_MATMUL_OUTREG;
localparam STAGE_X_LOAD = STAGE_L_LOAD + L_STORE_REG + L_REG - G_LHS_REG - X_REG;
localparam STAGE_Y_LOAD = STAGE_X_LOAD + X_REG + G_LHS_REG + G_REG + ENABLE_G_HAT * G_HAT_REG + Y_DELTA_REG - Y_REG;
initial begin 
    $write("STAGE_J_LOAD: %d\n", STAGE_J_LOAD);
    $write("STAGE_X_HAT_LOAD: %d\n", STAGE_X_HAT_LOAD);
    $write("STAGE_L_LOAD: %d\n", STAGE_L_LOAD);
    $write("STAGE_X_LOAD: %d\n", STAGE_X_LOAD);
    $write("STAGE_Y_LOAD: %d\n", STAGE_Y_LOAD);
end

localparam STAGE_X_ARRIVE = STAGE_X_LOAD + X_REG;
localparam STAGE_Y_ARRIVE = STAGE_Y_LOAD + Y_REG;
localparam STAGE_X_HAT_ARRIVE = STAGE_X_HAT_LOAD + X_HAT_REG;
localparam STAGE_J_ARRIVE = STAGE_J_LOAD + J_ADDR_REG + 1 + J_REG; // +1 for BRAM latency
localparam STAGE_L_ARRIVE = STAGE_L_LOAD + L_STORE_REG + L_REG;

// Block Matrix multiplication
if (STAGE_J_ARRIVE != STAGE_X_HAT_ARRIVE) begin
    $error("Error: Input stages of J * x_hat doesnot match");
end

localparam STAGE_MATMUL_OUT = STAGE_J_ARRIVE + BLOCK_MATMUL_PROGREG + BLOCK_MATMUL_LEVEL1REG + BLOCK_MATMUL_LEVEL2REG + BLOCK_MATMUL_OUTREG;

if (STAGE_MATMUL_OUT != STAGE_L_LOAD) begin
    $error("Error: Output stages of J * x_hat doesnot match input stage of L_mem");
end

localparam STAGE_G_LHS_ARRIVE = STAGE_X_ARRIVE + G_LHS_REG;
if (STAGE_L_ARRIVE != STAGE_G_LHS_ARRIVE) begin
    $error("Error: Input stages of g = g_lhs + xi L doesnot match");
end

localparam STAGE_G_ARRIVE = STAGE_L_ARRIVE + G_REG;
localparam STAGE_G_HAT_ARRIVE = STAGE_G_ARRIVE + G_HAT_REG;
localparam STAGE_Y_DELTA_ARRIVE = (ENABLE_G_HAT ? STAGE_G_HAT_ARRIVE : STAGE_G_ARRIVE) + Y_DELTA_REG;

if (STAGE_Y_DELTA_ARRIVE != STAGE_Y_ARRIVE) begin
    $error("Error: Input stages of y += delta y doesnot match");
end

localparam STAGE_Y_NEXT_ARRIVE = STAGE_Y_DELTA_ARRIVE + Y_NEXT_REG; 
localparam STAGE_Y_HAT_ARRIVE = STAGE_Y_NEXT_ARRIVE + Y_HAT_REG;
localparam STAGE_X_DELTA_ARRIVE = (ENABLE_Y_HAT ? STAGE_Y_HAT_ARRIVE : STAGE_Y_NEXT_ARRIVE) + X_DELTA_REG;

localparam STAGE_X_NEXT_ARRIVE = STAGE_X_DELTA_ARRIVE + X_NEXT_REG;
localparam STAGE_OOB_ARRIVE = STAGE_X_NEXT_ARRIVE + OOB_REG;
localparam STAGE_X_NEW_ARRIVE = STAGE_OOB_ARRIVE + X_NEW_REG;
localparam STAGE_X_WRITE = STAGE_X_NEW_ARRIVE - X_WRITE_ADDR_REG;
localparam STAGE_Y_NEW_ARRIVE = STAGE_OOB_ARRIVE + Y_NEW_REG;
localparam STAGE_Y_WRITE = STAGE_Y_NEW_ARRIVE - Y_WRITE_ADDR_REG;
localparam STAGE_X_HAT_NEW_ARRIVE = STAGE_X_NEW_ARRIVE + X_HAT_NEW_REG;
localparam STAGE_X_HAT_WRITE = STAGE_X_HAT_NEW_ARRIVE - X_HAT_K_ADDR_REG;


// Stage indices for the block index iterator
// store multi stages of block_idx to handle different storing stage of x_fix, y_fix, x_hat during initialization phase
reg [BLOCK_IDX_WIDTH-1:0] stage_init_block_idx [STAGE_X_NEXT_ARRIVE:STAGE_X_HAT_NEW_ARRIVE]; 
always @(*) stage_init_block_idx[STAGE_X_NEXT_ARRIVE] = block_idx;
generate
    for (gs = STAGE_X_NEXT_ARRIVE; gs < STAGE_X_HAT_NEW_ARRIVE; gs = gs + 1) begin : gen_stage_block_idx
        always @(posedge clk) stage_init_block_idx[gs+1] <= stage_init_block_idx[gs];
    end
endgenerate



// Memory for x_fix
wire [0:BLOCK_SIZE*X_WIDTH-1] x_fix_j_packed;
wire [0:BLOCK_SIZE*X_WIDTH-1] x_fix_j_packed_new;
wire x_fix_j_we = 
    initializing ? 1'b1 : // always write during initialization phase
    running ? stage_i[STAGE_X_WRITE] == N_BLOCK_PER_ROW - 1 : // write only at the last block of the column during running phase
    1'b0; // disable otherwise

wire [BLOCK_IDX_WIDTH-1:0] x_fix_j_write_addr = 
    initializing ? stage_init_block_idx[STAGE_X_WRITE] :
    stage_j[STAGE_X_WRITE];

reg x_fix_j_we_reg;
if (X_WRITE_ADDR_REG) always @(posedge clk) x_fix_j_we_reg <= x_fix_j_we;
else                  always @(*) x_fix_j_we_reg = x_fix_j_we;

reg [BLOCK_IDX_WIDTH-1:0] x_fix_j_write_addr_reg;
if (X_WRITE_ADDR_REG) always @(posedge clk) x_fix_j_write_addr_reg <= x_fix_j_write_addr;
else                  always @(*) x_fix_j_write_addr_reg = x_fix_j_write_addr;

if (STAGE_X_WRITE == STAGE_X_LOAD)
    lutram_gen #(
        .WIDTH          (BLOCK_SIZE * X_WIDTH),
        .DEPTH          (N_BLOCK_PER_ROW),
        .ADDR_WIDTH     (BLOCK_IDX_WIDTH)
    ) x_fix_mem (
        .clk    (clk),
        .addr   (x_fix_j_write_addr_reg),
        .we     (x_fix_j_we_reg),
        .din    (x_fix_j_packed_new),
        .dout   (x_fix_j_packed)
    );
else
    dual_lutram_gen #(
        .WIDTH              (BLOCK_SIZE * X_WIDTH),
        .DEPTH              (N_BLOCK_PER_ROW),
        .ADDR_WIDTH         (BLOCK_IDX_WIDTH),
        .ENABLE_OUTREG_B    (X_REG)
    ) x_fix_mem (
        .clk    (clk),
        .addra  (x_fix_j_write_addr_reg), // read at running phase, undefined during writing phase
        .wea    (x_fix_j_we_reg),
        .dina   (x_fix_j_packed_new),
        .douta  (/* unused */),
        .addrb  (stage_j[STAGE_X_LOAD]),
        .doutb  (x_fix_j_packed)
    );


// Memory for y_fix
wire [0:BLOCK_SIZE*Y_WIDTH-1] y_fix_j_packed;
wire [0:BLOCK_SIZE*Y_WIDTH-1] y_fix_j_packed_new;

wire y_fix_j_we = 
    initializing ? 1'b1 : // always write during initialization phase
    running ? stage_i[STAGE_Y_WRITE] == N_BLOCK_PER_ROW - 1 : // write only at the last block of the column during running phase
    1'b0; // disable otherwise

wire [BLOCK_IDX_WIDTH-1:0] y_fix_j_write_addr = 
    initializing ? stage_init_block_idx[STAGE_Y_WRITE] :
    stage_j[STAGE_Y_WRITE];

reg y_fix_j_we_reg;
if (Y_WRITE_ADDR_REG) always @(posedge clk) y_fix_j_we_reg <= y_fix_j_we;
else                  always @(*) y_fix_j_we_reg = y_fix_j_we;

reg [BLOCK_IDX_WIDTH-1:0] y_fix_j_write_addr_reg;
if (Y_WRITE_ADDR_REG) always @(posedge clk) y_fix_j_write_addr_reg <= y_fix_j_write_addr;
else                  always @(*) y_fix_j_write_addr_reg = y_fix_j_write_addr;


if (STAGE_Y_WRITE == STAGE_Y_LOAD)
    lutram_gen #(
        .WIDTH          (BLOCK_SIZE * Y_WIDTH),
        .DEPTH          (N_BLOCK_PER_ROW),
        .ADDR_WIDTH     (BLOCK_IDX_WIDTH),
        .ENABLE_OUTREG  (Y_REG)
    ) y_fix_mem (
        .clk    (clk),
        .addr   (y_fix_j_write_addr_reg),
        .we     (y_fix_j_we_reg),
        .din    (y_fix_j_packed_new),
        .dout   (y_fix_j_packed)
    );
else 
    dual_lutram_gen #(
        .WIDTH              (BLOCK_SIZE * Y_WIDTH),
        .DEPTH              (N_BLOCK_PER_ROW),
        .ADDR_WIDTH         (BLOCK_IDX_WIDTH),
        .ENABLE_OUTREG_B    (Y_REG)
    ) y_fix_mem (
        .clk    (clk),
        .addra  (y_fix_j_write_addr_reg),
        .wea    (y_fix_j_we_reg),
        .dina   (y_fix_j_packed_new),
        .douta  (/* unused */),
        .addrb  (stage_j[STAGE_Y_LOAD]),
        .doutb  (y_fix_j_packed)
    );


// Memory for x_hat
wire [BLOCK_IDX_WIDTH-1:0] x_hat_k_addr = 
    initializing ? stage_init_block_idx[STAGE_X_HAT_WRITE] :
    running ? stage_j[STAGE_X_HAT_WRITE] :
    block_idx; // during writing phase, read based on block_idx
reg [BLOCK_IDX_WIDTH-1:0] x_hat_k_addr_reg;
if (X_HAT_K_ADDR_REG) always @(posedge clk) x_hat_k_addr_reg <= x_hat_k_addr;
else                  always @(*) x_hat_k_addr_reg = x_hat_k_addr;

wire x_hat_k_we = 
    initializing ? 1'b1 : // always write during initialization phase
    running ? stage_i[STAGE_X_HAT_WRITE] == N_BLOCK_PER_ROW - 1 : // write only at the last block of the column
    writing ? 1'b0 : // always read during writing phase
    1'b0;
reg x_hat_k_we_reg;
if (X_HAT_K_ADDR_REG) always @(posedge clk) x_hat_k_we_reg <= x_hat_k_we;
else                  always @(*) x_hat_k_we_reg = x_hat_k_we;

wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_i_packed; // packed x_hat_i
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed; // packed x_hat_j
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_k_packed; // packed x_hat_k
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed_new; // packed x_hat_j_new
x_hat_mem #(
    .BLOCK_SIZE         (BLOCK_SIZE),
    .N_BLOCK_PER_ROW    (N_BLOCK_PER_ROW),
    .BLOCK_IDX_WIDTH    (BLOCK_IDX_WIDTH),
    .DATA_WIDTH         (X_HAT_WIDTH),
    .ENABLE_OUTREG_I    (X_HAT_REG),
    .ENABLE_OUTREG_J    (X_HAT_REG),
    .ENABLE_OUTREG_K    (X_HAT_K_REG)
) x_hat_mem_i (
    .clk    (clk),
    .i      (stage_i[STAGE_X_HAT_LOAD]),
    .j      (stage_j[STAGE_X_HAT_LOAD]),
    .dout_i (x_hat_i_packed), // used as input for matrix multiplication
    .dout_j (x_hat_j_packed), // used as input for matrix multiplication
    .k      (x_hat_k_addr_reg), // during writing phase, read based on block_idx
    .we_k   (x_hat_k_we_reg),
    .din_k  (x_hat_j_packed_new), // provided by dynamics update
    .dout_k (x_hat_k_packed) // used as input during writing phase
);

// Memory for Coefficient Matrix
wire [0:BLOCK_DATA_WIDTH-1] J_local_ij;
wire [0:BLOCK_DATA_WIDTH-1] J_local_ji;
wire [BLOCK_FLAT_IDX_WIDTH-1:0] J_addr = stage_flat_idx[STAGE_J_LOAD];
reg [BLOCK_FLAT_IDX_WIDTH-1:0] J_addr_reg;
if (J_ADDR_REG) always @(posedge clk) J_addr_reg <= J_addr;
else            always @(*) J_addr_reg = J_addr;
J_mem #(
    .N              (N),
    .BLOCK_SIZE     (BLOCK_SIZE),
    .ENABLE_OUTREG  (J_REG)
) J_mem_i (
    .clk            (clk),
    .idx            (J_addr_reg),
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
    .DATA_WIDTH         (MUL_WIDTH),
    .ENABLE_STOREREG    (L_STORE_REG),
    .ENABLE_OUTREG      (L_REG)
) L_mem_i (
    .clk        (clk),
    .en         (running),
    .i          (stage_i[STAGE_L_LOAD]),
    .j          (stage_j[STAGE_L_LOAD]),
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

        // x_fix_j fetch 
        assign x_fix_j[gi] = x_fix_j_packed[gi*X_WIDTH +: X_WIDTH];
        // Extend x_fix to match the stage of y_hat, since x_fix_next <= x_fix + y_hat
        reg signed [X_WIDTH-1:0] stage_x_fix [STAGE_X_ARRIVE:STAGE_X_DELTA_ARRIVE];
        always @(*) stage_x_fix[STAGE_X_ARRIVE] = x_fix_j[gi];
        for (gs = STAGE_X_ARRIVE; gs < STAGE_X_DELTA_ARRIVE; gs = gs + 1)
            always @(posedge clk) stage_x_fix[gs+1] <= stage_x_fix[gs];

        // g_fix_j calculation
        wire signed [G_WIDTH-1:0] g_lhs = ($signed({1'b0, stage_step[STAGE_X_ARRIVE]}) - (1 << (G_DECIMAL - K_ETA))) * 
                                          stage_x_fix[STAGE_X_ARRIVE];
        reg signed [G_WIDTH-1:0] g_lhs_reg;
        if (G_LHS_REG) always @(posedge clk) g_lhs_reg <= g_lhs;
        else           always @(*)           g_lhs_reg = g_lhs;
        assign g_fix_j[gi] = g_lhs_reg + $signed({L_j[gi], {(G_DECIMAL - K_XI){1'b0}}});

        reg signed [G_WIDTH-1:0] g_fix;
        if (G_REG) always @(posedge clk) g_fix <= g_fix_j[gi];
        else       always @(*)           g_fix = g_fix_j[gi];

        // g_hat_j generation
        if (ENABLE_G_HAT)
            rand_near #(
                .WIDTH      (G_WIDTH),
                .OUT_WIDTH  (G_HAT_WIDTH),
                .RAND_WIDTH (G_DECIMAL),
                .METHOD     (RANDOM_METHOD),
                .SEED       (gi+1)
            ) r_g_i (
                .clk        (clk),
                .in         (g_fix),
                .out        (g_hat_j[gi])
            );
        reg signed [G_HAT_WIDTH-1:0] g_hat;
        if (G_HAT_REG) always @(posedge clk) g_hat <= g_hat_j[gi];
        else           always @(*)           g_hat = g_hat_j[gi];


        // g_sgn calculation
        wire signed [1:0] g_sgn = g_fix > 0 ? 1 : g_fix < 0 ? -1 : 0; // TODO verify 

        // y_delta
        wire signed [Y_DELTA_WIDTH-1:0] y_delta = ENABLE_G_HAT ? g_hat : 
                                                  ENABLE_G_SGN ? g_sgn : g_fix;
        reg signed [Y_DELTA_WIDTH-1:0] y_delta_reg;
        if (Y_DELTA_REG) always @(posedge clk) y_delta_reg <= y_delta;
        else             always @(*)           y_delta_reg = y_delta;

        // y_fix_j fetch
        assign y_fix_j[gi] = y_fix_j_packed[gi*Y_WIDTH +: Y_WIDTH];
        assign y_fix_j_next[gi] = y_fix_j[gi] + y_delta_reg;
        reg signed [Y_NEXT_WIDTH-1:0] y_fix_next;
        if (Y_NEXT_REG) always @(posedge clk) y_fix_next <= y_fix_j_next[gi];
        else            always @(*)           y_fix_next = y_fix_j_next[gi];

        // Extend y_fix_next to match the stage of out-of-bounds checking
        reg signed [Y_NEXT_WIDTH-1:0] stage_y_fix_next [STAGE_Y_NEXT_ARRIVE:STAGE_OOB_ARRIVE];
        always @(*) stage_y_fix_next[STAGE_Y_NEXT_ARRIVE] = y_fix_next;
        for (gs = STAGE_Y_NEXT_ARRIVE; gs < STAGE_OOB_ARRIVE; gs = gs + 1)
            always @(posedge clk) stage_y_fix_next[gs+1] <= stage_y_fix_next[gs];

        // y_hat_j generation
        if (ENABLE_Y_HAT)
            rand_near #(
                .WIDTH      (Y_WIDTH),
                .OUT_WIDTH  (Y_HAT_WIDTH),
                .RAND_WIDTH (Y_DECIMAL),
                .METHOD     (RANDOM_METHOD),
                .SEED       (gi+1)
            ) r_y_i (
                .clk        (clk),
                .in         (y_fix_next),
                .out        (y_hat_j[gi])
            );
        reg signed [Y_HAT_WIDTH-1:0] y_hat;
        if (Y_HAT_REG) always @(posedge clk) y_hat <= y_hat_j[gi];
        else           always @(*)           y_hat = y_hat_j[gi];
        
        // y_fix_next_sgn calculation
        wire signed [1:0] y_fix_next_sgn = y_fix_next > 0 ? 1 : y_fix_next < 0 ? -1 : 0; // TODO verify

        // x_delta
        wire signed [X_DELTA_WIDTH-1:0] x_delta = ENABLE_Y_HAT ? y_hat : 
                                                  ENABLE_Y_SGN ? y_fix_next_sgn : y_fix_next;
        reg signed [X_DELTA_WIDTH-1:0] x_delta_reg;
        if (X_DELTA_REG) always @(posedge clk) x_delta_reg <= x_delta;
        else             always @(*)           x_delta_reg = x_delta;
        assign x_fix_j_next[gi] = stage_x_fix[STAGE_X_DELTA_ARRIVE] + x_delta_reg;
        
        reg signed [X_NEXT_WIDTH-1:0] x_fix_next;
        if (X_NEXT_REG) always @(posedge clk) x_fix_next <= x_fix_j_next[gi];
        else            always @(*)           x_fix_next = x_fix_j_next[gi];

        // Extend x_fix_next to match the stage of out-of-bounds checking
        reg signed [X_NEXT_WIDTH-1:0] stage_x_fix_next [STAGE_X_NEXT_ARRIVE:STAGE_OOB_ARRIVE];
        always @(*) stage_x_fix_next[STAGE_X_NEXT_ARRIVE] = x_fix_next;
        for (gs = STAGE_X_NEXT_ARRIVE; gs < STAGE_OOB_ARRIVE; gs = gs + 1)
            always @(posedge clk) stage_x_fix_next[gs+1] <= stage_x_fix_next[gs];


        assign right_out_of_bounds[gi] = x_fix_next > X_ABS_MAX;
        assign left_out_of_bounds[gi] = x_fix_next < -X_ABS_MAX;
        reg roob;
        reg loob;
        if (OOB_REG)
            always @(posedge clk) begin
                roob <= right_out_of_bounds[gi];
                loob <= left_out_of_bounds[gi];
            end
        else
            always @(*) begin
                roob = right_out_of_bounds[gi];
                loob = left_out_of_bounds[gi];
            end

        assign x_fix_j_new[gi] = 
            initializing ? (x_fix_j_init_sign[gi] ? -X_ABS_MAX : X_ABS_MAX) : 
            roob ? X_ABS_MAX :
            loob ? -X_ABS_MAX :
            stage_x_fix_next[STAGE_OOB_ARRIVE];
        reg signed [X_WIDTH-1:0] x_fix_new;
        if (X_NEW_REG) always @(posedge clk) x_fix_new <= x_fix_j_new[gi];
        else           always @(*)           x_fix_new = x_fix_j_new[gi];


        assign y_fix_j_new[gi] = 
            initializing ? 0 :
            roob || loob ? 0 :
            stage_y_fix_next[STAGE_OOB_ARRIVE];
        reg signed [Y_WIDTH-1:0] y_fix_new;
        if (Y_NEW_REG) always @(posedge clk) y_fix_new <= y_fix_j_new[gi];
        else           always @(*)           y_fix_new = y_fix_j_new[gi];


        // x_hat_i_new generation
        if (ENABLE_X_HAT)
            rand_near #(
                .WIDTH      (X_WIDTH),
                .OUT_WIDTH  (X_HAT_WIDTH),
                .RAND_WIDTH (X_DECIMAL),
                .METHOD     (RANDOM_METHOD),
                .SEED       (gi+1)
            ) r_x_i (
                .clk        (clk),
                .in         (x_fix_new),
                .out        (x_hat_j_new[gi])
            );
        else if (ENABLE_X_SGN)
            assign x_hat_j_new[gi] = x_fix_new > 0 ? 1 : 
                                     x_fix_new < 0 ? -1 : 0;
        else
            $error("Error: Either ENABLE_X_HAT or ENABLE_X_SGN must be enabled for x_hat generation");

        reg signed [X_HAT_WIDTH-1:0] x_hat_new;
        if (X_HAT_NEW_REG) always @(posedge clk) x_hat_new <= x_hat_j_new[gi];
        else               always @(*)           x_hat_new = x_hat_j_new[gi];

        // assign packed wires
        assign y_fix_j_packed_new[gi*Y_WIDTH +: Y_WIDTH] = y_fix_new;
        assign x_fix_j_packed_new[gi*X_WIDTH +: X_WIDTH] = x_fix_new;
        assign x_hat_j_packed_new[gi*X_HAT_WIDTH +: X_HAT_WIDTH] = x_hat_new;
    end
endgenerate



// Sequential logic of the state machine

reg [K_N-1:0] read_begin;
reg [K_N-1:0] write_begin;
wire [K_N:0] read_end = read_begin + BLOCK_SIZE;
wire [K_N:0] write_end = write_begin + OUT_BRAM_WIDTH;
reg signed [LOCAL_IDX_WIDTH:0] read_offset;

reg [1:0] block_loading; // since ENABLE_OUTREG_K of x_hat_mem may be enabled

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
            //     if (stage_i[STAGE_X_HAT_ARRIVE] == 0)
            //         $write("x_hat = [");
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //         $write("%2d,", $signed(x_hat_i_packed[k*X_HAT_WIDTH +: X_HAT_WIDTH]));
            //     if (stage_i[STAGE_X_HAT_ARRIVE] == N_BLOCK_PER_ROW - 1)
            //         $write("]");
            //     $write("\n");
            // end

            // // Display L
            // if (stage_i[STAGE_L_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
            //     if (stage_j[STAGE_L_ARRIVE] == 0)
            //         $write("L = [");
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1)
            //         $write("%3d,", $signed(L_j[k]));
            //     if (stage_j[STAGE_L_ARRIVE] == N_BLOCK_PER_ROW - 1)
            //         $write("]");
            //     $write("\n");
            // end 


            // // Display x_hat_new
            // if (stage_i[STAGE_X_HAT_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
            //     if (stage_j[STAGE_X_HAT_ARRIVE] == 0)
            //         $write("x_hat_new = [");
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1) 
            //         $write("%1d", x_hat_j_packed_new[k*X_HAT_WIDTH]);
            //     $write("\n");
            //     if (stage_j[STAGE_X_HAT_ARRIVE] == N_BLOCK_PER_ROW - 1)
            //         $write("]\n");
            // end

            // // Display x_fix_new
            // if (stage_i[STAGE_X_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
            //     if (stage_j[STAGE_X_NEW_ARRIVE] == 0)
            //         $write("x_fix_new = [");
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1) 
            //         $write("%3d,", $signed(x_fix_j_packed_new[k*X_WIDTH +: X_WIDTH]));
            //     if (stage_j[STAGE_X_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1)
            //         $write("]");
            //     $write("\n");
            // end

            // // Display y_fix_new
            // if (stage_i[STAGE_Y_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
            //     if (stage_j[STAGE_Y_NEW_ARRIVE] == 0)
            //         $write("y_fix_new = [");
            //     for (k = 0; k < BLOCK_SIZE; k = k + 1) 
            //         $write("%3d,", $signed(y_fix_j_packed_new[k*Y_WIDTH +: Y_WIDTH]));
            //     if (stage_j[STAGE_Y_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1)
            //         $write("]");
            //     $write("\n");
            // end

            if (stage_request_stop[STAGE_X_HAT_NEW_ARRIVE]) begin
                state <= WRITE;
                            
                read_begin <= 0;
                write_begin <= 0;
                read_offset <= 0;

                block_idx <= 0;
                block_loading <= X_HAT_K_REG + X_HAT_K_ADDR_REG; // delay one clock if X_HAT_K_REG enabled
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
                    block_loading <= X_HAT_K_REG + X_HAT_K_ADDR_REG;
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
