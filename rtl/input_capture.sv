// =============================================================================
// Module: input_capture
// Description: Captures counter value on external signal edge transitions.
//              Includes optional debounce filtering.
// =============================================================================
module input_capture #(
    parameter int unsigned WIDTH     = 32,
    parameter int unsigned DEBOUNCE  = 4   // Debounce filter depth (0 = disabled)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,
    input  logic capture_in,        // External capture input
    input  logic [WIDTH-1:0] count, // Counter value to capture
    input  logic [1:0] edge_sel,    // 00: rising, 01: falling, 10: both, 11: disabled
    output logic [WIDTH-1:0] captured_val,  // Captured counter value
    output logic capture_event     // Capture event pulse
);

    // Debounce filter (shift register)
    localparam int unsigned DEPTH = (DEBOUNCE > 0) ? DEBOUNCE : 1;
    logic [DEPTH-1:0] debounce_reg;
    logic debounced;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounce_reg <= '0;
        end else if (enable) begin
            debounce_reg <= {debounce_reg[DEPTH-2:0], capture_in};
        end
    end

    assign debounced = (DEBOUNCE == 0) ? capture_in :
                       &debounce_reg;  // All bits must be 1

    // Edge detection
    logic debounced_d;
    logic rising_edge_detect, falling_edge_detect;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            debounced_d <= 1'b0;
        else if (enable)
            debounced_d <= debounced;
    end

    assign rising_edge_detect  = debounced & ~debounced_d;
    assign falling_edge_detect = ~debounced & debounced_d;

    logic capture_trigger;
    assign capture_trigger = (edge_sel == 2'b00) ? rising_edge_detect :
                             (edge_sel == 2'b01) ? falling_edge_detect :
                             (edge_sel == 2'b10) ? (rising_edge_detect | falling_edge_detect) :
                             1'b0;

    // Capture register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_val <= '0;
            capture_event <= 1'b0;
        end else if (enable && capture_trigger) begin
            captured_val <= count;
            capture_event <= 1'b1;
        end else begin
            capture_event <= 1'b0;
        end
    end

endmodule
