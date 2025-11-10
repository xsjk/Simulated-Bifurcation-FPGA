import os
from math import ceil

from data import J, N
from utils import pm1_to_bits

assert J.shape == (N, N)

BLOCK_SIZE = 80
assert N % BLOCK_SIZE == 0

BRAM_UNIT_PORT_WIDTH = 36  # This is the maximum port width of a RAMB36E1
BRAM_UNIT_DEPTH = 1024  # The depth of BRAM unit is 1024 when width is 36

BLOCK_DATA_WIDTH = BLOCK_SIZE * BLOCK_SIZE
N_BLOCK_PER_ROW = N // BLOCK_SIZE
BLOCK_COUNT = (N_BLOCK_PER_ROW * (N_BLOCK_PER_ROW + 1)) // 2

BRAM_UNIT_COUNT = ceil(BLOCK_DATA_WIDTH / (BRAM_UNIT_PORT_WIDTH * 2))  # 2 for dual port
BRAM_PORT_WIDTH = BRAM_UNIT_COUNT * BRAM_UNIT_PORT_WIDTH
BRAM_BANDWIDTH = BRAM_PORT_WIDTH * 2

assert BLOCK_DATA_WIDTH <= BRAM_BANDWIDTH
assert BLOCK_COUNT <= BRAM_UNIT_DEPTH

suggested_width = BRAM_PORT_WIDTH
suggested_depth = BRAM_UNIT_DEPTH
print(f"J_bram settings -> DATA_WIDTH: {suggested_width}, DEPTH: {suggested_depth} (uses {BRAM_UNIT_COUNT} x {BRAM_UNIT_PORT_WIDTH}-bit BRAM units, total bandwidth {BRAM_BANDWIDTH} bits / cycle for dual port)")


output_path = os.path.join(os.path.dirname(__file__), "..", "srcs", "sources_1", "coe", "k2000.coe")

# Now generate the .coe
with open(output_path, "w") as f:
    f.write("memory_initialization_radix=2;\n")
    f.write("memory_initialization_vector=\n")
    for j in range(N_BLOCK_PER_ROW):
        for i in range(j, N_BLOCK_PER_ROW):
            block = J[i * BLOCK_SIZE : (i + 1) * BLOCK_SIZE, j * BLOCK_SIZE : (j + 1) * BLOCK_SIZE]
            block_bits = pm1_to_bits(block.ravel())
            block_bits = block_bits.ljust(BRAM_BANDWIDTH, "0")
            # Write two lines for each block (for dual port)
            f.write(block_bits[:BRAM_PORT_WIDTH] + ",\n")
            f.write(block_bits[BRAM_PORT_WIDTH:] + ",\n")

print(f"Wrote to {output_path}")
