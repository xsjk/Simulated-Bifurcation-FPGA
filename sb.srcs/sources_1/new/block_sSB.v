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

    parameter FLAT_IDX_MAX = N*(N-1)/2+N-1,     // Maximum flattened index value

    parameter FLAT_IDX_WIDTH = $clog2(FLAT_IDX_MAX+1),         // Width for flattened index
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


// State definitions
localparam STOPPED = 0;
localparam INIT = 1;
localparam RUNNING = 2;
localparam WRITE = 3;

genvar gi;
genvar gs;


// Write index for output BRAM
reg [WRITE_INDEX_WIDTH-1:0] out_idx;

reg [BLOCK_IDX_WIDTH-1:0] block_idx;


if (BLOCK_SIZE < OUT_BRAM_WIDTH) begin
    $error("BLOCK_SIZE (%d) must be greater than or equal to OUT_BRAM_WIDTH (%d)", BLOCK_SIZE, OUT_BRAM_WIDTH);
end

// State variables
reg [1:0] state;
assign stopped = (state == STOPPED);
assign running = (state == RUNNING);
assign writing = (state == WRITE);
assign initializing = (state == INIT);
reg block_idx_rst;

// Block Index Iterator
localparam STAGE = 10;
wire [BLOCK_IDX_WIDTH-1:0] i;
wire [BLOCK_IDX_WIDTH-1:0] j;
wire [FLAT_IDX_WIDTH-1:0] flat_idx;
wire request_stop;

reg [BLOCK_IDX_WIDTH-1:0] stage_i [0:STAGE];
reg [BLOCK_IDX_WIDTH-1:0] stage_j [0:STAGE];
reg [FLAT_IDX_WIDTH-1:0] stage_flat_idx [0:STAGE];
reg stage_request_stop [0:STAGE];
always @(*) begin
    stage_i[0] = i;
    stage_j[0] = j;
    stage_flat_idx[0] = flat_idx;
    stage_request_stop[0] = request_stop;
end

wire [STEP_WIDTH-1:0] step;
block_index_iterator #(
    .N      (N_BLOCK_PER_ROW),
    .STEPS  (STEPS)
) block_index_iterator_i (
    .clk            (clk),
    .rst            (block_idx_rst),
    .i              (i),
    .j              (j),
    .flat_idx       (flat_idx),
    .step           (step),
    .request_stop   (request_stop)
);
generate
    for (gs = 0; gs < STAGE; gs = gs + 1) begin : gen_stage_reg
        always @(posedge clk) begin
            stage_i[gs+1] <= stage_i[gs];
            stage_j[gs+1] <= stage_j[gs];
            stage_flat_idx[gs+1] <= stage_flat_idx[gs];
            stage_request_stop[gs+1] <= stage_request_stop[gs];
        end
    end
endgenerate

reg [$clog2(STAGE)-1:0] stage_idx;
always @(posedge clk) begin
    if (block_idx_rst)
        stage_idx <= 0;
    else if (stage_idx + 2 < STAGE)
        stage_idx <= stage_idx + 1;
end




/*   0         1        2         3             4             5            6            7             8
 *
 *             j ---- x_hat -
 *                           \
 *  i,j ------ J  ----- J ----- mm_out -         i --------              y_fix --       i ---------
 *                                      \                /                        \              /
 *                      i ----- mm_acc ---- mm_acc_new ---- g_fix ------ g_hat ----- y_fix_new --
 *                                      /               /                        /
 *                                 j ---    --- lhs ----                - oob ---
 *                                         /                           /
 *                      i ------ x_fix ------- x_fix ---              -- r_oob ---                     i ---------
 *                                                      \            / - l_oob -- \                             /
 *                      i ------ y_fix ------- y_hat ------ x_next ----- x_next ---- x_fix_new ---- x_hat_new --
 *                                         \                           x_init_sign /              \
 *                                          -- y_fix ------ y_fix ------ y_fix           i ---------
 */


