`timescale 1ns / 1ps

module tb_to_flat_index #(
    parameter N = 25, // 25x25 matrix
    parameter WIDTH = $clog2(N)
);

reg [WIDTH-1:0] block_idx_i;
reg [WIDTH-1:0] block_idx_j;
wire [WIDTH*2-1:0] block_idx_flat;

to_flat_index #(
    .N  (N)
) to_flat_index_i (
    .i  (block_idx_i),
    .j  (block_idx_j),
    .o  (block_idx_flat)
);


integer i, j;

initial begin
    for (i = 0; i < N; i = i + 1) begin
        for (j = 0; j < N; j = j + 1) begin
            block_idx_i = i;
            block_idx_j = j;
            #1
            $write("%d", block_idx_flat);
        end
        $write("\n");
    end

end



endmodule
