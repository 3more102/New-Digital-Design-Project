// =============================================================================
// Module: timer_assertions
// Description: Concurrent SVA assertions for the timer/counter subsystem.
//              Monitors protocol compliance, counter behavior, and
//              interrupt timing.
// =============================================================================
module timer_assertions #(
    parameter int unsigned NUM_CHANNELS = 4,
    parameter int unsigned WIDTH        = 32
) (
    input  logic clk,
    input  logic rst_n,

    // APB interface
    input  logic [11:0] paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [WIDTH-1:0] pwdata,
    input  logic [WIDTH-1:0] prdata,
    input  logic        pready,

    // Timer signals
    input  logic [NUM_CHANNELS-1:0] channel_enable,
    input  logic [WIDTH-1:0] channel_count_0,
    input  logic [WIDTH-1:0] channel_count_1,
    input  logic [WIDTH-1:0] channel_count_2,
    input  logic [WIDTH-1:0] channel_count_3,
    input  logic [NUM_CHANNELS-1:0] channel_overflow,
    input  logic [NUM_CHANNELS-1:0] channel_underflow,
    input  logic [NUM_CHANNELS-1:0] channel_match,
    input  logic irq
);

    // =========================================================================
    // APB Protocol Assertions
    // =========================================================================

    // APB: setup phase must be followed by access phase
    property apb_valid_sequence;
        @(posedge clk) disable iff (!rst_n)
        psel && !penable |=> psel && penable;
    endproperty

    a_apb_valid_sequence: assert property (apb_valid_sequence)
        else $error("APB: Setup phase not followed by access phase");

    // APB: pready must be asserted during valid transaction
    property apb_pready_asserted;
        @(posedge clk) disable iff (!rst_n)
        psel && penable |-> pready;
    endproperty

    a_apb_pready: assert property (apb_pready_asserted)
        else $error("APB: pready not asserted during valid transaction");

    // APB: write data stable during access phase
    property apb_write_data_stable;
        @(posedge clk) disable iff (!rst_n)
        psel && penable && pwrite |-> $stable(pwdata);
    endproperty

    a_apb_write_stable: assert property (apb_write_data_stable)
        else $error("APB: Write data changed during access phase");

    // APB: no spurious requests (psel=0 implies penable=0)
    property apb_no_spurious;
        @(posedge clk) disable iff (!rst_n)
        !psel |-> !penable;
    endproperty

    a_apb_no_spurious: assert property (apb_no_spurious)
        else $error("APB: penable asserted without psel");

    // =========================================================================
    // Counter Behavior Assertions (per channel)
    // =========================================================================

    // Channel 0 assertions
    property ch0_overflow_at_max;
        @(posedge clk) disable iff (!rst_n)
        channel_overflow[0] |-> channel_count_0 == {WIDTH{1'b1}};
    endproperty
    a_ch0_overflow: assert property (ch0_overflow_at_max)
        else $error("CH0: Overflow did not occur at max value");

    property ch0_underflow_at_zero;
        @(posedge clk) disable iff (!rst_n)
        channel_underflow[0] |-> channel_count_0 == '0;
    endproperty
    a_ch0_underflow: assert property (ch0_underflow_at_zero)
        else $error("CH0: Underflow did not occur at zero");

    property ch0_counter_frozen_when_disabled;
        @(posedge clk) disable iff (!rst_n)
        !channel_enable[0] |=> $stable(channel_count_0);
    endproperty
    a_ch0_frozen: assert property (ch0_counter_frozen_when_disabled)
        else $error("CH0: Counter changed while disabled");

    property ch0_match_implies_enabled;
        @(posedge clk) disable iff (!rst_n)
        channel_match[0] |-> channel_enable[0];
    endproperty
    a_ch0_match_enabled: assert property (ch0_match_implies_enabled)
        else $error("CH0: Match occurred while disabled");

    // Channel 1 assertions
    property ch1_overflow_at_max;
        @(posedge clk) disable iff (!rst_n)
        channel_overflow[1] |-> channel_count_1 == {WIDTH{1'b1}};
    endproperty
    a_ch1_overflow: assert property (ch1_overflow_at_max)
        else $error("CH1: Overflow did not occur at max value");

    property ch1_counter_frozen_when_disabled;
        @(posedge clk) disable iff (!rst_n)
        !channel_enable[1] |=> $stable(channel_count_1);
    endproperty
    a_ch1_frozen: assert property (ch1_counter_frozen_when_disabled)
        else $error("CH1: Counter changed while disabled");

    // =========================================================================
    // Interrupt Assertions
    // =========================================================================

    property irq_reflects_pending;
        @(posedge clk) disable iff (!rst_n)
        !irq |-> !(channel_overflow[0] | channel_underflow[0] | channel_match[0]);
    endproperty
    a_irq_reflects: assert property (irq_reflects_pending)
        else $error("IRQ deasserted while interrupt sources active");

    // =========================================================================
    // Cover Properties
    // =========================================================================

    cover_channel0_count_gt_zero: cover property (
        @(posedge clk) disable iff (!rst_n)
        channel_count_0 > 0
    );

    cover_channel0_overflow: cover property (
        @(posedge clk) disable iff (!rst_n)
        channel_overflow[0]
    );

    cover_channel0_match: cover property (
        @(posedge clk) disable iff (!rst_n)
        channel_match[0]
    );

    cover_irq_asserted: cover property (
        @(posedge clk) disable iff (!rst_n)
        irq
    );

endmodule