// Calculate the stage of x_hat_j
localparam X_HAT_IS_BRAM = 0;
localparam X_HAT_OUTREG = 1;

localparam STAGE_X_HAT_LOAD = 1;
localparam STAGE_X_HAT_ARRIVE = STAGE_X_HAT_LOAD + X_HAT_IS_BRAM + X_HAT_OUTREG;


// Calculate the stage of J
localparam J_IS_BRAM = 1;
localparam J_OUTREG = 1;
localparam BLOCK_MATMUL_OUTREG = 1;

localparam STAGE_J_LOAD = 0;
localparam STAGE_J_ARRIVE = STAGE_J_LOAD + J_IS_BRAM + J_OUTREG;
localparam STAGE_MATMUL_OUT_ARRIVE = STAGE_J_ARRIVE + BLOCK_MATMUL_OUTREG;

if (STAGE_X_HAT_ARRIVE != STAGE_J_ARRIVE)
    $error("`x_hat_j` data arrival stage (%d) does not match `J_local_ij` arrival stage (%d), cannot calculate `block_matmul_out_i` correctly.", STAGE_X_HAT_ARRIVE, STAGE_J_ARRIVE);


// Calculate the stage of block_matmul_acc
localparam BLOCK_MATMUL_ACC_IS_BRAM = 0;
localparam BLOCK_MATMUL_ACC_OUTREG = 1;
localparam BLOCK_MATMUL_ACCREG = 1;

localparam STAGE_BLOCK_MATMUL_ACC_LOAD = 2;
localparam STAGE_BLOCK_MATMUL_ACC_ARRIVE = STAGE_BLOCK_MATMUL_ACC_LOAD + BLOCK_MATMUL_ACC_IS_BRAM + BLOCK_MATMUL_ACC_OUTREG;

if (STAGE_BLOCK_MATMUL_ACC_ARRIVE != STAGE_MATMUL_OUT_ARRIVE)
    $error("`block_matmul_out_i` arrival stage (%d) does not match `block_matmul_acc_i` arrival stage (%d), cannot calculate `block_matmul_acc_i_new` correctly.", STAGE_MATMUL_OUT_ARRIVE, STAGE_BLOCK_MATMUL_ACC_ARRIVE);


localparam STAGE_BLOCK_MATMUL_ACC_NEW_ARRIVE = STAGE_BLOCK_MATMUL_ACC_ARRIVE + BLOCK_MATMUL_ACCREG;

// Calculate the stage of dynamics
localparam X_FIX_IS_BRAM = 0;
localparam X_FIX_OUTREG = 1;

localparam STAGE_X_FIX_LOAD = 2;
localparam STAGE_X_FIX_ARRIVE = STAGE_X_FIX_LOAD + X_FIX_IS_BRAM + X_FIX_OUTREG;

localparam Y_FIX_IS_BRAM = 0;
localparam Y_FIX_OUTREG = 1;

localparam STAGE_Y_FIX_LOAD = 2;
localparam STAGE_Y_FIX_ARRIVE = STAGE_Y_FIX_LOAD + Y_FIX_IS_BRAM + Y_FIX_OUTREG;


localparam G_LHS_REG = 1;
localparam STAGE_G_LHS_ARRIVE = STAGE_X_FIX_ARRIVE + G_LHS_REG;
if (STAGE_G_LHS_ARRIVE != STAGE_BLOCK_MATMUL_ACC_NEW_ARRIVE)
    $error("`g_lhs` arrival stage (%d) does not match the `block_matmul_acc_i_new` arrival stage (%d), cannot calculate `g_fix_i` correctly.", STAGE_G_LHS_ARRIVE, STAGE_BLOCK_MATMUL_ACC_NEW_ARRIVE);


localparam G_FIX_REG = 1;
localparam STAGE_G_FIX_ARRIVE = STAGE_G_LHS_ARRIVE + G_FIX_REG;

