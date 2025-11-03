// A virtual memory module for x_hat with two read/write ports.
module L_mem #(
    parameter BLOCK_SIZE = 80,
    parameter N_BLOCK_PER_ROW = 25,
    parameter BLOCK_IDX_WIDTH = $clog2(N_BLOCK_PER_ROW),
    parameter DELTA_WIDTH = 0, // should be externally set
    parameter DATA_WIDTH = 0, // should be externally set
    parameter ENABLE_STOREREG = 0,
    parameter ENABLE_OUTREG = 0
)
(
    input wire clk,
    input wire en,
    input wire [BLOCK_IDX_WIDTH-1:0] i, // real port that directly accesses a gingle port lutram
    input wire [BLOCK_IDX_WIDTH-1:0] j, // virtual port that actrually accesses registered value thanks to the traversal order of (i,j)
    input wire [0:DELTA_WIDTH*BLOCK_SIZE-1] delta_i, // the offset to be added to L_i
    input wire [0:DELTA_WIDTH*BLOCK_SIZE-1] delta_j, // the offset to be added to L_j
    output reg [0:DATA_WIDTH*BLOCK_SIZE-1] dout_i, // updated L_i
    output reg [0:DATA_WIDTH*BLOCK_SIZE-1] dout_j // updated L_j
);

if (DELTA_WIDTH == 0 || DATA_WIDTH == 0) begin
    $error("Error: DELTA_WIDTH and DATA_WIDTH must be explicitly set");
end

genvar gi;

localparam STAGE_INPUT = 0;
localparam STAGE_LOAD = STAGE_INPUT;
localparam STAGE_ARRIVE = STAGE_LOAD + ENABLE_STOREREG;
localparam STAGE_ACC_ARRIVE = STAGE_ARRIVE;
localparam STAGE_WRITE = STAGE_ACC_ARRIVE;
localparam STAGE_OUTPUT = STAGE_WRITE + ENABLE_OUTREG;


// store the inputs through stages
reg stage_en [STAGE_INPUT:STAGE_OUTPUT];
reg [BLOCK_IDX_WIDTH-1:0] stage_i [STAGE_INPUT:STAGE_OUTPUT];
reg [BLOCK_IDX_WIDTH-1:0] stage_j [STAGE_INPUT:STAGE_OUTPUT];
reg signed [0:DELTA_WIDTH*BLOCK_SIZE-1] stage_delta_i [STAGE_INPUT:STAGE_OUTPUT];
reg signed [0:DELTA_WIDTH*BLOCK_SIZE-1] stage_delta_j [STAGE_INPUT:STAGE_OUTPUT];
always @(*) begin
    stage_en[STAGE_INPUT] = en;
    stage_i[STAGE_INPUT] = i;
    stage_j[STAGE_INPUT] = j;
    stage_delta_i[STAGE_INPUT] = delta_i;
    stage_delta_j[STAGE_INPUT] = delta_j;
end
generate
    for (gi = STAGE_INPUT; gi < STAGE_OUTPUT; gi = gi + 1) begin : gen_stage_regs
        always @(posedge clk) begin
            stage_en[gi+1] <= stage_en[gi];
            stage_i[gi+1] <= stage_i[gi];
            stage_j[gi+1] <= stage_j[gi];
            stage_delta_i[gi+1] <= stage_delta_i[gi];
            stage_delta_j[gi+1] <= stage_delta_j[gi];
        end
    end
endgenerate


reg [0:DATA_WIDTH*BLOCK_SIZE-1] L_i_packed; // should arrive at STAGE_ARRIVE
reg [0:DATA_WIDTH*BLOCK_SIZE-1] L_j_packed;

