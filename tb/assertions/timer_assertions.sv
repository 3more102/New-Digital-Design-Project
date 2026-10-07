// =============================================================================
// Assertion monitor for timer_top.
// Uses simulator-portable procedural assertions/checks so the same regression
// runs under Icarus Verilog while still enforcing protocol/behavior invariants.
// =============================================================================
module timer_assertions #(
    parameter int unsigned NUM_CHANNELS = 4,
    parameter int unsigned WIDTH        = 32
) (
    input logic clk,
    input logic rst_n,

    input logic [11:0]            paddr,
    input logic                   psel,
    input logic                   penable,
    input logic                   pwrite,
    input logic [WIDTH-1:0]       pwdata,
    input logic                   pready,

    input logic [NUM_CHANNELS-1:0]            channel_enable,
    input logic [NUM_CHANNELS-1:0][WIDTH-1:0] channel_count,
    input logic [NUM_CHANNELS-1:0]            channel_overflow,
    input logic [NUM_CHANNELS-1:0]            channel_underflow,
    input logic [NUM_CHANNELS-1:0]            channel_int_pending,
    input logic                               irq
);

    logic setup_seen;
    logic [11:0] setup_addr;
    logic setup_write;
    logic [WIDTH-1:0] setup_wdata;

    logic [NUM_CHANNELS-1:0][WIDTH-1:0] prev_count;
    logic [NUM_CHANNELS-1:0] prev_enable;
    logic prev_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            setup_seen  <= 1'b0;
            setup_addr  <= '0;
            setup_write <= 1'b0;
            setup_wdata <= '0;
            prev_count  <= '0;
            prev_enable <= '0;
            prev_valid  <= 1'b0;
        end else begin
            // APB setup must be followed by an access phase.
            if (setup_seen && !(psel && penable))
                $error("ASSERT APB: setup phase not followed by access phase");

            // PENABLE is only legal while PSEL is asserted.
            if (penable && !psel)
                $error("ASSERT APB: PENABLE asserted without PSEL");

            // This peripheral is zero-wait-state.
            if (psel && penable && !pready)
                $error("ASSERT APB: PREADY low during access phase");

            // Address/control/write-data must remain stable from setup to access.
            if (setup_seen && psel && penable) begin
                if (paddr !== setup_addr)
                    $error("ASSERT APB: PADDR changed between setup and access");
                if (pwrite !== setup_write)
                    $error("ASSERT APB: PWRITE changed between setup and access");
                if (setup_write && (pwdata !== setup_wdata))
                    $error("ASSERT APB: PWDATA changed between setup and access");
            end

            setup_seen <= psel && !penable;
            if (psel && !penable) begin
                setup_addr  <= paddr;
                setup_write <= pwrite;
                setup_wdata <= pwdata;
            end

            // Overflow/underflow events must originate at the corresponding
            // terminal value observed in the prior sampled cycle.
            if (prev_valid) begin
                for (int i = 0; i < NUM_CHANNELS; i++) begin
                    if (channel_overflow[i] &&
                        (prev_count[i] !== {WIDTH{1'b1}}))
                        $error("ASSERT CH%0d: overflow without prior max count", i);

                    if (channel_underflow[i] &&
                        (prev_count[i] !== {WIDTH{1'b0}}))
                        $error("ASSERT CH%0d: underflow without prior zero count", i);
                end
            end

            // Global IRQ is the OR of the pending channel bitmap.
            if (irq !== (|channel_int_pending))
                $error("ASSERT IRQ: irq does not match pending bitmap");

            prev_count  <= channel_count;
            prev_enable <= channel_enable;
            prev_valid  <= 1'b1;
        end
    end

endmodule
