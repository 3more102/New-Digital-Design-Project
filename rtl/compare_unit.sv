// =============================================================================
// Module: compare_unit
// Description: Generates match signals when counter equals compare register.
//              Supports single-shot and auto-reload modes.
// =============================================================================
module compare_unit #(
    parameter int unsigned WIDTH = 32  // Counter/comparator width
) (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,
    input  logic [WIDTH-1:0] count,       // Current counter value
    input  logic [WIDTH-1:0] compare_val, // Compare match value
    input  logic compare_en,              // 1 = compare matching enabled
    output logic match,                   // Match pulse (1 cycle)
    output logic match_level              // Match level (held until next tick)
);

    logic match_next;

    assign match_next = (count == compare_val) && compare_en && enable;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            match       <= 1'b0;
            match_level <= 1'b0;
        end else begin
            match       <= match_next;
            if (match_next)
                match_level <= ~match_level;
            else if (!enable)
                match_level <= 1'b0;
        end
    end

endmodule
