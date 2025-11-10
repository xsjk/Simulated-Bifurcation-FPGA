import sys

from data import J, N
from utils import bits_to_pm1, evaluate_cut


def get_cut_value_from_debug_bram(mem: str) -> int:
    """
    Parse the multiline memory dump from Vitis debugger memory viewer
        ADDRESS: 0x40000000
        OFFSET: 0
        LENGTH: 256
        BYTE_SIZE: 8
        BYTES_PER_GROUP: 4
        GROUPS_PER_ROW: 4
        ENDIANNESS: little
    """
    mem = "".join(line.split()[-1] for line in mem.strip().split("\n"))
    bits_str = "".join(f"{int(mem[i : i + 8], 16):032b}"[::-1] for i in range(0, len(mem), 8))
    x = bits_to_pm1(bits_str[:N])
    return evaluate_cut(x, J)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python check_bram_data.py <debug_mem_file>")
        sys.exit(1)

    with open(sys.argv[1], "r") as f:
        print(get_cut_value_from_debug_bram(f.read()))
