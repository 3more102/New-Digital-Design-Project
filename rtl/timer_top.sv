// =============================================================================
// Module: timer_top
// Description: Parameterized multi-channel timer/counter subsystem.
//              Multi-channel word buses are flattened for tool portability.
// =============================================================================
module timer_top #(
    parameter int unsigned NUM_CHANNELS    = 4,
    parameter int unsigned WIDTH           = 32,
    parameter int unsigned APB_ADDR_W      = 12,
    parameter int unsigned DEBOUNCE_DEPTH  = 4,
    parameter int unsigned PRESCALER_WIDTH = 16
) (
    input  logic clk,
    input  logic rst_n,

    input  logic [APB_ADDR_W-1:0] paddr,
    input  logic                  psel,
    input  logic                  penable,
    input  logic                  pwrite,
    input  logic [WIDTH-1:0]      pwdata,
    output logic [WIDTH-1:0]      prdata,
    output logic                  pready,
    output logic                  pslverr,

    input  logic [NUM_CHANNELS-1:0] capture_in,
    output logic [NUM_CHANNELS-1:0] pwm_out,
    output logic                    irq
);

    logic [NUM_CHANNELS-1:0]           channel_enable;
    logic [(NUM_CHANNELS*2)-1:0]       channel_mode;
    logic [(NUM_CHANNELS*WIDTH)-1:0]   channel_reload;
    logic [(NUM_CHANNELS*WIDTH)-1:0]   channel_compare;
    logic [(NUM_CHANNELS*WIDTH)-1:0]   channel_pwm_cmp;
    logic [(NUM_CHANNELS*2)-1:0]       channel_edge_sel;
    logic [NUM_CHANNELS-1:0]           channel_cascade_en;
    logic [NUM_CHANNELS-1:0]           channel_count_load_strobe;
    logic [(NUM_CHANNELS*WIDTH)-1:0]   channel_count_load_value;
    logic [NUM_CHANNELS-1:0]           channel_int_en;
    logic [NUM_CHANNELS-1:0]           channel_int_clr;
    logic                              global_enable;
    logic [15:0]                       prescaler_val;

    logic [(NUM_CHANNELS*WIDTH)-1:0]   channel_count;
    logic [NUM_CHANNELS-1:0]           channel_overflow;
    logic [NUM_CHANNELS-1:0]           channel_underflow;
    logic [NUM_CHANNELS-1:0]           channel_counting_up;
    logic [NUM_CHANNELS-1:0]           channel_match;
    logic [(NUM_CHANNELS*WIDTH)-1:0]   channel_captured;
    logic [NUM_CHANNELS-1:0]           channel_capture_event;

    logic prescaler_tick;
    logic [NUM_CHANNELS-1:0] cascade_internal;
    logic [NUM_CHANNELS-1:0] channel_int_pending;

    prescaler #(
        .WIDTH(PRESCALER_WIDTH)
    ) u_prescaler (
        .clk     (clk),
        .rst_n   (rst_n),
        .enable  (global_enable),
        .divisor (prescaler_val),
        .tick    (prescaler_tick)
    );

    generate
        for (genvar i = 0; i < NUM_CHANNELS; i++) begin : gen_channels
            logic cascade_source;
            logic channel_step;

            if (i == 0) begin : gen_first_channel
                assign cascade_source = 1'b0;
            end else begin : gen_cascaded_channel
                assign cascade_source = cascade_internal[i-1];
            end

            assign channel_step = channel_cascade_en[i] ?
                                  cascade_source :
                                  prescaler_tick;

            counter #(
                .WIDTH(WIDTH)
            ) u_counter (
                .clk         (clk),
                .rst_n       (rst_n),
                .enable      (prescaler_tick & global_enable & channel_enable[i]),
                .mode        (channel_mode[(i*2) +: 2]),
                .load        (channel_count_load_strobe[i]),
                .load_val    (channel_count_load_value[(i*WIDTH) +: WIDTH]),
                .reload_val  (channel_reload[(i*WIDTH) +: WIDTH]),
                .cascade_in  (cascade_source),
                .cascade_en  (channel_cascade_en[i]),
                .count       (channel_count[(i*WIDTH) +: WIDTH]),
                .overflow    (channel_overflow[i]),
                .underflow   (channel_underflow[i]),
                .counting_up (channel_counting_up[i])
            );

            cascade_unit u_cascade (
                .clk         (clk),
                .rst_n       (rst_n),
                .trigger_in  (channel_underflow[i] | channel_overflow[i]),
                .cascade_en  (1'b1),
                .cascade_out (cascade_internal[i])
            );

            compare_unit #(
                .WIDTH(WIDTH)
            ) u_compare (
                .clk         (clk),
                .rst_n       (rst_n),
                .enable      (channel_step & global_enable & channel_enable[i]),
                .count       (channel_count[(i*WIDTH) +: WIDTH]),
                .compare_val (channel_compare[(i*WIDTH) +: WIDTH]),
                .compare_en  (channel_enable[i]),
                .match       (channel_match[i]),
                .match_level ()
            );

            pwm_generator #(
                .WIDTH(WIDTH)
            ) u_pwm (
                .clk          (clk),
                .rst_n        (rst_n),
                .enable       (global_enable & channel_enable[i]),
                .count        (channel_count[(i*WIDTH) +: WIDTH]),
                .compare_val  (channel_pwm_cmp[(i*WIDTH) +: WIDTH]),
                .period_val   (channel_reload[(i*WIDTH) +: WIDTH]),
                .center_align (channel_mode[(i*2) +: 2] == 2'b11),
                .counting_up  (channel_counting_up[i]),
                .pwm_en       (channel_enable[i]),
                .pwm_out      (pwm_out[i])
            );

            input_capture #(
                .WIDTH    (WIDTH),
                .DEBOUNCE (DEBOUNCE_DEPTH)
            ) u_capture (
                .clk           (clk),
                .rst_n         (rst_n),
                .enable        (global_enable & channel_enable[i]),
                .capture_in    (capture_in[i]),
                .count         (channel_count[(i*WIDTH) +: WIDTH]),
                .edge_sel      (channel_edge_sel[(i*2) +: 2]),
                .captured_val  (channel_captured[(i*WIDTH) +: WIDTH]),
                .capture_event (channel_capture_event[i])
            );
        end
    endgenerate

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

    register_block #(
        .NUM_CHANNELS(NUM_CHANNELS),
        .WIDTH       (WIDTH),
        .APB_ADDR_W  (APB_ADDR_W)
    ) u_reg_block (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .paddr                     (paddr),
        .psel                      (psel),
        .penable                   (penable),
        .pwrite                    (pwrite),
        .pwdata                    (pwdata),
        .prdata                    (prdata),
        .pready                    (pready),
        .pslverr                   (pslverr),
        .channel_enable            (channel_enable),
        .channel_mode              (channel_mode),
        .channel_reload            (channel_reload),
        .channel_compare           (channel_compare),
        .channel_pwm_cmp           (channel_pwm_cmp),
        .channel_edge_sel          (channel_edge_sel),
        .channel_cascade_en        (channel_cascade_en),
        .channel_count_load_strobe (channel_count_load_strobe),
        .channel_count_load_value  (channel_count_load_value),
        .channel_count             (channel_count),
        .channel_captured          (channel_captured),
        .channel_overflow          (channel_overflow),
        .channel_underflow         (channel_underflow),
        .channel_match             (channel_match),
        .channel_capture_event     (channel_capture_event),
        .channel_int_pending       (channel_int_pending),
        .channel_int_en            (channel_int_en),
        .channel_int_clr           (channel_int_clr),
        .global_enable             (global_enable),
        .prescaler_val             (prescaler_val)
    );

endmodule