localparam G_HAT_OUTREG = 1;
localparam STAGE_G_HAT_ARRIVE = STAGE_G_FIX_ARRIVE + G_HAT_OUTREG;

localparam Y_FIX_NEW_REG = 1;
localparam STAGE_Y_FIX_NEW_ARRIVE = STAGE_G_HAT_ARRIVE + Y_FIX_NEW_REG;



localparam Y_HAT_OUTREG = 1;
localparam STAGE_Y_HAT_ARRIVE = STAGE_X_FIX_ARRIVE + Y_HAT_OUTREG;

localparam X_NEXT_REG = 1;
localparam STAGE_X_NEXT_ARRIVE = STAGE_Y_HAT_ARRIVE + X_NEXT_REG;

localparam OOB_REG = 1;
localparam STAGE_OOB_ARRIVE = STAGE_X_NEXT_ARRIVE + OOB_REG;

if (STAGE_OOB_ARRIVE != STAGE_G_HAT_ARRIVE)
    $error("`oob` arrival stage (%d) does not match `g_hat` arrival stage (%d), cannot calculate `y_fix_new` correctly.", STAGE_OOB_ARRIVE, STAGE_G_HAT_ARRIVE);


localparam LROOB_REG = 1;
localparam STAGE_LROOB_ARRIVE = STAGE_X_NEXT_ARRIVE + LROOB_REG;

localparam X_FIX_NEW_REG = 1;
localparam STAGE_X_FIX_NEW_ARRIVE = STAGE_LROOB_ARRIVE + X_FIX_NEW_REG;

localparam X_HAT_NEW_OUTREG = 1;
localparam STAGE_X_HAT_NEW_ARRIVE = STAGE_X_FIX_NEW_ARRIVE + X_HAT_NEW_OUTREG;


// Stage indices for the block index iterator
reg [BLOCK_IDX_WIDTH-1:0] stage_block_idx [STAGE_X_NEXT_ARRIVE:STAGE_X_HAT_NEW_ARRIVE];
always @(*) stage_block_idx[STAGE_X_NEXT_ARRIVE] = block_idx;
generate
    for (gs = STAGE_X_NEXT_ARRIVE; gs < STAGE_X_HAT_NEW_ARRIVE; gs = gs + 1) begin : gen_stage_block_idx
        always @(posedge clk) stage_block_idx[gs+1] <= stage_block_idx[gs];
    end
endgenerate


