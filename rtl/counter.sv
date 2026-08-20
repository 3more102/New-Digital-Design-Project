// =============================================================================
// Module: counter
// Description: Up/down counter with auto-reload, count modes, and cascade input.
// =============================================================================
module counter #(
    parameter int unsigned WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,           // Count enable (after prescaler)
    input  logic [1:0] mode,       // 00: stop, 01: up, 10: down, 11: up/down
    input  logic reload,           // 1 = reload counter from reload_val
    input  logic [WIDTH-1:0] reload_val,  // Value to reload on overflow/underflow
    input  logic cascade_in,       // External cascade trigger
    input  logic cascade_en,       // 1 = increment on cascade_in rising edge
    output logic [WIDTH-1:0] count,
    output logic overflow,         // Up-count overflow
    output logic underflow,        // Down-count underflow
    output logic counting_up       // Current counting direction (for center-align PWM)
);

    logic direction;  // 1 = counting up, 0 = counting down (for up/down mode)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count    <= '0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            direction <= 1'b1;
        end else begin
            overflow  <= 1'b0;
            underflow <= 1'b0;

            if (reload) begin
                count <= reload_val;
            end else if (enable || (cascade_en && cascade_in)) begin
                case (mode)
                    2'b01: begin  // Up count
                        if (count == {WIDTH{1'b1}}) begin
                            count   <= reload_val;
                            overflow <= 1'b1;
                        end else begin
                            count <= count + 1'b1;
                        end
                    end
                    2'b10: begin  // Down count
                        if (count == '0) begin
                            count    <= reload_val;
                            underflow <= 1'b1;
                        end else begin
                            count <= count - 1'b1;
                        end
                    end
                    2'b11: begin  // Up/down count
                        if (direction) begin
                            if (count == {WIDTH{1'b1}}) begin
                                count    <= count - 1'b1;
                                direction <= 1'b0;
                                overflow <= 1'b1;
                            end else begin
                                count <= count + 1'b1;
                            end
                        end else begin
                            if (count == '0) begin
                                count    <= count + 1'b1;
                                direction <= 1'b1;
                                underflow <= 1'b1;
                            end else begin
                                count <= count - 1'b1;
                            end
                        end
                    end
                    default: begin  // Stop (mode 00)
                        count <= count;
                    end
                endcase
            end
        end
    end

    // Expose direction for PWM center-align
    assign counting_up = direction;

endmodule
