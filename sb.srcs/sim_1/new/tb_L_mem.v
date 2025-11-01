`timescale 1ns / 1ps

module tb_L_mem;

localparam N = 16;
localparam BLOCK_SIZE = 4;
localparam N_BLOCK_PER_ROW = N / BLOCK_SIZE;
localparam BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW);
localparam K_BLOCK = $clog2(BLOCK_SIZE + 1);
localparam BLOCK_MUL_WIDTH = 1 + K_BLOCK;
localparam K_ALPHA = 0;
localparam K_N = $clog2(N + 1);
localparam MUL_WIDTH = 1 + K_N - K_ALPHA;
localparam IDX_MAX = N_BLOCK_PER_ROW * (N_BLOCK_PER_ROW + 1) / 2 - 1;
localparam IDX_WIDTH = $clog2(IDX_MAX + 1);
localparam STEPS = 2;
localparam STEP_WIDTH = $clog2(STEPS);
localparam integer TOTAL_SCALARS = STEPS * N_BLOCK_PER_ROW * N_BLOCK_PER_ROW * BLOCK_SIZE;
localparam integer TOTAL_L_SCALARS = STEPS * N_BLOCK_PER_ROW * BLOCK_SIZE;

reg clk;
reg rst;

wire [BLOCK_IDX_WIDTH-1:0] i;
wire [BLOCK_IDX_WIDTH-1:0] j;
wire [BLOCK_IDX_WIDTH-1:0] next_i;
wire [BLOCK_IDX_WIDTH-1:0] next_j;
wire [IDX_WIDTH-1:0] flat_idx;
wire [IDX_WIDTH-1:0] next_flat_idx;
wire initialized;
wire [STEP_WIDTH-1:0] step;
wire request_stop;

wire [0:MUL_WIDTH*BLOCK_SIZE-1] L_i_packed_new;
wire [0:MUL_WIDTH*BLOCK_SIZE-1] L_j_packed_new;

integer show_idx;
reg signed [BLOCK_MUL_WIDTH-1:0] delta_scalar [0:STEPS-1][0:N_BLOCK_PER_ROW-1][0:N_BLOCK_PER_ROW-1][0:BLOCK_SIZE-1]; // delta_scalar[step][row][col][elem]
reg signed [MUL_WIDTH-1:0] L_scalar [0:STEPS-1][0:N_BLOCK_PER_ROW-1][0:BLOCK_SIZE-1]; // L_scalar[step][col][elem]
reg signed [MUL_WIDTH-1:0] expected_value;
reg signed [MUL_WIDTH-1:0] actual_value;

function [0:BLOCK_MUL_WIDTH*BLOCK_SIZE-1] pack_delta;
    input integer step_idx;
    input integer row_idx;
    input integer col_idx;
    integer elem_idx;
    reg [0:BLOCK_MUL_WIDTH*BLOCK_SIZE-1] pack;
    begin
        for (elem_idx = 0; elem_idx < BLOCK_SIZE; elem_idx = elem_idx + 1)
            pack[elem_idx*BLOCK_MUL_WIDTH +: BLOCK_MUL_WIDTH] = delta_scalar[step_idx][row_idx][col_idx][elem_idx];
        pack_delta = pack;
    end
endfunction

wire [0:BLOCK_MUL_WIDTH*BLOCK_SIZE-1] delta_L_i_packed = pack_delta(step, i, j); // In real computation, delta_L_i is matmul(J_ij, x_j)
wire [0:BLOCK_MUL_WIDTH*BLOCK_SIZE-1] delta_L_j_packed = pack_delta(step, j, i); // In real computation, delta_L_j is matmul(J_ji, x_i)

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    rst = 1'b1;
    #12;
    rst = 1'b0;
end

block_index_iterator #(
    .N          (N_BLOCK_PER_ROW),
    .STEPS      (STEPS)
) block_index_iterator_i (
    .clk            (clk),
    .rst            (rst),
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

L_mem #(
    .N                  (N),
    .BLOCK_SIZE         (BLOCK_SIZE),
    .BLOCK_MUL_WIDTH    (BLOCK_MUL_WIDTH),
    .MUL_WIDTH          (MUL_WIDTH)
) L_mem_i (
    .clk                (clk),
    .en                 (~rst),
    .i                  (i),
    .j                  (j),
    .next_i             (next_i),
    .next_j             (next_j),
    .delta_L_i_packed   (delta_L_i_packed),
    .delta_L_j_packed   (delta_L_j_packed),
    .L_i_packed_new     (L_i_packed_new),
    .L_j_packed_new     (L_j_packed_new)
);

initial begin : precompute_tables
    integer step_idx;
    integer row_idx;
    integer col_idx;
    integer elem_idx;
    integer signed_base;
    integer sum;
    integer rand_val;
    integer sel;
    integer seed;
    seed = 32'h1234_ABCD;
    for (step_idx = 0; step_idx < STEPS; step_idx = step_idx + 1) begin
        $display("Precomputed delta_L matrix for step %0d:", step_idx);
        for (row_idx = 0; row_idx < N_BLOCK_PER_ROW; row_idx = row_idx + 1) begin
            $write("  row %0d:", row_idx);
            for (col_idx = 0; col_idx < N_BLOCK_PER_ROW; col_idx = col_idx + 1) begin
                for (elem_idx = 0; elem_idx < BLOCK_SIZE; elem_idx = elem_idx + 1) begin
                    rand_val = $random(seed);
                    sel = rand_val % 3;
                    if (sel < 0) sel = sel + 3;
                    signed_base = sel - 1; // -1, 0, 1
                    delta_scalar[step_idx][row_idx][col_idx][elem_idx] = signed_base;
                end
                $write(" {");
                for (elem_idx = 0; elem_idx < BLOCK_SIZE; elem_idx = elem_idx + 1)
                    $write("%2d%s", delta_scalar[step_idx][row_idx][col_idx][elem_idx], (elem_idx == BLOCK_SIZE-1) ? "" : ",");
                $write("}");
            end
            $display("");
        end
        $display("Precomputed L for step %0d:", step_idx);
        for (row_idx = 0; row_idx < N_BLOCK_PER_ROW; row_idx = row_idx + 1)
            for (elem_idx = 0; elem_idx < BLOCK_SIZE; elem_idx = elem_idx + 1) begin
                sum = 0;
                for (col_idx = 0; col_idx < N_BLOCK_PER_ROW; col_idx = col_idx + 1)
                    sum = sum + delta_scalar[step_idx][row_idx][col_idx][elem_idx];
                L_scalar[step_idx][row_idx][elem_idx] = sum;
            end
        $write("     L = ");
        for (row_idx = 0; row_idx < N_BLOCK_PER_ROW; row_idx = row_idx + 1) begin
            $write("{");
            for (elem_idx = 0; elem_idx < BLOCK_SIZE; elem_idx = elem_idx + 1)
                $write("%2d%s", L_scalar[step_idx][row_idx][elem_idx], (elem_idx == BLOCK_SIZE-1) ? "" : ",");
            $write("}%s", (row_idx == N_BLOCK_PER_ROW-1) ? "" : " ");
        end
        $display("");
    end
end

always @(posedge clk) begin
    if (rst) begin
        for (show_idx = 0; show_idx < BLOCK_SIZE; show_idx = show_idx + 1) begin
            expected_value <= {MUL_WIDTH{1'b0}};
        end
    end else begin
        if (i == N_BLOCK_PER_ROW - 1) begin
            $write("Validate step=%0d, j=%0d, expected L = {", step, j);
            for (show_idx = 0; show_idx < BLOCK_SIZE; show_idx = show_idx + 1)
                $write("%2d%s", L_scalar[step][j][show_idx], (show_idx == BLOCK_SIZE-1) ? "" : ",");
            $write("}, actual L = {");
            for (show_idx = 0; show_idx < BLOCK_SIZE; show_idx = show_idx + 1)
                $write("%2d%s", $signed(L_j_packed_new[show_idx*MUL_WIDTH +: MUL_WIDTH]), (show_idx == BLOCK_SIZE-1) ? "" : ",");
            $display("}");
         end
     end

    if (request_stop) begin
        $display("Finished all iterations at time %0t", $time);
        $finish;
    end
end

endmodule