import numpy as np


def pm1_to_bits(arr: np.ndarray) -> str:
    return "".join("0" if x > 0 else "1" for x in arr)


def clog2(x: float) -> int:
    from math import ceil, log2

    return ceil(log2(x))


def evaluate_cut(x: np.ndarray, J: np.ndarray) -> int:
    x = x.astype(np.int32)  # Ensure no overflow during x @ J @ x
    return int(((-J.sum() + x @ J @ x) // 4))


def bits_to_pm1(x) -> np.ndarray:
    if not isinstance(x, np.ndarray):
        x = np.fromiter(x, dtype=np.int8)
    return 1 - 2 * x.astype(np.int8)
