// =============================================================================
// Module: counter
// Description: Up/down counter with software preload, wrap reload value,
//              count modes, and optional cascade-driven counting.
// =============================================================================
module counter #(
    parameter int unsigned WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,                    // Normal count enable pulse
    input  logic [1:0] mode,                // 00: stop, 01: up, 10: down, 11: up/down

    input  logic load,                      // Software preload strobe
    input  logic [WIDTH-1:0] load_val,      // Software preload value
    input  logic [WIDTH-1:0] reload_val,    // Value loaded on overflow/underflow

    input  logic cascade_in,                // Cascade pulse from previous channel
    input  logic cascade_en,                // 1 = count only on cascade_in
    output logic [WIDTH-1:0] count,
    output logic overflow,
    output logic underflow,
    output logic counting_up
);

    logic direction;  // 1 = up, 0 = down (up/down mode only)
    logic count_step;

    // In cascade mode the local prescaler path is intentionally suppressed.
    // This prevents a cascaded channel from counting both locally and from
    // the previous channel.
    assign count_step = cascade_en ? cascade_in : enable;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count      <= '0;
            overflow   <= 1'b0;
            underflow  <= 1'b0;
            direction  <= 1'b1;
        end else begin
            overflow  <= 1'b0;
            underflow <= 1'b0;

            if (load) begin
                count <= load_val;
            end else if (count_step) begin
                case (mode)
                    2'b01: begin  // Up
                        if (count == {WIDTH{1'b1}}) begin
                            count    <= reload_val;
                            overflow <= 1'b1;
                        end else begin
                            count <= count + {{(WIDTH-1){1'b0}}, 1'b1};
                        end
                    end

                    2'b10: begin  // Down
                        if (count == '0) begin
                            count     <= reload_val;
                            underflow <= 1'b1;
                        end else begin
                            count <= count - {{(WIDTH-1){1'b0}}, 1'b1};
                        end
                    end

                    2'b11: begin  // Up/down (center-aligned)
                        if (direction) begin
                            if (count == {WIDTH{1'b1}}) begin
                                count     <= count - {{(WIDTH-1){1'b0}}, 1'b1};
                                direction <= 1'b0;
                                overflow  <= 1'b1;
                            end else begin
                                count <= count + {{(WIDTH-1){1'b0}}, 1'b1};
                            end
                        end else begin
                            if (count == '0) begin
                                count      <= count + {{(WIDTH-1){1'b0}}, 1'b1};
                                direction  <= 1'b1;
                                underflow  <= 1'b1;
                            end else begin
                                count <= count - {{(WIDTH-1){1'b0}}, 1'b1};
                            end
                        end
                    end

                    default: begin
                        count <= count;
                    end
                endcase
            end
        end
    end

    assign counting_up = direction;

endmodule
