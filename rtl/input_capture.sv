// =============================================================================
// Module: input_capture
// Description: Synchronizes an external capture input, optionally debounces it,
//              detects configured edges, and snapshots the current counter.
// =============================================================================
module input_capture #(
    parameter int unsigned WIDTH    = 32,
    parameter int unsigned DEBOUNCE = 4   // consecutive samples; 0 = disabled
) (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,
    input  logic capture_in,
    input  logic [WIDTH-1:0] count,
    input  logic [1:0] edge_sel,          // 00 rising, 01 falling, 10 both, 11 off
    output logic [WIDTH-1:0] captured_val,
    output logic capture_event
);

    // Two-flop synchronizer for the asynchronous external input.
    logic capture_meta;
    logic capture_sync;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capture_meta <= 1'b0;
            capture_sync <= 1'b0;
        end else begin
            capture_meta <= capture_in;
            capture_sync <= capture_meta;
        end
    end

    logic filtered_capture;

    generate
        if (DEBOUNCE == 0) begin : gen_no_debounce
            always_comb filtered_capture = capture_sync;
        end else if (DEBOUNCE == 1) begin : gen_single_sample_debounce
            logic stable_q;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    stable_q <= 1'b0;
                else if (enable)
                    stable_q <= capture_sync;
            end

            always_comb filtered_capture = stable_q;
        end else begin : gen_debounce
            logic [DEBOUNCE-1:0] sample_history;
            logic stable_q;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    sample_history <= '0;
                    stable_q       <= 1'b0;
                end else if (enable) begin
                    sample_history <= {sample_history[DEBOUNCE-2:0], capture_sync};

                    // Change the stable output only after DEBOUNCE identical
                    // samples. Intermediate patterns preserve the old level.
                    if (&sample_history)
                        stable_q <= 1'b1;
                    else if (~|sample_history)
                        stable_q <= 1'b0;
                end
            end

            always_comb filtered_capture = stable_q;
        end
    endgenerate

    logic filtered_d;
    logic rising_edge_detect;
    logic falling_edge_detect;
    logic capture_trigger;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            filtered_d <= 1'b0;
        else if (enable)
            filtered_d <= filtered_capture;
    end

    assign rising_edge_detect  =  filtered_capture & ~filtered_d;
    assign falling_edge_detect = ~filtered_capture &  filtered_d;

    always_comb begin
        case (edge_sel)
            2'b00: capture_trigger = rising_edge_detect;
            2'b01: capture_trigger = falling_edge_detect;
            2'b10: capture_trigger = rising_edge_detect | falling_edge_detect;
            default: capture_trigger = 1'b0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_val  <= '0;
            capture_event <= 1'b0;
        end else begin
            capture_event <= 1'b0;

            if (enable && capture_trigger) begin
                captured_val  <= count;
                capture_event <= 1'b1;
            end
        end
    end

endmodule