// Memory for x_fix
wire [0:BLOCK_SIZE*X_WIDTH-1] x_fix_i_packed;
wire [0:BLOCK_SIZE*X_WIDTH-1] x_fix_i_packed_new;
dual_lutram_gen #(
    .WIDTH          (BLOCK_SIZE * X_WIDTH),
    .DEPTH          (N_BLOCK_PER_ROW),
    .ADDR_WIDTH     (BLOCK_IDX_WIDTH),
    .ENABLE_OUTREGB (X_FIX_OUTREG)
) x_fix_mem (
    .clk    (clk),
    .addra  (running ? stage_i[STAGE_X_FIX_NEW_ARRIVE] : stage_block_idx[STAGE_X_FIX_NEW_ARRIVE]),
    .dina   (x_fix_i_packed_new),
    .wea    (initializing || (running && stage_j[STAGE_X_FIX_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1)),
    .douta  (),
    .addrb  (stage_i[STAGE_X_FIX_LOAD]),
    .doutb  (x_fix_i_packed)
);

// Memory for y_fix
wire [0:BLOCK_SIZE*Y_WIDTH-1] y_fix_i_packed;
wire [0:BLOCK_SIZE*Y_WIDTH-1] y_fix_i_packed_new;
dual_lutram_gen #(
    .WIDTH          (BLOCK_SIZE * Y_WIDTH),
    .DEPTH          (N_BLOCK_PER_ROW),
    .ADDR_WIDTH     (BLOCK_IDX_WIDTH),
    .ENABLE_OUTREGB (Y_FIX_OUTREG)
) y_fix_mem (
    .clk    (clk),
    .addra  (running ? stage_i[STAGE_Y_FIX_NEW_ARRIVE] : stage_block_idx[STAGE_Y_FIX_NEW_ARRIVE]),
    .dina   (y_fix_i_packed_new),
    .wea    (initializing || (running && stage_j[STAGE_Y_FIX_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1)),
    .douta  (),
    .addrb  (stage_i[STAGE_Y_FIX_LOAD]),
    .doutb  (y_fix_i_packed)
);

// Memory for x_hat
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed; // used for matrix multiplication
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_i_packed_new; // packed x_hat_i_new
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_i_packed; // packed x_hat_i
dual_lutram_gen #(
    .WIDTH          (BLOCK_SIZE * X_HAT_WIDTH),
    .DEPTH          (N_BLOCK_PER_ROW),
    .ADDR_WIDTH     (BLOCK_IDX_WIDTH),
    .ENABLE_OUTREGB (X_HAT_OUTREG)
) x_hat_mem (
    .clk    (clk),
    .addra  (initializing ? stage_block_idx[STAGE_X_HAT_NEW_ARRIVE] :
             running ? stage_i[STAGE_X_HAT_NEW_ARRIVE] :
             writing ? block_idx : 0),
    .dina   (x_hat_i_packed_new),
    .wea    (initializing || (running && stage_j[STAGE_X_HAT_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1)),
    .douta  (x_hat_i_packed),
    .addrb  (stage_j[STAGE_X_HAT_LOAD]),
    .doutb  (x_hat_j_packed)
);

// Local Coefficient Matrix
wire [0:BLOCK_DATA_WIDTH-1] J_local_ij;
wire [0:BLOCK_DATA_WIDTH-1] J_local_ji;
J_block_bram_loader #(
    .N              (N),
    .BLOCK_SIZE     (BLOCK_SIZE),
    .ENABLE_OUTREG  (J_OUTREG)
) J_block_bram_loader_i (
    .clk        (clk),
    .i          (stage_i[STAGE_J_LOAD]),
    .j          (stage_j[STAGE_J_LOAD]),
    .flat_idx   (stage_flat_idx[STAGE_J_LOAD]),
    .out_ij     (J_local_ij),
    .out_ji     (J_local_ji)
);




// Memory for accumulated vector of the matrix multiplication
wire [0:BLOCK_SIZE*MUL_WIDTH-1] block_matmul_acc_i_packed;
wire [0:BLOCK_SIZE*MUL_WIDTH-1] block_matmul_acc_i_packed_new; // packed block_matmul_acc_i_new
if (STAGE_BLOCK_MATMUL_ACC_NEW_ARRIVE == STAGE_BLOCK_MATMUL_ACC_ARRIVE && BLOCK_MATMUL_ACC_OUTREG == 0) begin
    $info("Using single port LUTRAM for block matrix multiplication accumulation storage, since there is no delay between the load stage and write stage, the block_matmul_acc_i_packed_new will be written directly to the memory.");
    lutram_gen #(
        .WIDTH          (BLOCK_SIZE * MUL_WIDTH),
        .DEPTH          (N_BLOCK_PER_ROW),
        .ADDR_WIDTH     (BLOCK_IDX_WIDTH),
        .ENABLE_OUTREG  (BLOCK_MATMUL_ACC_OUTREG)
    ) block_matmul_acc_mem (
        .clk    (clk),
        .addr   (stage_i[STAGE_BLOCK_MATMUL_ACC_LOAD]),
        .din    (block_matmul_acc_i_packed_new),
        .dout   (block_matmul_acc_i_packed),
        .we     (running)
    );
