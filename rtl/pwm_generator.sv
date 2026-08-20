// =============================================================================
// Module: pwm_generator
// Description: Generates PWM output from counter and compare values.
//              Supports edge-aligned (up-count) and center-aligned (up/down) modes.
//              Edge-aligned: HIGH when count < compare
//              Center-aligned: HIGH when counting up AND count < compare,
//                              or counting down AND count >= compare
// =============================================================================
module pwm_generator #(
    parameter int unsigned WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,
    input  logic [WIDTH-1:0] count,      // Current counter value
    input  logic [WIDTH-1:0] compare_val, // Duty cycle compare value
    input  logic [WIDTH-1:0] period_val,  // Period value
    input  logic center_align,           // 1 = center-aligned, 0 = edge-aligned
    input  logic counting_up,            // 1 = counter counting up (for center-aligned)
    input  logic pwm_en,                 // 1 = PWM output enabled
    output logic pwm_out                 // PWM output signal
);

    logic pwm_next;

    always_comb begin
        if (!pwm_en || !enable) begin
            pwm_next = 1'b0;
        end else if (center_align) begin
            // Center-aligned: output HIGH when counting up AND count < compare,
            // or when counting down AND count >= compare
            // This creates a symmetric PWM waveform centered at the compare value
            if (counting_up) begin
                pwm_next = (count < compare_val);
            end else begin
                pwm_next = (count >= compare_val);
            end
        end else begin
            // Edge-aligned: output HIGH when count < compare_val
            pwm_next = (count < compare_val);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_out <= 1'b0;
        end else begin
            pwm_out <= pwm_next;
        end
    end

endmodule
