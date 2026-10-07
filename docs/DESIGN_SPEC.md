# Design Specification - Multi-Channel Timer/Counter Subsystem

**Version:** 1.0.1
**Date:** October 2026
**Status:** RTL verified in CI

---

## 1. Overview

The Timer/Counter Subsystem is a parameterized, memory-mapped peripheral IP designed for SoC integration. It provides multiple independent timer channels with compare matching, PWM output, input capture, and interrupt generation capabilities.

## 2. Design Goals

| Goal | Metric |
|------|--------|
| Parameterization | Channels (1-16), Width (8-64 bits) |
| Clock frequency target | 100 MHz (10ns period) |
| Interface | APB3-compatible |
| Verification | Directed semantic regression + golden model + invariant monitor |
| Synthesis targets | Yosys, Design Compiler, Genus |

## 3. Architecture

### 3.1 Module Hierarchy

```
timer_top (top)
├── prescaler                    # Clock divider
├── gen_channels [NUM_CHANNELS]  # Per-channel instances
│   ├── counter                  # Up/down/up-down counter
│   ├── cascade_unit             # Channel chaining logic
│   ├── compare_unit             # Match detection
│   ├── pwm_generator            # PWM output
│   └── input_capture            # External capture
├── interrupt_controller         # IRQ generation/masking
└── register_block               # APB register interface
```

### 3.2 Interface Definition

#### APB Slave Port

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `paddr` | Input | 12 | Address bus |
| `psel` | Input | 1 | Peripheral select |
| `penable` | Input | 1 | Access phase enable |
| `pwrite` | Input | 1 | Write enable |
| `pwdata` | Input | 32 | Write data |
| `prdata` | Output | 32 | Read data |
| `pready` | Output | 1 | Ready (always 1) |
| `pslverr` | Output | 1 | Slave error (always 0) |

#### Timer Ports

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `capture_in` | Input | N | External capture inputs |
| `pwm_out` | Output | N | PWM outputs |
| `irq` | Output | 1 | Interrupt output |

## 4. Functional Specification

### 4.1 Count Modes

| Mode | Value | Behavior |
|------|-------|----------|
| Stop | 0 | Counter frozen |
| Up | 1 | Increment, overflow → reload |
| Down | 2 | Decrement, underflow → reload |
| Up/Down | 3 | Count up to max, then down to 0, repeat |

### 4.2 Prescaler

- Configurable 16-bit divisor register
- Encoded divisor `N` produces one tick every `N+1` input clocks (`0` = divide-by-1)
- Prescaler freezes when global_enable = 0

### 4.3 Compare Match

- 32-bit compare register per channel
- Match event when counter == compare value
- Match generates interrupt if enabled

### 4.4 PWM Generation

- Edge-aligned: output HIGH when count < compare
- Center-aligned: same comparison, but counter counts up/down
- Independent compare register for duty cycle
- Independent reload register for period

### 4.5 Input Capture

- Captures counter value on external signal edge
- Configurable edge selection (rising/falling/both/none)
- Optional debounce filter (shift register based)
- Generates capture event interrupt

### 4.6 Channel Cascade

- Overflow/underflow of channel N drives count-enable of channel N+1
- Creates wider effective counter (e.g., 2×32-bit = 64-bit)
- Destination channel must have `cascade_en` set; while cascaded, it advances only on the previous channel event and does not also consume local prescaler ticks

### 4.7 Interrupt Controller

- Per-channel interrupt sources: overflow, underflow, match, capture
- Per-channel interrupt enable mask
- Write-1-to-clear for interrupt status
- Global IRQ = OR of all pending interrupts

## 5. Register Map

See README.md for register map. Key design decisions:

- **Sticky STATUS** records match/overflow/underflow/capture events
- **Write-1-to-clear** clears pending interrupt and sticky STATUS
- **CNT readable/writable** for software preloading; **RELOAD** is independent and is applied only on overflow/underflow
- **Global prescaler** shared across all channels
- **Version register** for IP identification and versioning

## 6. Design Constraints

### 6.1 Timing

- Target Fmax: 100 MHz
- Max input delay: 2.0 ns
- Max output delay: 2.0 ns
- Clock uncertainty: 0.5 ns

### 6.2 Area (Expected)

- ~2,000-3,000 gate equivalents for 4-channel, 32-bit config
- Scales linearly with NUM_CHANNELS

### 6.3 Power

- Clock gating via prescaler (no count = no toggle in counter logic)
- Individual channel enable/disable
- PWM output can be disabled per channel

## 7. Verification Approach

- Self-checking testbench with directed tests
- Portable assertion/invariant monitor for APB and behavioral checks
- Python golden model for cross-validation
- Corner case tests (max values, overflow, cascade timing)
- Verilator lint and Yosys synthesis in CI

## 8. Synthesis Support

- **Yosys**: Open-source synthesis with full RTL
- **OpenROAD**: Physical design flow (requires PDK)
- **SDC constraints**: Provided for timing closure
- **ASIC-ready**: No FPGA-specific primitives

## 9. Future Enhancements

- [ ] DMA interface for bulk register access
- [ ] Capture FIFO for high-speed capture
- [ ] Real-time clock (RTC) mode
- [ ] Watchdog timer functionality
- [ ] AHB-Lite interface option