end else begin
    $info("Using dual port LUTRAM for block matrix multiplication accumulation storage, since there is a delay between the load stage and write stage, the block_matmul_acc_i_packed_new will be written to the memory after the load stage.");
    dual_lutram_gen #(
        .WIDTH          (BLOCK_SIZE * MUL_WIDTH),
        .DEPTH          (N_BLOCK_PER_ROW),
        .ADDR_WIDTH     (BLOCK_IDX_WIDTH),
        .ENABLE_OUTREGB (BLOCK_MATMUL_ACC_OUTREG)
    ) block_matmul_acc_mem (
        .clk    (clk),
        .addra  (stage_i[STAGE_BLOCK_MATMUL_ACC_NEW_ARRIVE]),
        .dina   (block_matmul_acc_i_packed_new),
        .douta  (), // Not used
        .wea    (running),
        .addrb  (stage_i[STAGE_BLOCK_MATMUL_ACC_LOAD]),
        .doutb  (block_matmul_acc_i_packed)
    );
end


// Block Matrix multiplication result
wire [0:BLOCK_SIZE*BLOCK_MUL_WIDTH-1] block_matmul_out_i_packed;
matmul #(
    .N              (BLOCK_SIZE),
    .M              (BLOCK_SIZE),
    .CHUNK          (1),
    .ENABLE_OUTREG  (BLOCK_MATMUL_OUTREG)
) matmul_i (
    .clk            (clk),
    .J              (J_local_ij),
    .x              (x_hat_j_packed),
    .is_diagonal    (stage_i[STAGE_J_ARRIVE] == stage_j[STAGE_J_ARRIVE]),
    .out            (block_matmul_out_i_packed)
);

wire signed [MUL_WIDTH-1:0] block_matmul_acc_i [0:BLOCK_SIZE-1]; // unpacked block_matmul_acc_i_packed
wire signed [BLOCK_MUL_WIDTH-1:0] block_matmul_out_i [0:BLOCK_SIZE-1]; // unpacked block_matmul_out_i_packed
reg signed [MUL_WIDTH-1:0] block_matmul_acc_i_new [0:BLOCK_SIZE-1]; // block_matmul_acc_i + block_matmul_out_j
generate
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : gen_next_tmp_j
        assign block_matmul_out_i[gi] = block_matmul_out_i_packed[gi*BLOCK_MUL_WIDTH +: BLOCK_MUL_WIDTH];
        assign block_matmul_acc_i[gi] = block_matmul_acc_i_packed[gi*MUL_WIDTH +: MUL_WIDTH];
        if (BLOCK_MATMUL_ACCREG)
            always @(posedge clk) block_matmul_acc_i_new[gi] <= stage_j[STAGE_BLOCK_MATMUL_ACC_ARRIVE] == 0 ? block_matmul_out_i[gi] : block_matmul_acc_i[gi] + block_matmul_out_i[gi];
        else
            always @(*) block_matmul_acc_i_new[gi] = stage_j[STAGE_BLOCK_MATMUL_ACC_ARRIVE] == 0 ? block_matmul_out_i[gi] : block_matmul_acc_i[gi] + block_matmul_out_i[gi];
        assign block_matmul_acc_i_packed_new[gi*MUL_WIDTH +: MUL_WIDTH] = block_matmul_acc_i_new[gi];
    end
endgenerate



