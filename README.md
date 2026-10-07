# Multi-Channel Timer/Counter Subsystem

A parameterized, synthesizable multi-channel timer/counter IP core designed for SoC peripheral integration. Built with SystemVerilog, targeting both FPGA and ASIC implementations.

## Features

- **4 independent timer channels** (parameterizable)
- **32-bit counters** (parameterizable width)
- **Multiple count modes**: Up, Down, Up/Down (center-aligned)
- **Prescaled clock** with configurable divider
- **Compare match** with interrupt generation
- **PWM output** (edge-aligned and center-aligned)
- **Input capture** with edge detection and debounce filtering
- **Channel cascading** for multi-stage timers
- **APB slave interface** for register access
- **Interrupt controller** with per-channel enable/mask
- **Protocol/behavior invariant monitor** exercised in CI
- **Yosys/OpenROAD synthesis** support

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     timer_top                           │
│                                                         │
│  ┌──────────┐   ┌──────────────────────────────────┐   │
│  │  APB     │   │         Register Block            │   │
│  │  Slave   │◄─►│  (per-channel config/status)      │   │
│  │  IF      │   └──────────────┬───────────────────┘   │
│  └──────────┘                  │                        │
│                                ▼                        │
│  ┌──────────┐   ┌──────────────────────────────────┐   │
│  │Prescaler │──►│      Timer Channels (×N)          │   │
│  │          │   │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ │   │
│  └──────────┘   │  │ CH0 │─│ CH1 │─│ CH2 │─│ CH3 │ │   │
│                 │  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ │   │
│                 │     │       │       │       │     │   │
│                 │  ┌──▼──┐ ┌──▼──┐ ┌──▼──┐ ┌──▼──┐ │   │
│                 │  │ PWM │ │ PWM │ │ PWM │ │ PWM │ │   │
│                 │  └─────┘ └─────┘ └─────┘ └─────┘ │   │
│                 └──────────────────────────────────┘   │
│                                │                        │
│                 ┌──────────────▼───────────────────┐   │
│                 │       Interrupt Controller        │   │
│                 │  (per-channel enable + global)    │   │
│                 └──────────────────────────────────┘   │
│                                │                        │
│                                ▼                        │
│                           [ IRQ out ]                   │
└─────────────────────────────────────────────────────────┘
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed Mermaid diagrams.

## Quick Start

### Prerequisites

- [Icarus Verilog](https://iverilog.icarus.com/) (simulation)
- [Yosys](http://www.clifford.at/yosys/) (synthesis)
- [Python 3.8+](https://www.python.org/) (golden model)

### Run All Tests

```bash
make test          # Python model + RTL simulation
make test_all      # Full suite including assertions + synthesis
make test_python   # Python golden model only (works without iverilog)
```

### Individual Targets

```bash
make sim           # RTL simulation only
make sim_assert    # Simulation with assertion/invariant monitor
make test_python   # Python golden model only
make yosys         # Yosys synthesis
make help          # Show all targets
```

## Parameterization

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_CHANNELS` | 4 | Number of timer channels |
| `WIDTH` | 32 | Counter/comparator width (bits) |
| `APB_ADDR_W` | 12 | APB address width |
| `DEBOUNCE_DEPTH` | 4 | Input capture debounce filter depth |

Override via Makefile:
```bash
make sim NUM_CHANNELS=8 WIDTH=64
```

## Register Map

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| `0x00` | CTRL | R/W | Count mode: 0=stop, 1=up, 2=down, 3=up/down |
| `0x04` | STATUS | R | Sticky event bits: match/overflow/underflow/capture |
| `0x08` | CNT | R/W | Current count / software preload |
| `0x0C` | RELOAD | R/W | Value loaded on overflow/underflow |
| `0x10` | COMPARE | R/W | Compare match value |
| `0x14` | PWM_CMP | R/W | PWM duty compare |
| `0x18` | CAPTURE | R | Captured counter value |
| `0x1C` | EDGE | R/W | Edge select/debounce config |
| `0x20` | INT_EN | R/W | bit0 interrupt enable, bit1 cascade enable |
| `0x24` | INT_CLR | W | Clear interrupt (W1C) |
| `0x400` | GLOBAL_CTRL | R/W | Global enable + prescaler |
| `0x404` | GLOBAL_IRQ | R | Global interrupt status |
| `0x408` | VERSION | R | IP version (0x00010001) |

Per-channel base: `channel_id × 0x40`

## Project Structure

```
.
├── rtl/                        # RTL source files
│   ├── prescaler.sv
│   ├── counter.sv
│   ├── compare_unit.sv
│   ├── pwm_generator.sv
│   ├── input_capture.sv
│   ├── cascade_unit.sv
│   ├── register_block.sv
│   ├── interrupt_controller.sv
│   └── timer_top.sv
├── tb/                         # Testbench
│   ├── timer_tb.sv
│   ├── agents/apb_bfm.sv
│   └── assertions/timer_assertions.sv
├── python/                     # Golden reference model
│   └── timer_golden_model.py
├── synth/                      # Synthesis scripts
│   ├── synth_yosys.ys
│   ├── timer_top.sdc
│   └── openroad/floorplan.tcl
├── docs/                       # Documentation
│   ├── DESIGN_SPEC.md
│   ├── VERIFICATION_PLAN.md
│   ├── ARCHITECTURE.md
│   └── PERFORMANCE_ANALYSIS.md
├── .github/workflows/ci.yml
├── Makefile
├── LICENSE
└── README.md
```

## Verification

The project includes a comprehensive verification environment:

- **Self-checking RTL integration regression** with 22 semantic checks
- **Assertion/invariant monitor** for APB sequencing, terminal-count events, and IRQ consistency
- **Python golden model** with 10 executable pytest tests
- **Verilator lint** and **Yosys synthesis** gates in CI

See [docs/VERIFICATION_PLAN.md](docs/VERIFICATION_PLAN.md) for the full verification plan.

## Synthesis

### Yosys (Open-Source)

```bash
make yosys
```

Generates gate-level netlist in `synth/output/`.

### ASIC Flow (OpenROAD)

Requires a PDK (e.g., SkyWater SKY130):

```bash
make openroad
```

See [docs/PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md) for area/timing analysis guidelines.

## Verified CI Baseline

GitHub Actions run **37690557357** completed successfully on the repaired RTL baseline.

| Gate | Result |
|------|--------|
| Python golden-model pytest | PASS |
| RTL simulation (Icarus Verilog) | PASS — 22 checks, 0 errors |
| Assertion/invariant monitor | PASS |
| Verilator lint | PASS |
| Yosys synthesis | PASS |
| Documentation check | PASS |

The verified RTL regression covers mode readback, CNT preload, RELOAD independence, up/down/up-down operation, overflow reload, sticky status/W1C, compare IRQ, cascade-only counting, input capture, PWM level behavior, and prescaler division.

## License

MIT License - see [LICENSE](LICENSE)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run `make test_all` to verify
4. Submit a pull request

## Author

Digital Design Portfolio - ASIC/FPGA Design

---

*Built for semiconductor job applications. Demonstrates RTL design, verification, and synthesis methodology.*
