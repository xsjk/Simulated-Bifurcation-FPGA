`timescale 1ns / 1ps

module block_sSB  #(
    parameter N = 2000,
    parameter BLOCK_SIZE = 80,
    parameter STEPS = 50000,
    
    parameter N_BLOCK_PER_ROW = N / BLOCK_SIZE, // Number of blocks per row
    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW), // Width for block indices
    parameter BLOCK_DATA_WIDTH = BLOCK_SIZE * BLOCK_SIZE,
    
    parameter K_N = $clog2(N+1),                // Width for N
    parameter K_BLOCK = $clog2(BLOCK_SIZE+1),   // Width for block size
    parameter K_BETA = 14,                      // beta = 2^(-K_BETA)
    parameter K_XI = 6,                         // xi = 2^(-K_XI)
    parameter K_ETA = 1,                        // eta = 2^(-K_ETA)
    parameter K_X = 1,                          // |x| < 2^(K_X)
    parameter K_Y = 3,                          // |y| < 2^(K_Y)
    parameter K_G = 3,                          // |g| < 2^(K_G)
    parameter K_ALPHA = 2,                      // |sum(J_ij * x_i)| < 2^(-K_ALPHA) * N

    parameter STEP_WIDTH = $clog2(STEPS),           // Width for step
    parameter BLOCK_MUL_WIDTH = 1 + K_BLOCK,        // Width for sum(J_ij * x_i) on block level
    parameter MUL_WIDTH = 1 + K_N - K_ALPHA,        // Width for sum(J_ij * x_i)
    parameter X_WIDTH = 1 + K_X + K_ETA,            // Width for x
    parameter Y_WIDTH = 1 + K_Y + K_ETA,            // Width for y
    parameter G_WIDTH = 1 + K_G + (2*K_ETA+K_BETA), // Width for g
    parameter X_HAT_WIDTH = 1 + K_X,                // Width for x_hat
    parameter Y_HAT_WIDTH = 1 + K_Y,                // Width for y_hat
    parameter G_HAT_WIDTH = 1 + K_G,                // Width for g_hat
    
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


// State definitions 
localparam STOPPED = 0;
localparam INIT = 1;
localparam RUNNING = 2;
localparam WRITE = 3;

genvar gi;


// Write index for output BRAM
reg [WRITE_INDEX_WIDTH-1:0] write_index;

// Initialization index for output BRAM
reg [WRITE_INDEX_WIDTH-1:0] init_index;





// State variables
reg [1:0] state;
assign stopped = (state == STOPPED);
assign running = (state == RUNNING);
assign initializing = (state == INIT);
reg block_index_rst;

// Block Index 
wire [BLOCK_IDX_WIDTH-1:0] i;
wire [BLOCK_IDX_WIDTH-1:0] j;
wire [BLOCK_IDX_WIDTH-1:0] next_i;
wire [BLOCK_IDX_WIDTH-1:0] next_j;
wire initialized;
wire [STEP_WIDTH-1:0] step;
wire request_stop;
block_index_iterator #(
    .N          (N_BLOCK_PER_ROW),
    .STEPS      (STEPS)
) block_index_iterator_i (
    .clk            (clk),
    .rst            (block_index_rst),
    .i              (i),
    .j              (j),
    .next_i         (next_i),
    .next_j         (next_j),
    .initialized    (initialized),
    .step           (step),
    .request_stop   (request_stop)
);


// Memory for accumulated vector of the matrix multiplication
wire [0:BLOCK_SIZE*(X_WIDTH+Y_WIDTH)-1] xy_fix_i_packed;
wire [0:BLOCK_SIZE*(X_WIDTH+Y_WIDTH)-1] xy_fix_i_packed_new;

wire [BLOCK_IDX_WIDTH-1:0] xy_fix_addr = (
    initializing ? init_index : 
    running ? (
        next_j == N_BLOCK_PER_ROW - 1 ? next_i : 
        j == N_BLOCK_PER_ROW - 1 ? i : 0
    ) : 0
);
wire xy_fix_we = initializing || (running && j == N_BLOCK_PER_ROW - 1);


lutram_gen #(
    .WIDTH          (BLOCK_SIZE * (X_WIDTH + Y_WIDTH)),
    .DEPTH          (N_BLOCK_PER_ROW),
    .ADDR_WIDTH     (BLOCK_IDX_WIDTH)
) xy_fix_mem (
    .clk            (clk),
    .addr           (xy_fix_addr),
    .din            (xy_fix_i_packed_new),
    .dout           (xy_fix_i_packed),
    .we             (xy_fix_we)
);


// Local Coefficient Matrix
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


(* ram_style = "registers" *)
reg signed [X_HAT_WIDTH-1:0] x_hat [0:N-1];

// x_hat_local arrays
wire [0:BLOCK_SIZE*X_HAT_WIDTH-1] x_hat_j_packed; // used for matrix multiplication
generate
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : gen_x_hat_packed
        assign x_hat_j_packed[gi*X_HAT_WIDTH +: X_HAT_WIDTH] = x_hat[j * BLOCK_SIZE + gi];
    end
endgenerate

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

if (BLOCK_SIZE*MUL_WIDTH != 800) begin
    $error("Customization of matmul_acc_bram to fit the data width (%d) is required", BLOCK_SIZE*MUL_WIDTH);
end


// Block Matrix multiplication result
wire [0:BLOCK_SIZE*BLOCK_MUL_WIDTH-1] block_matmul_out_i_packed;
matmul #(
    .N              (BLOCK_SIZE),
    .M              (BLOCK_SIZE),
    .CHUNK          (1)
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


if (OUT_BRAM_DEPTH < $clog2((N-1)/OUT_BRAM_WIDTH+1)) begin
    $error("OUT_BRAM_DEPTH (%d) is not sufficient for N (%d) bits.", OUT_BRAM_DEPTH, N);
end




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

    end
endgenerate



integer k;

always @(posedge clk) begin

    // Default values
    block_index_rst <= 1'b0;
    state <= STOPPED;
    BRAM_addr <= 0;
    BRAM_din <= 0;
    BRAM_en <= 0;
    BRAM_we <= 0;
    write_index <= 0;
    init_index <= 0;

    
    // State machine
    case (state)
        STOPPED: begin
            if (request_start)
                state <= INIT;
        end

        INIT: begin
            
            for (k = 0; k < BLOCK_SIZE; k = k + 1) begin
                x_hat[xy_fix_addr * BLOCK_SIZE + k] <= x_hat_i_new[k];
            end
            if (init_index == N_BLOCK_PER_ROW - 1) begin
                state <= RUNNING;
            end else begin
                state <= INIT;
                init_index <= init_index + 1;
                block_index_rst <= 1'b1; 
            end
        end
        
        RUNNING: begin
            state <= RUNNING;

            if (j == N_BLOCK_PER_ROW - 1) begin
                // write new x_fix[i] and y_fix[i]

                // Update dynamics when j == N-1
                // $display("Step %d: Updating dynamics for chunk (%2d)", step, real_i);
                for (k = 0; k < BLOCK_SIZE; k = k + 1) begin
                    x_hat[xy_fix_addr * BLOCK_SIZE + k] <= x_hat_i_new[k];
                end


                // $write("block_matmul_acc_i_new[%2d] = [", i); 
                // for (k = 0; k < BLOCK_SIZE; k = k + 1) 
                //     $write("%3d,", block_matmul_acc_i_new[k]);
                // $write("]\n");

                // $write("g_fix_i[%2d] = [", i);
                // for (k = 0; k < BLOCK_SIZE; k = k + 1) 
                //     $write("%5d,", g_fix_i[k]);
                // $write("]\n");

                // $write("g_hat_i[%2d] = [", i);
                // for (k = 0; k < BLOCK_SIZE; k = k + 1) 
                //     $write("%1d,", g_hat_i[k]);
                // $write("]\n");

                // $write("y_fix_i_new[%2d] = [", i);
                // for (k = 0; k < BLOCK_SIZE; k = k + 1) 
                //     $write("%2d,", y_fix_i_new[k]);
                // $write("]\n");

                // $write("x_fix_i_new[%2d] = [", i);
                // for (k = 0; k < BLOCK_SIZE; k = k + 1) 
                //     $write("%2d,", x_fix_i_new[k]);
                // $write("]\n");

                // $write("\n");
                
            end else begin
                // Keep the current values for x_fix, y_fix, and x_hat
            end

            // Display x_hat 
            if (i == N_BLOCK_PER_ROW - 1 && j == 0) begin
                 $display("Step = %d", step);
                 $write("x_hat = [");
                 for (k = 0; k < N; k = k + 1)
                     $write("%1d,", x_hat[k]);
                 $write("]\n");
                //  $write("x_fix = [");
                //  for (k = 0; k < N; k = k + 1)
                //      $write("%1d,", x_fix[k]);
                //  $write("]\n");
                //  $write("y_fix = [");
                //  for (k = 0; k < N; k = k + 1)
                //      $write("%1d,", y_fix[k]);
                //  $write("]\n");
                 $write("\n");
            end

            if (i == N_BLOCK_PER_ROW - 1 && j == N_BLOCK_PER_ROW - 1 && request_stop) begin
                state <= WRITE;
            end

        end
        
        WRITE: begin  
            
            if (write_index <= N / OUT_BRAM_WIDTH) begin
                state <= WRITE;

                write_index <= write_index + 1;
                BRAM_en <= 1;
                BRAM_we <= 4'b1111; // Write all bytes
                BRAM_addr <= write_index;
                for (k = 0; k < OUT_BRAM_WIDTH; k = k + 1) begin
                    if ((write_index * OUT_BRAM_WIDTH + k) < N)
                        BRAM_din[k] <= x_hat[write_index * OUT_BRAM_WIDTH + k][X_HAT_WIDTH-1]; // Use the sign bit of x_hat
                    else 
                        BRAM_din[k] <= 1'b0;
                end
            end
        end

    endcase

end


endmodule