// Dynamics update pipeline
generate
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : calculate_dynamics

        // Unpack
        wire signed [X_WIDTH-1:0] x_fix = x_fix_i_packed[gi*X_WIDTH +: X_WIDTH];
        wire signed [Y_WIDTH-1:0] y_fix = y_fix_i_packed[gi*Y_WIDTH +: Y_WIDTH];
        wire signed [MUL_WIDTH-1:0] block_matmul_acc_new = block_matmul_acc_i_new[gi];


        // Extend x_fix to match the stage of y_hat, since x_next <= x_fix + y_hat
        reg signed [X_WIDTH-1:0] stage_x_fix [STAGE_X_FIX_ARRIVE:STAGE_Y_HAT_ARRIVE];
        for (gs = STAGE_X_FIX_ARRIVE; gs < STAGE_Y_HAT_ARRIVE; gs = gs + 1)
            always @(posedge clk) stage_x_fix[gs+1] <= stage_x_fix[gs];


        // Extend y_fix to match the stage of g_hat, since y_fix_new <= oob ? 0 : y_fix + g_hat
        reg signed [Y_WIDTH-1:0] stage_y_fix [STAGE_Y_FIX_ARRIVE:STAGE_G_HAT_ARRIVE];
        for (gs = STAGE_Y_FIX_ARRIVE; gs < STAGE_G_HAT_ARRIVE; gs = gs + 1)
            always @(posedge clk) stage_y_fix[gs+1] <= stage_y_fix[gs];

        // Extend x_next to match the stage of oob
        reg signed [X_NEXT_WIDTH-1:0] stage_x_next [STAGE_X_NEXT_ARRIVE:STAGE_LROOB_ARRIVE];
        for (gs = STAGE_X_NEXT_ARRIVE; gs < STAGE_LROOB_ARRIVE; gs = gs + 1)
            always @(posedge clk) stage_x_next[gs+1] <= stage_x_next[gs];


        always @(*) stage_x_fix[STAGE_X_FIX_ARRIVE] = x_fix;
        always @(*) stage_y_fix[STAGE_Y_FIX_ARRIVE] = y_fix;


        // Initialization of x_fix_init_sign
        wire x_fix_init_sign;
        if (RANDOM_INIT)
            rand #(
                .WIDTH  (1)
            ) r_x_init (
                .clk    (clk),
                .out    (x_fix_init_sign)
            );
        else
            assign x_fix_init_sign = 1'b0; // Default to positive


        // g_lhs calculation: g_lhs = (step - 2^(K_BETA + K_ETA)) * x_fix
        reg signed [G_WIDTH-1:0] g_lhs;
        if (G_LHS_REG)  always @(posedge clk) g_lhs <= ($signed({1'b0, step}) - (1 << (K_BETA + K_ETA))) * stage_x_fix[STAGE_X_FIX_ARRIVE];
        else            always @(*) g_lhs = ($signed({1'b0, step}) - (1 << (K_BETA + K_ETA))) * stage_x_fix[STAGE_X_FIX_ARRIVE];


        // g_fix calculation: g_fix = g_lhs + (block_matmul_acc_new <<< (K_BETA + 2*K_ETA - K_XI));
        reg signed [G_WIDTH-1:0] g_fix;
        wire signed [G_WIDTH:0] g_rhs = {block_matmul_acc_new, {(K_BETA + 2*K_ETA - K_XI){1'b0}}};
        if (G_FIX_REG)  always @(posedge clk) g_fix <= g_lhs + g_rhs;
        else            always @(*) g_fix = g_lhs + g_rhs;


        // g_hat generation: g_hat = R(g_fix)
        wire signed [G_HAT_WIDTH-1:0] g_hat;
        rand_near #(
            .WIDTH          (G_WIDTH),
            .OUT_WIDTH      (G_HAT_WIDTH),
            .RAND_WIDTH     (2*K_ETA+K_BETA),
            .ENABLE_OUTREG  (G_HAT_OUTREG)
        ) r_g_i (
            .clk        (clk),
            .in         (g_fix),
            .out        (g_hat)
        );


        // y_hat generation: y_hat = R(y_fix)
        wire signed [Y_HAT_WIDTH-1:0] y_hat;
        rand_near #(
            .WIDTH          (Y_WIDTH),
            .OUT_WIDTH      (Y_HAT_WIDTH),
            .RAND_WIDTH     (K_ETA),
            .ENABLE_OUTREG  (Y_HAT_OUTREG)
        ) r_y_i (
            .clk    (clk),
            .in     (stage_y_fix[STAGE_Y_FIX_ARRIVE]),
            .out    (y_hat)
        );


        // x_next calculation
        reg signed [X_NEXT_WIDTH-1:0] x_next;
        if (X_NEXT_REG) always @(posedge clk) x_next <= stage_x_fix[STAGE_Y_HAT_ARRIVE] + y_hat;
        else            always @(*) x_next = stage_x_fix[STAGE_Y_HAT_ARRIVE] + y_hat;

        always @(*) stage_x_next[STAGE_X_NEXT_ARRIVE] = x_next;


        // out_of_bounds
        reg oob;
        if (OOB_REG)    always @(posedge clk) oob <= (x_next > (1 << K_ETA)) || (x_next < -(1 << K_ETA));
        else            always @(*) oob = (x_next > (1 << K_ETA)) || (x_next < -(1 << K_ETA));


        // y_fix_new generation
        reg [Y_WIDTH-1:0] y_fix_new;
        if (Y_FIX_NEW_REG)  always @(posedge clk) y_fix_new <= oob || initializing ? 0 : stage_y_fix[STAGE_G_HAT_ARRIVE] + g_hat;
        else                always @(*) y_fix_new = oob || initializing ? 0 : stage_y_fix[STAGE_G_HAT_ARRIVE] + g_hat;


        // right_out_of_bounds and left_out_of_bounds
        reg roob;
        reg loob;
        if (LROOB_REG)
            always @(posedge clk) begin
                roob <= x_next > (1 << K_ETA);
                loob <= x_next < -(1 << K_ETA);
            end
        else
            always @(*) begin
                roob = x_next > (1 << K_ETA);
                loob = x_next < -(1 << K_ETA);
            end


        // x_fix_new calculation
        reg signed [X_WIDTH-1:0] x_fix_new;
        if (X_FIX_NEW_REG)
            always @(posedge clk) begin
                if (initializing)
                    x_fix_new <= x_fix_init_sign ? -1 : 1; // Initialize to -1 or 1 based on sign
                else if (roob)
                    x_fix_new <= 1 << K_ETA; // Right out of bounds, set to 1 << K_ETA
                else if (loob)
                    x_fix_new <= -1 << K_ETA; // Left out of bounds, set to -1 << K_ETA
                else
                    x_fix_new <= stage_x_next[STAGE_LROOB_ARRIVE]; // Normal case, update with x_fix + y_hat
            end
        else
            always @(*) begin
                if (initializing)
                    x_fix_new = x_fix_init_sign ? -1 : 1; // Initialize to -1 or 1 based on sign
                else if (roob)
                    x_fix_new = 1 << K_ETA; // Right out of bounds, set to 1 << K_ETA
                else if (loob)
                    x_fix_new = -1 << K_ETA; // Left out of bounds, set to -1 << K_ETA
                else
                    x_fix_new = stage_x_next[STAGE_LROOB_ARRIVE]; // Normal case, update with x_fix + y_hat
            end


        // x_hat_new generation
        wire signed [X_HAT_WIDTH-1:0] x_hat_new;
        rand_near #(
            .WIDTH          (X_WIDTH),
            .OUT_WIDTH      (X_HAT_WIDTH),
            .RAND_WIDTH     (K_ETA),
            .ENABLE_OUTREG  (X_HAT_NEW_OUTREG)
        ) r_x_i (
            .clk        (clk),
            .in         (x_fix_new),
            .out        (x_hat_new)
        );


        // assign new values to packed arrays for storage
        assign x_fix_i_packed_new[gi*X_WIDTH +: X_WIDTH] = x_fix_new;
        assign y_fix_i_packed_new[gi*Y_WIDTH +: Y_WIDTH] = y_fix_new;
        assign x_hat_i_packed_new[gi*X_HAT_WIDTH +: X_HAT_WIDTH] = x_hat_new;

    end
endgenerate



integer k;

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
            if (stage_block_idx[STAGE_X_HAT_NEW_ARRIVE] == N_BLOCK_PER_ROW - 1) begin
                state <= RUNNING;
            end else begin
                block_idx <= block_idx + 1;
                block_idx_rst <= 1'b1;
            end
        end

        RUNNING: begin

            if (stage_request_stop[STAGE_X_HAT_NEW_ARRIVE]) begin
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

                // Don't write to BRAM
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
