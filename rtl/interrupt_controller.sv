// =============================================================================
// Module: interrupt_controller
// Description: Manages interrupt generation for timer channels.
//              Supports per-channel masking and global interrupt output.
// =============================================================================
module interrupt_controller #(
    parameter int unsigned NUM_CHANNELS = 4
) (
    input  logic clk,
    input  logic rst_n,

    // Per-channel interrupt sources
    input  logic [NUM_CHANNELS-1:0] overflow_int,
    input  logic [NUM_CHANNELS-1:0] underflow_int,
    input  logic [NUM_CHANNELS-1:0] match_int,
    input  logic [NUM_CHANNELS-1:0] capture_int,

    // Per-channel interrupt enable masks
    input  logic [NUM_CHANNELS-1:0] overflow_int_en,
    input  logic [NUM_CHANNELS-1:0] underflow_int_en,
    input  logic [NUM_CHANNELS-1:0] match_int_en,
    input  logic [NUM_CHANNELS-1:0] capture_int_en,

    // Per-channel clear (write-1-to-clear)
    input  logic [NUM_CHANNELS-1:0] int_clr,

    // Per-channel raw and masked status
    output logic [NUM_CHANNELS-1:0] int_pending,
    output logic [NUM_CHANNELS-1:0] int_raw,    // Unmasked

    // Global interrupt output (active high, pulsed)
    output logic irq
);

    logic [NUM_CHANNELS-1:0] int_raw_next;
    logic [NUM_CHANNELS-1:0] int_pending_reg;

    // Raw interrupt (latched, any source triggers it)
    assign int_raw_next = (overflow_int & overflow_int_en) |
                          (underflow_int & underflow_int_en) |
                          (match_int & match_int_en) |
                          (capture_int & capture_int_en);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_pending_reg <= '0;
        end else begin
            // Set on new events, clear on write-1-to-clear
            int_pending_reg <= (int_pending_reg & ~int_clr) | int_raw_next;
        end
    end

    assign int_pending = int_pending_reg;
    assign int_raw     = (overflow_int | underflow_int | match_int | capture_int);
    assign irq         = |int_pending_reg;

endmodule
