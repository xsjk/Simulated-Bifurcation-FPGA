`timescale 1ns / 1ps

module matmul #(
    parameter N = 80,
    parameter M = 80,
    parameter CHUNK = 1,
    parameter WIDTH = $clog2(M+1)+1,   // WIDTH of signed out
    parameter ENABLE_DOTREG = 0,
    parameter ENABLE_LOCALREG = 0,
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

localparam CHUNK_SIZE = (M-1) / CHUNK + 1;
localparam CHUNK_WIDTH = $clog2(CHUNK_SIZE+1) + 1; // s_local [-CHUNK_SIZE, CHUNK_SIZE]
reg signed [CHUNK_WIDTH-1:0] s_local [0:N-1][0:CHUNK-1];
reg signed [CHUNK_WIDTH-1:0] s_local_reg [0:N-1][0:CHUNK-1];

// New arrays for dot product calculation
reg signed [1:0] dot_products [0:N-1][0:M-1];
reg signed [1:0] dot_products_reg [0:N-1][0:M-1];

// Calculate all dot products
always @(*) for (i=0; i<N; i=i+1) for (j=0; j<M; j=j+1) dot_products[i][j] = $signed({(J[i*M+j]^x[j*2])&x[j*2+1], x[j*2+1]});

if (ENABLE_DOTREG) always @(posedge clk) for (i=0; i<N; i=i+1) for (j=0; j<M; j=j+1) dot_products_reg[i][j] <= dot_products[i][j];
else always @(*) for (i=0; i<N; i=i+1) for (j=0; j<M; j=j+1) dot_products_reg[i][j] = dot_products[i][j];

// Calculate local sums
always @(*)
    for (i=0; i<N; i=i+1) begin 
        for (k=0; k<CHUNK; k=k+1) 
            s_local[i][k] = 0;
        for (j=0; j<M; j=j+1) 
            s_local[i][j/CHUNK_SIZE] = s_local[i][j/CHUNK_SIZE] + dot_products_reg[i][j];
        // Remove diagonal element if needed
        if (is_diagonal) 
            s_local[i][i/CHUNK_SIZE] = s_local[i][i/CHUNK_SIZE] - dot_products_reg[i][i];
    end

if (ENABLE_LOCALREG) always @(posedge clk) for (i=0; i<N; i=i+1) for (k=0; k<CHUNK; k=k+1) s_local_reg[i][k] <= s_local[i][k];
else always @(*) for (i=0; i<N; i=i+1) for (k=0; k<CHUNK; k=k+1) s_local_reg[i][k] = s_local[i][k];

// Calculate final sums
always @(*) begin
    for (i=0; i<N; i=i+1) begin
        s[i] = 0;
        for (k=0; k<CHUNK; k=k+1)
            s[i] = s[i] + s_local_reg[i][k];
    end
end

if (ENABLE_OUTREG) always @(posedge clk) for (i=0; i<N; i=i+1) out[i*WIDTH +: WIDTH] <= s[i];
else always @(*) for (i=0; i<N; i=i+1) out[i*WIDTH +: WIDTH] = s[i];


endmodule
