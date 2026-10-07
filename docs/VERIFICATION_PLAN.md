# Verification Plan - Multi-Channel Timer/Counter Subsystem

**Version:** 1.0.1
**Date:** October 2026

---

## 1. Verification Objectives

| Objective | Metric | Target |
|-----------|--------|--------|
| Functional correctness | All test cases pass | 100% |
| Protocol compliance | APB assertions pass | 0 violations |
| Corner case coverage | Edge cases tested | >90% |
| Code coverage | Line/branch/toggle | >85% |
| Assertion coverage | All assertions checked | 100% |

## 2. Verification Strategy

### 2.1 Levels of Verification

```
┌─────────────────────────────────────────┐
│     System-Level (Integration)          │  ← Timer top + APB BFM
├─────────────────────────────────────────┤
│     Module-Level (Unit)                 │  ← Individual channel tests
├─────────────────────────────────────────┤
│     Python Golden Model                 │  ← Reference comparison
└─────────────────────────────────────────┘
```

### 2.2 Verification Methods

| Method | Tool | Purpose |
|--------|------|---------|
| Directed tests | Icarus Verilog | Specific scenario validation |
| Invariant monitor | SystemVerilog procedural checks | APB/behavioral checking under Icarus |
| Golden model | Python | Reference comparison |
| CI gates | Verilator + Yosys | Lint and synthesis portability |

## 3. Test Cases

### 3.1 Counter Modes

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-001 | Up-count basic | Count from 0, verify increment | count = N after N ticks |
| TC-002 | Up-count overflow | Count past max value | Reloads to reload_val |
| TC-003 | Down-count basic | Count down from value | count decrements |
| TC-004 | Down-count underflow | Count past zero | Reloads to reload_val |
| TC-005 | Up/down mode | Center-aligned counting | Bounces between 0 and max |
| TC-006 | Stop mode | Counter frozen | count unchanged |
| TC-007 | Mode switching | Change mode mid-operation | Behavior changes immediately |

### 3.2 Prescaler

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-010 | Prescaler divide-by-1 | No division | Full speed |
| TC-011 | Prescaler divide-by-N | Divided clock | Count advances every N ticks |
| TC-012 | Prescaler disable | Global enable = 0 | No counting |
| TC-013 | Prescaler reload | Change divisor mid-operation | New rate takes effect |

### 3.3 Compare Match

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-020 | Match at count = compare | Basic comparison | Match pulse generated |
| TC-021 | Match with different compare values | Various thresholds | Correct match timing |
| TC-022 | Match when disabled | compare_en = 0 | No match |
| TC-023 | Multiple matches | Counter wraps around | Match each time |

### 3.4 PWM

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-030 | PWM 50% duty | compare = period/2 | 50% duty cycle |
| TC-031 | PWM 0% duty | compare = 0 | Output always LOW |
| TC-032 | PWM 100% duty | compare = period | Output always HIGH |
| TC-033 | PWM disable | pwm_en = 0 | Output LOW |
| TC-034 | Center-aligned PWM | Up/down mode | Symmetric waveform |

### 3.5 Input Capture

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-040 | Rising edge capture | capture_in rises | Counter value captured |
| TC-041 | Falling edge capture | capture_in falls | Counter value captured |
| TC-042 | Both-edge capture | Either transition | Counter value captured |
| TC-043 | Capture disabled | edge_sel = 3 | No capture |
| TC-044 | Capture event interrupt | Capture occurs | IRQ fires |

### 3.6 Cascade

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-050 | Basic cascade | CH0 overflow → CH1 | CH1 increments |
| TC-051 | Multi-stage cascade | CH0 → CH1 → CH2 | All chain correctly |
| TC-052 | Cascade disabled | cascade_en = 0 | No propagation |
| TC-053 | Cascade with different widths | Wider counters | Correct combined count |

### 3.7 Interrupts

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-060 | Overflow interrupt | Overflow occurs | IRQ fires |
| TC-061 | Match interrupt | Match occurs | IRQ fires |
| TC-062 | Interrupt enable/disable | int_en = 0 | IRQ suppressed |
| TC-063 | Interrupt clear | Write INT_CLR | Pending cleared |
| TC-064 | Multiple sources | Multiple events | IRQ = OR of all |
| TC-065 | Global IRQ deassert | All cleared | IRQ = 0 |

### 3.8 Corner Cases

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-070 | Counter at max value | count = 0xFFFFFFFF | Overflow + reload |
| TC-071 | Counter at zero | count = 0 (down mode) | Underflow + reload |
| TC-072 | Reload value = 0 | Zero-period | Immediate overflow |
| TC-073 | Reload value = max | Maximum period | Correct full-range count |
| TC-074 | Compare = reload | Match at every overflow | Continuous matching |
| TC-075 | All channels active | 4 channels counting | Independent operation |

### 3.9 APB Protocol

| ID | Test | Description | Expected |
|----|------|-------------|----------|
| TC-080 | Write transaction | Valid APB write | Data written |
| TC-081 | Read transaction | Valid APB read | Data returned |
| TC-082 | Read-only register | Read STATUS/CAPTURE | Returns correct value |
| TC-083 | Write-only register | Read INT_CLR | Returns 0 |
| TC-084 | Address decode | Access each register | Correct decode |

## 4. Invariant Checks

### 4.1 Protocol Checks

| ID | Assertion | Severity |
|----|-----------|----------|
| AS-001 | APB setup→access sequence | Error |
| AS-002 | pready during valid transaction | Error |
| AS-003 | Write data stable in access phase | Error |
| AS-004 | No penable without psel | Error |

### 4.2 Behavioral Checks

| ID | Assertion | Severity |
|----|-----------|----------|
| AS-010 | Overflow at max value | Error |
| AS-011 | Underflow at zero | Error |
| AS-012 | Counter frozen when disabled | Error |
| AS-013 | Match implies enabled | Error |

### 4.3 Current Verified Baseline

GitHub Actions run **37690557357** passed all six CI jobs. The RTL integration regression completed **22 checks with 0 errors**. The Python reference model has **10 pytest tests**. Verilator lint and Yosys synthesis both pass.

## 5. Coverage Goals

### 5.1 Functional Coverage

| Group | Bins | Target |
|-------|------|--------|
| Count modes | {stop, up, down, up_down} | 100% |
| Edge types | {rising, falling, both, disabled} | 100% |
| Interrupt sources | {overflow, underflow, match, capture} | 100% |
| Cascade states | {enabled, disabled} | 100% |

### 5.2 Code Coverage Targets (not yet measured)

| Metric | Target |
|--------|--------|
| Line coverage | >90% |
| Branch coverage | >85% |
| Toggle coverage | >80% |

## 6. Test Environment

### 6.1 Components

```
┌─────────────┐    ┌────────────────┐    ┌─────────────┐
│  APB BFM    │───►│   timer_top    │───►│  Assertions │
│  (Master)   │    │    (DUT)       │    │  (Monitor)  │
└─────────────┘    └────────────────┘    └─────────────┘
       │                                       │
       ▼                                       ▼
  Stimulus                              Passive checks
  Generation                            (always @(posedge clk))
```

### 6.2 Self-Checking Mechanism

- Testbench reads back register values after writes
- Compares against expected values using `check()` task
- Counts pass/fail and reports summary
- The invariant monitor runs concurrently as a passive checker

## 7. Regression

Run full regression with:
```bash
make test_all
```

Required for merge: Python tests, RTL regression, invariant monitor, Verilator lint, Yosys synthesis, and documentation checks all pass.
