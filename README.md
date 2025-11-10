## Simulated Bifurcation FPGA

FPGA accelerator for *Conflict-Free Block Pipelining for FPGA-Accelerated Stochastic Simulated Bifurcation on Dense Ising Models*. Solves fully connected 2000×2000 Max-Cut instances in ~1.1 ms on ZedBoard (Zynq-7000) at 71 MHz.

### Quick Start

**Reproduce hardware results:**  
→ [Hardware Bringup Guide](https://github.com/xsjk/Simulated-Bifurcation-FPGA/wiki/Hardware-Bringup-Guide)

**Develop and extend:**  
→ [Wiki](https://github.com/xsjk/Simulated-Bifurcation-FPGA/wiki)

### Repository Structure
```
srcs/       RTL, constraints, testbenches
xpr/        Vivado project template
scripts/    Makefile automation (setup, git hooks)
tools/      Python verification utilities
```

### Key Features
- Pure PL implementation; PS optional (AXI BRAM at `0x40000000` for result readback)
- Git-friendly: `make build` regenerates projects from version-controlled sources
- Portable: retargetable to any Vivado-supported FPGA
- Tested: Ubuntu 22.04, Vivado/Vitis 2024.2

For architecture details, power considerations, and development workflows, see the [Wiki](https://github.com/xsjk/Simulated-Bifurcation-FPGA/wiki).
