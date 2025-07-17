`timescale 1ns / 1ps

module matmul #(
    parameter N = 80,
    parameter M = 80,
    parameter CHUNK = 1,
    parameter WIDTH = $clog2(M+1)+1   // WIDTH of signed out
)
// Calculate (N, M) * (M,) -> (N,) every clock cycle
(
    input wire [0:M*2-1] x,   
    input wire [0:N*M*1-1] J,
    input wire is_diagonal, // if J is diagonal, then J[i*M+j] = 0 for i != j
    output wire [0:N*WIDTH-1] out 
);

integer i;
integer j;
integer k;

reg signed [WIDTH-1:0] s [0:N-1];

localparam CHUNK_SIZE = (M-1) / CHUNK + 1;
localparam CHUNK_WIDTH = $clog2(CHUNK_SIZE+1) + 1; // s_local [-CHUNK_SIZE, CHUNK_SIZE]
reg signed [CHUNK_WIDTH-1:0] s_local [0:CHUNK-1];

// Combinational logic
always @(*) begin
    for (i=0; i<N; i=i+1) begin 
        s[i] = 0;
        for (k=0; k<CHUNK; k=k+1) 
            s_local[k] = 0;
        for (j=0; j<M; j=j+1)
            s_local[j/CHUNK_SIZE] = s_local[j/CHUNK_SIZE] + $signed({(J[i*M+j]^x[j*2])&x[j*2+1], x[j*2+1]});

        // Remove diagonal element if needed
        if (is_diagonal) begin
            s_local[i/CHUNK_SIZE] = s_local[i/CHUNK_SIZE] - $signed({(J[i*M+i]^x[i*2])&x[i*2+1], x[i*2+1]});
        end
        
        for (k=0; k<CHUNK; k=k+1)
            s[i] = s[i] + s_local[k];
    end
end

// Assign output directly from combinational logic
genvar gi;
generate
    for (gi=0; gi<N; gi=gi+1) begin : gen_out
        assign out[gi*WIDTH +: WIDTH] = s[gi];
    end
endgenerate

endmodule
