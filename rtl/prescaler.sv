// =============================================================================
// Module: prescaler
// Description: Parameterized clock prescaler for timer subsystem.
//              Divides input clock by (divisor + 1) to produce a tick output.
//              Divisor is a runtime-configurable input.
// =============================================================================
module prescaler #(
    parameter int unsigned WIDTH = 16  // Maximum divisor width
) (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,           // 1 = prescaler active, 0 = frozen
    input  logic [WIDTH-1:0] divisor,  // Clock division factor (0 = divide by 1)
    output logic tick              // Single-cycle pulse at divided rate
);

    logic [WIDTH-1:0] count;
    logic [WIDTH-1:0] limit;

    // divisor=0 means divide by 1 (every cycle), divisor=1 means divide by 2, etc.
    assign limit = (divisor == '0) ? '0 : divisor;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
            tick  <= 1'b0;
        end else if (enable) begin
            if (count >= limit) begin
                count <= '0;
                tick  <= 1'b1;
            end else begin
                count <= count + 1'b1;
                tick  <= 1'b0;
            end
        end else begin
            tick <= 1'b0;
        end
    end

endmodule
