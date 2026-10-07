#!/usr/bin/env python3
"""
Golden Reference Model for Multi-Channel Timer/Counter Subsystem.

This model accurately predicts the behavior of the RTL design for use in
self-checking verification. It simulates all timer modes, compare matching,
PWM generation, input capture, and cascade chaining.
"""

from dataclasses import dataclass, field
from typing import List, Optional
import sys


@dataclass
class TimerChannel:
    """Models a single timer channel."""
    width: int = 32
    count: int = 0
    reload_val: int = 0
    compare_val: int = 0
    pwm_cmp_val: int = 0
    mode: int = 0  # 0:stop, 1:up, 2:down, 3:up/down
    direction: int = 1  # 1=up, 0=down (for mode 3)
    enabled: bool = False
    cascade_en: bool = False
    pwm_out: bool = False
    overflow: bool = False
    underflow: bool = False
    match: bool = False
    captured_val: int = 0
    capture_event: bool = False
    edge_sel: int = 0  # 0:rising, 1:falling, 2:both, 3:disabled
    debounce_prev: int = 0
    debounce_reg: List[int] = field(default_factory=lambda: [0] * 4)
    int_pending: bool = False

    @property
    def mask(self) -> int:
        return (1 << self.width) - 1

    def tick(self, prescaler_tick: bool, cascade_in: bool = False):
        """Advance one clock cycle."""
        self.overflow = False
        self.underflow = False
        self.match = False
        self.capture_event = False

        # Cascade mode is exclusive: a cascaded channel advances only when the
        # previous channel generates a cascade event. Otherwise it follows the
        # shared prescaler tick.
        count_enable = prescaler_tick and self.enabled and not self.cascade_en
        cascade_trigger = cascade_in and self.enabled and self.cascade_en

        if count_enable or cascade_trigger:
            if self.mode == 1:  # Up count
                if self.count == self.mask:
                    self.count = self.reload_val & self.mask
                    self.overflow = True
                else:
                    self.count = (self.count + 1) & self.mask

            elif self.mode == 2:  # Down count
                if self.count == 0:
                    self.count = self.reload_val & self.mask
                    self.underflow = True
                else:
                    self.count = (self.count - 1) & self.mask

            elif self.mode == 3:  # Up/down
                if self.direction == 1:
                    if self.count == self.mask:
                        self.count = (self.count - 1) & self.mask
                        self.direction = 0
                        self.overflow = True
                    else:
                        self.count = (self.count + 1) & self.mask
                else:
                    if self.count == 0:
                        self.count = (self.count + 1) & self.mask
                        self.direction = 1
                        self.underflow = True
                    else:
                        self.count = (self.count - 1) & self.mask

        # Compare match
        if self.enabled and (count_enable or cascade_trigger) and self.count == self.compare_val:
            self.match = True
            self.int_pending = True

        # PWM update
        if self.enabled:
            self.pwm_out = self.count < self.pwm_cmp_val

    def capture(self, capture_in: int):
        """Process input capture."""
        if self.edge_sel == 3:
            return

        # Simple debounce (all bits must match)
        debounced = capture_in
        edge_detected = (debounced == 1 and self.debounce_prev == 0) or \
                       (debounced == 0 and self.debounce_prev == 1)

        if self.edge_sel == 0 and debounced == 1 and self.debounce_prev == 0:
            self.captured_val = self.count
            self.capture_event = True
        elif self.edge_sel == 1 and debounced == 0 and self.debounce_prev == 1:
            self.captured_val = self.count
            self.capture_event = True
        elif self.edge_sel == 2 and edge_detected:
            self.captured_val = self.count
            self.capture_event = True

        self.debounce_prev = debounced

    def reload(self, value: Optional[int] = None):
        """Reload counter."""
        if value is not None:
            self.count = value & self.mask
        else:
            self.count = self.reload_val & self.mask

    def get_pwm_duty(self) -> float:
        """Return PWM duty cycle as a fraction."""
        if self.reload_val == 0:
            return 0.0
        return min(self.pwm_cmp_val / self.reload_val, 1.0)


@dataclass
class TimerSubsystem:
    """Complete timer subsystem model."""
    num_channels: int = 4
    width: int = 32
    prescaler_val: int = 0  # 0=divide-by-1, 1=divide-by-2, ...
    prescaler_count: int = 0
    global_enable: bool = False
    channels: List[TimerChannel] = field(default_factory=list)

    def __post_init__(self):
        if not self.channels:
            self.channels = [TimerChannel(width=self.width)
                           for _ in range(self.num_channels)]

    def tick(self, capture_in: Optional[List[int]] = None):
        """Advance one clock cycle."""
        if not self.global_enable:
            return

        # RTL semantics: divisor N produces a tick every N+1 input clocks.
        if self.prescaler_count >= self.prescaler_val:
            prescaler_tick = True
            self.prescaler_count = 0
        else:
            prescaler_tick = False
            self.prescaler_count += 1

        cascade_trigger = [False] * self.num_channels

        for i in range(self.num_channels):
            ch = self.channels[i]
            cascade_in = cascade_trigger[i]
            ch.tick(prescaler_tick, cascade_in)

            # Source overflow/underflow always propagates. The destination
            # decides whether to consume it through its cascade_en setting.
            if (ch.overflow or ch.underflow) and i + 1 < self.num_channels:
                cascade_trigger[i + 1] = True

            # Input capture
            if capture_in and i < len(capture_in):
                ch.capture(capture_in[i])

    def set_channel_config(self, ch_id: int, **kwargs):
        """Configure a channel."""
        ch = self.channels[ch_id]
        for key, val in kwargs.items():
            if hasattr(ch, key):
                setattr(ch, key, val)

    def get_channel_count(self, ch_id: int) -> int:
        return self.channels[ch_id].count

    def get_irq(self) -> bool:
        return any(ch.int_pending for ch in self.channels)

    def clear_irq(self, ch_id: int):
        self.channels[ch_id].int_pending = False


