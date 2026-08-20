// =============================================================================
// Module: cascade_unit
// Description: Enables cascading timer channels. When enabled, the overflow/
//              underflow of one channel drives the count-enable of the next.
// =============================================================================
module cascade_unit (
    input  logic clk,
    input  logic rst_n,
    input  logic trigger_in,     // Cascade trigger from previous channel
    input  logic cascade_en,     // 1 = cascade mode enabled
    output logic cascade_out     // Cascade output (synchronized)
);

    logic trigger_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trigger_d <= 1'b0;
            cascade_out <= 1'b0;
        end else begin
            trigger_d <= trigger_in;
            cascade_out <= trigger_in & ~trigger_d & cascade_en;
        end
    end

endmodule
