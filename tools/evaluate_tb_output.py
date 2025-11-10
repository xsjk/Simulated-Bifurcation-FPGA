import sys

from data import J, N
from utils import bits_to_pm1, evaluate_cut


def get_cut_value_from_tb_output(output: str) -> int:
    """
    Parse the output of tb_block_sSB.v to get the cut value of the simulation.
    """
    bits_str = "".join(line.split()[-1][::-1] for line in output.strip().split("\n")[1:])
    x = bits_to_pm1(bits_str[:N])
    return evaluate_cut(x, J)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python check_tb_output.py <sim_debug_output_file>")
        sys.exit(1)

    with open(sys.argv[1], "r") as f:
        print(get_cut_value_from_tb_output(f.read()))