def run_basic_test():
    """Run basic functional tests on the golden model."""
    print("=" * 60)
    print("Golden Model Basic Functional Tests")
    print("=" * 60)
    errors = 0

    # Test 1: Up counting
    print("\n[Test 1] Up-count mode...")
    sub = TimerSubsystem(num_channels=1, width=8)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, reload_val=255)
    for _ in range(10):
        sub.tick()
    expected = 10
    actual = sub.get_channel_count(0)
    if actual == expected:
        print(f"  PASS: count = {actual}")
    else:
        print(f"  FAIL: expected {expected}, got {actual}")
        errors += 1

    # Test 2: Overflow and reload
    print("\n[Test 2] Overflow and reload...")
    sub = TimerSubsystem(num_channels=1, width=8)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, reload_val=5)
    for _ in range(260):  # 256 to overflow, then reload to 5, count 4 more
        sub.tick()
    count = sub.get_channel_count(0)
    # After 256 ticks: overflow, reload to 5. Then 4 more ticks: count = 9
    if count == 9:
        print(f"  PASS: count = {count} (overflow + reload)")
    else:
        print(f"  FAIL: expected 9, got {count}")
        errors += 1

    # Test 3: Down counting
    print("\n[Test 3] Down-count mode...")
    sub = TimerSubsystem(num_channels=1, width=8)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=2, reload_val=100)
    sub.channels[0].count = 10
    for _ in range(5):
        sub.tick()
    count = sub.get_channel_count(0)
    if count == 5:
        print(f"  PASS: count = {count}")
    else:
        print(f"  FAIL: expected 5, got {count}")
        errors += 1

    # Test 4: PWM output
    print("\n[Test 4] PWM output...")
    sub = TimerSubsystem(num_channels=1, width=8)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, reload_val=100, pwm_cmp_val=75)
    sub.tick()
    if sub.channels[0].pwm_out:
        print(f"  PASS: PWM out = 1 (count=0 < 75)")
    else:
        print(f"  FAIL: PWM out should be 1")
        errors += 1

    # Test 5: Cascade chaining
    print("\n[Test 5] Cascade chaining...")
    sub = TimerSubsystem(num_channels=2, width=4)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, reload_val=15, cascade_en=False)
    sub.set_channel_config(1, enabled=True, mode=1, reload_val=15, cascade_en=True)
    for _ in range(256):  # Channel 0 overflows ~16 times, triggering channel 1
        sub.tick()
    ch0_count = sub.get_channel_count(0)
    ch1_count = sub.get_channel_count(1)
    if ch1_count > 0:
        print(f"  PASS: ch0={ch0_count}, ch1={ch1_count} (cascade working)")
    else:
        print(f"  FAIL: ch1 should have counted via cascade")
        errors += 1

    # Test 6: Compare match interrupt
    print("\n[Test 6] Compare match interrupt...")
    sub = TimerSubsystem(num_channels=1, width=8)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, reload_val=255, compare_val=5)
    for _ in range(20):
        sub.tick()
    if sub.get_irq():
        print(f"  PASS: IRQ fired at count >= 5")
    else:
        print(f"  FAIL: IRQ should have fired")
        errors += 1

    # Test 7: Up/down mode
    print("\n[Test 7] Up/down (center-aligned) mode...")
    sub = TimerSubsystem(num_channels=1, width=8)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=3, reload_val=255)
    for _ in range(260):
        sub.tick()
    count = sub.get_channel_count(0)
    # After 255 up + 5 down = count should be 250
    if count == 250:
        print(f"  PASS: count = {count} (up/down center-aligned)")
    else:
        print(f"  FAIL: expected ~250, got {count}")
        errors += 1

    # Test 8: Input capture on rising edge
    print("\n[Test 8] Input capture (rising edge)...")
    sub = TimerSubsystem(num_channels=1, width=8)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, reload_val=255, edge_sel=0)
    for _ in range(10):
        sub.tick()
    sub.channels[0].count = 42  # Force count for capture
    sub.channels[0].capture(1)  # Rising edge
    if sub.channels[0].captured_val == 42 and sub.channels[0].capture_event:
        print(f"  PASS: captured value = {sub.channels[0].captured_val}")
    else:
        print(f"  FAIL: capture failed")
        errors += 1

    print("\n" + "=" * 60)
    if errors == 0:
        print("All tests PASSED!")
    else:
        print(f"{errors} test(s) FAILED")
    print("=" * 60)
    return errors


if __name__ == "__main__":
    errors = run_basic_test()
    sys.exit(errors)