wire signed [DATA_WIDTH-1:0] L_i [0:BLOCK_SIZE-1];
wire signed [DATA_WIDTH-1:0] L_j [0:BLOCK_SIZE-1];
wire signed [DELTA_WIDTH-1:0] delta_L_i [0:BLOCK_SIZE-1];
wire signed [DELTA_WIDTH-1:0] delta_L_j [0:BLOCK_SIZE-1];
wire signed [DATA_WIDTH-1:0] L_i_new [0:BLOCK_SIZE-1];
wire signed [DATA_WIDTH-1:0] L_j_new [0:BLOCK_SIZE-1];
wire [0:DATA_WIDTH*BLOCK_SIZE-1] L_i_packed_new;
wire [0:DATA_WIDTH*BLOCK_SIZE-1] L_j_packed_new;
generate
    for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : gen_next_tmp_j
        assign delta_L_i[gi] = stage_delta_i[STAGE_ARRIVE][gi*DELTA_WIDTH +: DELTA_WIDTH];
        assign delta_L_j[gi] = stage_delta_j[STAGE_ARRIVE][gi*DELTA_WIDTH +: DELTA_WIDTH];

        assign L_i[gi] = L_i_packed[gi*DATA_WIDTH +: DATA_WIDTH];
        assign L_j[gi] = L_j_packed[gi*DATA_WIDTH +: DATA_WIDTH];

        wire is_first_col = (stage_j[STAGE_ARRIVE] == 0);
        wire is_diagonal = (stage_i[STAGE_ARRIVE] == stage_j[STAGE_ARRIVE]);
        assign L_i_new[gi] = stage_en[STAGE_ARRIVE] ? $signed(is_first_col ? delta_L_i[gi] : L_i[gi] + delta_L_i[gi]) : {DATA_WIDTH{1'b0}};
        assign L_j_new[gi] = stage_en[STAGE_ARRIVE] ? $signed(is_diagonal ? L_i_new[gi] : L_j[gi] + delta_L_j[gi]) : {DATA_WIDTH{1'b0}};
        assign L_i_packed_new[gi*DATA_WIDTH +: DATA_WIDTH] = L_i_new[gi];
        assign L_j_packed_new[gi*DATA_WIDTH +: DATA_WIDTH] = L_j_new[gi];
    end
endgenerate

// lutram for L_i
wire [0:DATA_WIDTH*BLOCK_SIZE-1] L_i_packed_out;
if (STAGE_WRITE == STAGE_LOAD) begin
    lutram_gen #(
        .WIDTH          (BLOCK_SIZE * DATA_WIDTH),
        .DEPTH          (N_BLOCK_PER_ROW),
        .ADDR_WIDTH     (BLOCK_IDX_WIDTH)
    ) lutram_gen_i (
        .clk            (clk),
        .addr           (stage_i[STAGE_WRITE]),
        .din            (L_i_packed_new),
        .dout           (L_i_packed_out),
        .we             (stage_en[STAGE_WRITE])
    );
    always @(*) L_i_packed = L_i_packed_out;
end else begin
    dual_lutram_gen #(
        .WIDTH              (BLOCK_SIZE * DATA_WIDTH),
        .DEPTH              (N_BLOCK_PER_ROW),
        .ADDR_WIDTH         (BLOCK_IDX_WIDTH)
    ) dual_lutram_gen_i (
        .clk            (clk),
        .addra          (stage_i[STAGE_WRITE]),
        .addrb          (stage_i[STAGE_LOAD]),
        .dina           (L_i_packed_new),
        .doutb          (L_i_packed_out),
        .wea            (stage_en[STAGE_WRITE])
    );
    if (!ENABLE_STOREREG) $error("L_mem: ENABLE_STOREREG must be 1 when using dual_lutram_gen.");

    always @(posedge clk) begin
        if (stage_i[STAGE_WRITE] == N_BLOCK_PER_ROW - 1 && 
            stage_j[STAGE_WRITE] == N_BLOCK_PER_ROW - 2)
            L_i_packed <= L_i_packed_new;
        else
            L_i_packed <= L_i_packed_out;
    end
end

// reg for L_j
always @(posedge clk) L_j_packed <= L_j_packed_new;


// output register
if (ENABLE_OUTREG) 
    always @(posedge clk) begin
        dout_i <= L_i_packed_new;
        dout_j <= L_j_packed_new;
    end
else 
    always @(*) begin
        dout_i = L_i_packed_new;
        dout_j = L_j_packed_new;
    end

endmodule