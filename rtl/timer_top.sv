// =============================================================================
// Module: timer_top
// Description: Top-level multi-channel timer/counter subsystem.
//              Parameterized for number of channels and counter width.
//              Features: prescaler, compare match, PWM, input capture,
//                        channel cascade, and interrupt generation.
// =============================================================================

// Register Map Summary (see register_block.sv for full details):
//   Per channel (base + N*0x40):
//     0x00 CTRL, 0x04 STATUS, 0x08 CNT, 0x0C RELOAD,
//     0x10 COMPARE, 0x14 PWM_CMP, 0x18 CAPTURE, 0x1C EDGE,
//     0x20 INT_EN, 0x24 INT_CLR
//   Global (0x400+):
//     0x400 GLOBAL_CTRL, 0x404 GLOBAL_IRQ, 0x408 VERSION

module timer_top #(
    parameter int unsigned NUM_CHANNELS = 4,
    parameter int unsigned WIDTH        = 32,
    parameter int unsigned APB_ADDR_W   = 12,
    parameter int unsigned DEBOUNCE_DEPTH = 4,
    parameter int unsigned PRESCALER_WIDTH = 16
) (
    input  logic clk,
    input  logic rst_n,

    // APB slave interface
    input  logic [APB_ADDR_W-1:0] paddr,
    input  logic                  psel,
    input  logic                  penable,
    input  logic                  pwrite,
    input  logic [WIDTH-1:0]      pwdata,
    output logic [WIDTH-1:0]      prdata,
    output logic                  pready,
    output logic                  pslverr,

    // Timer external interfaces
    input  logic [NUM_CHANNELS-1:0] capture_in,   // External capture inputs
    output logic [NUM_CHANNELS-1:0] pwm_out,      // PWM outputs
    output logic                     irq           // Interrupt output
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // Register block outputs
    logic [NUM_CHANNELS-1:0]             channel_enable;
    logic [1:0]  [NUM_CHANNELS-1:0]      channel_mode;
    logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_reload;
    logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_compare;
    logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_pwm_cmp;
    logic [1:0]  [NUM_CHANNELS-1:0]      channel_edge_sel;
    logic [NUM_CHANNELS-1:0]             channel_cascade_en;
    logic [NUM_CHANNELS-1:0]             channel_reload_strobe;
    logic [NUM_CHANNELS-1:0]             channel_int_en;
    logic [NUM_CHANNELS-1:0]             channel_int_clr;
    logic                                global_enable;
    logic [15:0]                         prescaler_val;

    // Counter signals
    logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_count;
    logic [NUM_CHANNELS-1:0]             channel_overflow;
    logic [NUM_CHANNELS-1:0]             channel_underflow;
    logic [NUM_CHANNELS-1:0]             channel_counting_up;

    // Compare/PWM signals
    logic [NUM_CHANNELS-1:0]             channel_match;
    logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_captured;
    logic [NUM_CHANNELS-1:0]             channel_capture_event;

    // Prescaler tick
    logic prescaler_tick;

    // Cascade signals
    logic [NUM_CHANNELS-1:0] cascade_internal;

    // Interrupt signals
    logic [NUM_CHANNELS-1:0] channel_int_pending;

    // =========================================================================
    // Prescaler
    // =========================================================================
    prescaler #(
        .WIDTH(PRESCALER_WIDTH)
    ) u_prescaler (
        .clk    (clk),
        .rst_n  (rst_n),
        .enable (global_enable),
        .divisor(prescaler_val),
        .tick   (prescaler_tick)
    );

    // =========================================================================
    // Timer Channels
    // =========================================================================
    generate
        for (genvar i = 0; i < NUM_CHANNELS; i++) begin : gen_channels
            // Counter
            counter #(
                .WIDTH(WIDTH)
            ) u_counter (
                .clk         (clk),
                .rst_n       (rst_n),
                .enable      (prescaler_tick & global_enable & channel_enable[i]),
                .mode        (channel_mode[i]),
                .reload      (channel_reload_strobe[i]),
                .reload_val  (channel_reload[i]),
                .cascade_in  (i > 0 ? cascade_internal[i-1] : 1'b0),
                .cascade_en  (channel_cascade_en[i]),
                .count       (channel_count[i]),
                .overflow    (channel_overflow[i]),
                .underflow   (channel_underflow[i]),
                .counting_up (channel_counting_up[i])
            );

            // Cascade unit
            cascade_unit u_cascade (
                .clk        (clk),
                .rst_n      (rst_n),
                .trigger_in (channel_underflow[i] | channel_overflow[i]),
                .cascade_en (channel_cascade_en[i]),
                .cascade_out(cascade_internal[i])
            );

            // Compare unit
            compare_unit #(
                .WIDTH(WIDTH)
            ) u_compare (
                .clk        (clk),
                .rst_n      (rst_n),
                .enable     (prescaler_tick & global_enable & channel_enable[i]),
                .count      (channel_count[i]),
                .compare_val(channel_compare[i]),
                .compare_en (channel_enable[i]),
                .match      (channel_match[i]),
                .match_level()
            );

            // PWM generator
            pwm_generator #(
                .WIDTH(WIDTH)
            ) u_pwm (
                .clk        (clk),
                .rst_n      (rst_n),
                .enable     (prescaler_tick & global_enable & channel_enable[i]),
                .count      (channel_count[i]),
                .compare_val(channel_pwm_cmp[i]),
                .period_val (channel_reload[i]),
                .center_align(channel_mode[i] == 2'b11),
                .counting_up(channel_counting_up[i]),
                .pwm_en     (channel_enable[i]),
                .pwm_out    (pwm_out[i])
            );

            // Input capture
            input_capture #(
                .WIDTH   (WIDTH),
                .DEBOUNCE(DEBOUNCE_DEPTH)
            ) u_capture (
                .clk          (clk),
                .rst_n        (rst_n),
                .enable       (global_enable & channel_enable[i]),
                .capture_in   (capture_in[i]),
                .count        (channel_count[i]),
                .edge_sel     (channel_edge_sel[i]),
                .captured_val (channel_captured[i]),
                .capture_event(channel_capture_event[i])
            );
        end
    endgenerate

    // =========================================================================
    // Interrupt Controller
    // =========================================================================
    interrupt_controller #(
        .NUM_CHANNELS(NUM_CHANNELS)
    ) u_irq_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        .overflow_int     (channel_overflow),
        .underflow_int    (channel_underflow),
        .match_int        (channel_match),
        .capture_int      (channel_capture_event),
        .overflow_int_en  (channel_int_en),
        .underflow_int_en (channel_int_en),
        .match_int_en     (channel_int_en),
        .capture_int_en   (channel_int_en),
        .int_clr          (channel_int_clr),
        .int_pending      (channel_int_pending),
        .int_raw          (),
        .irq              (irq)
    );

    // =========================================================================
    // Register Block (APB Interface)
    // =========================================================================
    register_block #(
        .NUM_CHANNELS(NUM_CHANNELS),
        .WIDTH       (WIDTH),
        .APB_ADDR_W  (APB_ADDR_W)
    ) u_reg_block (
        .clk                (clk),
        .rst_n              (rst_n),
        .paddr              (paddr),
        .psel               (psel),
        .penable            (penable),
        .pwrite             (pwrite),
        .pwdata             (pwdata),
        .prdata             (prdata),
        .pready             (pready),
        .pslverr            (pslverr),
        .channel_enable     (channel_enable),
        .channel_mode       (channel_mode),
        .channel_reload     (channel_reload),
        .channel_compare    (channel_compare),
        .channel_pwm_cmp    (channel_pwm_cmp),
        .channel_edge_sel   (channel_edge_sel),
        .channel_cascade_en (channel_cascade_en),
        .channel_reload_strobe(channel_reload_strobe),
        .channel_count      (channel_count),
        .channel_captured   (channel_captured),
        .channel_overflow   (channel_overflow),
        .channel_underflow  (channel_underflow),
        .channel_match      (channel_match),
        .channel_capture_event(channel_capture_event),
        .channel_int_pending(channel_int_pending),
        .channel_int_en     (channel_int_en),
        .channel_int_clr    (channel_int_clr),
        .global_enable      (global_enable),
        .prescaler_val      (prescaler_val)
    );

endmodule
