from timer_golden_model import TimerChannel, TimerSubsystem


def test_up_count_basic():
    sub = TimerSubsystem(num_channels=1, width=8, prescaler_val=0)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, reload_val=0)

    for _ in range(10):
        sub.tick()

    assert sub.get_channel_count(0) == 10


def test_down_count_basic():
    sub = TimerSubsystem(num_channels=1, width=8, prescaler_val=0)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=2, reload_val=100)
    sub.channels[0].count = 10

    for _ in range(5):
        sub.tick()

    assert sub.get_channel_count(0) == 5


def test_overflow_uses_reload_value():
    sub = TimerSubsystem(num_channels=1, width=8, prescaler_val=0)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, reload_val=5)
    sub.channels[0].count = 0xFF

    sub.tick()

    assert sub.channels[0].overflow is True
    assert sub.get_channel_count(0) == 5


def test_underflow_uses_reload_value():
    sub = TimerSubsystem(num_channels=1, width=8, prescaler_val=0)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=2, reload_val=200)
    sub.channels[0].count = 0

    sub.tick()

    assert sub.channels[0].underflow is True
    assert sub.get_channel_count(0) == 200


def test_up_down_turnaround():
    sub = TimerSubsystem(num_channels=1, width=4, prescaler_val=0)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=3)
    sub.channels[0].count = 0xF

    sub.tick()

    assert sub.channels[0].overflow is True
    assert sub.channels[0].direction == 0
    assert sub.get_channel_count(0) == 0xE


def test_prescaler_divide_by_four():
    fast = TimerSubsystem(num_channels=1, width=8, prescaler_val=0)
    slow = TimerSubsystem(num_channels=1, width=8, prescaler_val=3)
    fast.global_enable = True
    slow.global_enable = True
    fast.set_channel_config(0, enabled=True, mode=1)
    slow.set_channel_config(0, enabled=True, mode=1)

    for _ in range(20):
        fast.tick()
        slow.tick()

    assert fast.get_channel_count(0) == 20
    assert slow.get_channel_count(0) == 5


def test_cascade_is_exclusive_of_local_prescaler():
    sub = TimerSubsystem(num_channels=2, width=4, prescaler_val=0)
    sub.global_enable = True

    sub.set_channel_config(0, enabled=True, mode=1, reload_val=0)
    sub.set_channel_config(1, enabled=True, mode=1, reload_val=0, cascade_en=True)
    sub.channels[0].count = 0xF
    sub.channels[1].count = 0

    sub.tick()
    assert sub.channels[0].overflow is True
    assert sub.channels[1].count == 1

    for _ in range(5):
        sub.tick()

    # CH0 has not wrapped again, so CH1 must not advance from local ticks.
    assert sub.channels[1].count == 1


def test_compare_sets_pending_interrupt():
    sub = TimerSubsystem(num_channels=1, width=8, prescaler_val=0)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, compare_val=5)

    for _ in range(5):
        sub.tick()

    assert sub.channels[0].match is True
    assert sub.get_irq() is True


def test_interrupt_clear():
    sub = TimerSubsystem(num_channels=1, width=8, prescaler_val=0)
    sub.global_enable = True
    sub.set_channel_config(0, enabled=True, mode=1, compare_val=1)

    sub.tick()
    assert sub.get_irq() is True

    sub.clear_irq(0)
    assert sub.get_irq() is False


def test_capture_rising_edge():
    ch = TimerChannel(width=8, enabled=True, edge_sel=0)
    ch.count = 42
    ch.capture(0)
    ch.capture(1)

    assert ch.capture_event is True
    assert ch.captured_val == 42
