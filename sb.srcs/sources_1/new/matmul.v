`timescale 1ns / 1ps

module matmul #(
    parameter N = 80,
    parameter M = 80,
    parameter LEVEL1_GROUPS = 1,      // Number of groups in first level of addition tree
    parameter LEVEL2_GROUPS = 1,      // Number of groups in second level of addition tree
    parameter WIDTH = $clog2(M+1)+1,   // WIDTH of signed out
    parameter ENABLE_PRODREG = 0,
    parameter ENABLE_LEVEL1REG = 0,   // Enable first level register
    parameter ENABLE_LEVEL2REG = 0,   // Enable second level register
    parameter ENABLE_OUTREG = 0
)
// Calculate (N, M) * (M,) -> (N,) every clock cycle
(
    input wire clk,
    input wire [0:M*2-1] x,   
    input wire [0:N*M*1-1] J,
    input wire is_diagonal, // if J is diagonal, then take J[i*M+j] = 0 for i != j
    output reg [0:N*WIDTH-1] out 
);

integer i;
integer j;
integer k;

reg signed [WIDTH-1:0] s [0:N-1];

localparam LEVEL0_GROUPS = M;
localparam LEVEL0_MAX = 1;

localparam LEVEL0_PER_LEVEL1 = (LEVEL0_GROUPS-1) / LEVEL1_GROUPS + 1; // Elements per LEVEL1 group
localparam LEVEL1_MAX = LEVEL0_PER_LEVEL1*LEVEL0_MAX;
localparam LEVEL1_WIDTH = $clog2(LEVEL1_MAX+1) + 1; // s_level1 [-LEVEL1_MAX, LEVEL1_MAX]
reg signed [LEVEL1_WIDTH-1:0] s_level1 [0:N-1][0:LEVEL1_GROUPS-1];
reg signed [LEVEL1_WIDTH-1:0] s_level1_reg [0:N-1][0:LEVEL1_GROUPS-1];

localparam LEVEL1_PER_LEVEL2 = (LEVEL1_GROUPS-1) / LEVEL2_GROUPS + 1;  // Elements per LEVEL2 group
localparam LEVEL2_MAX = LEVEL1_PER_LEVEL2*LEVEL1_MAX;
localparam LEVEL2_WIDTH = $clog2(LEVEL2_MAX+1) + 1; // s_level2 [-LEVEL1_PER_LEVEL2, LEVEL1_PER_LEVEL2]
reg signed [LEVEL2_WIDTH-1:0] s_level2 [0:N-1][0:LEVEL2_GROUPS-1];
reg signed [LEVEL2_WIDTH-1:0] s_level2_reg [0:N-1][0:LEVEL2_GROUPS-1];

reg signed [1:0] p [0:N-1][0:M-1];
reg signed [1:0] p_reg [0:N-1][0:M-1];
reg is_diagonal_reg;

// Calculate Level 0: dot products
always @(*) 
    for (i=0; i<N; i=i+1) 
        for (j=0; j<M; j=j+1) 
            p[i][j] = $signed({(J[i*M+j]^x[j*2])&x[j*2+1], x[j*2+1]});
if (ENABLE_PRODREG) 
    always @(posedge clk) begin
        is_diagonal_reg <= is_diagonal;
        for (i=0; i<N; i=i+1) for (j=0; j<M; j=j+1) p_reg[i][j] <= p[i][j];
    end
else 
    always @(*) begin
        is_diagonal_reg = is_diagonal;
        for (i=0; i<N; i=i+1) for (j=0; j<M; j=j+1) p_reg[i][j] = p[i][j];
    end

// Calculate Level 1: sum of dot products
always @(*)
    for (i=0; i<N; i=i+1) begin 
        for (k=0; k<LEVEL1_GROUPS; k=k+1) 
            s_level1[i][k] = 0;
        for (j=0; j<LEVEL0_GROUPS; j=j+1) 
            s_level1[i][j/LEVEL0_PER_LEVEL1] = s_level1[i][j/LEVEL0_PER_LEVEL1] + p_reg[i][j];
        // Remove diagonal element if needed
        if (is_diagonal_reg) 
            s_level1[i][i/LEVEL0_PER_LEVEL1] = s_level1[i][i/LEVEL0_PER_LEVEL1] - p_reg[i][i];
    end
if (ENABLE_LEVEL1REG) always @(posedge clk) for (i=0; i<N; i=i+1) for (k=0; k<LEVEL1_GROUPS; k=k+1) s_level1_reg[i][k] <= s_level1[i][k];
else always @(*) for (i=0; i<N; i=i+1) for (k=0; k<LEVEL1_GROUPS; k=k+1) s_level1_reg[i][k] = s_level1[i][k];

// Calculate Level 2: sum of s_level1
always @(*) begin
    for (i=0; i<N; i=i+1) begin
        for (k=0; k<LEVEL2_GROUPS; k=k+1)
            s_level2[i][k] = 0;
        for (j=0; j<LEVEL1_GROUPS; j=j+1)
            s_level2[i][j/LEVEL1_PER_LEVEL2] = s_level2[i][j/LEVEL1_PER_LEVEL2] + s_level1_reg[i][j];
    end
end
if (ENABLE_LEVEL2REG) always @(posedge clk) for (i=0; i<N; i=i+1) for (k=0; k<LEVEL2_GROUPS; k=k+1) s_level2_reg[i][k] <= s_level2[i][k];
else always @(*) for (i=0; i<N; i=i+1) for (k=0; k<LEVEL2_GROUPS; k=k+1) s_level2_reg[i][k] = s_level2[i][k];

// Calculate final output: sum of s_level2
always @(*) begin
    for (i=0; i<N; i=i+1) begin
        s[i] = 0;
        for (k=0; k<LEVEL2_GROUPS; k=k+1)
            s[i] = s[i] + s_level2_reg[i][k];
    end
end
if (ENABLE_OUTREG) always @(posedge clk) for (i=0; i<N; i=i+1) out[i*WIDTH +: WIDTH] <= s[i];
else always @(*) for (i=0; i<N; i=i+1) out[i*WIDTH +: WIDTH] = s[i];


endmodule
