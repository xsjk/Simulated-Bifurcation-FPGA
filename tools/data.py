import os
from urllib.request import urlopen

import numpy as np


N = 2000

if not os.path.exists(f"k{N}.npy"):
    url = f"https://media.githubusercontent.com/media/xsjk/Simulated-Bifurcation/refs/heads/main/data/k{N}.npy"
    with open(f"k{N}.npy", "wb") as f, urlopen(url) as resp:
        f.write(resp.read())

J = -np.load(f"k{N}.npy")
assert J.shape == (N, N)
