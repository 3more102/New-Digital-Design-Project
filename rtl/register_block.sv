// =============================================================================
// Module: register_block
// Description: APB3-compatible register interface for the timer subsystem.
// =============================================================================
//
// Per-channel register map (base = channel_id * 0x40):
//   0x00 CTRL     R/W  mode: 0=stop, 1=up, 2=down, 3=up/down
//   0x04 STATUS   R    bit0=match, bit1=overflow, bit2=underflow, bit3=capture
//   0x08 CNT      R/W  current counter value / software preload
//   0x0C RELOAD   R/W  value loaded on counter overflow/underflow
//   0x10 COMPARE  R/W  compare value
//   0x14 PWM_CMP  R/W  PWM compare value
//   0x18 CAPTURE  R    last captured counter value
//   0x1C EDGE     R/W  0=rising, 1=falling, 2=both, 3=disabled
//   0x20 INT_EN   R/W  bit0=interrupt enable, bit1=cascade enable
//   0x24 INT_CLR  W1C  bit0 clears pending interrupt and sticky STATUS
//
// Global registers:
//   0x400 GLOBAL_CTRL R/W bit0=enable, bits[16:1]=prescaler divisor
//   0x404 GLOBAL_IRQ  R   pending channel bitmap
//   0x408 VERSION     R   IP version
// =============================================================================
module register_block #(
    parameter int unsigned NUM_CHANNELS = 4,
    parameter int unsigned WIDTH        = 32,
    parameter int unsigned APB_ADDR_W   = 12
) (
    input  logic clk,
    input  logic rst_n,

    // APB slave interface
    input  logic [APB_ADDR_W-1:0] paddr,
    input  logic                  psel,
    input  logic                  penable,
    input  logic                  pwrite,
    input  logic [WIDTH-1:0]      pwdata,
    output logic [WIDTH-1:0]      prdata,
    output logic                  pready,
    output logic                  pslverr,

    // Per-channel configuration
    output logic [NUM_CHANNELS-1:0]             channel_enable,
    output logic [NUM_CHANNELS-1:0][1:0]        channel_mode,
    output logic [NUM_CHANNELS-1:0][WIDTH-1:0]  channel_reload,
    output logic [NUM_CHANNELS-1:0][WIDTH-1:0]  channel_compare,
    output logic [NUM_CHANNELS-1:0][WIDTH-1:0]  channel_pwm_cmp,
    output logic [NUM_CHANNELS-1:0][1:0]        channel_edge_sel,
    output logic [NUM_CHANNELS-1:0]             channel_cascade_en,

    // Software counter preload
    output logic [NUM_CHANNELS-1:0]             channel_count_load_strobe,
    output logic [NUM_CHANNELS-1:0][WIDTH-1:0]  channel_count_load_value,

    // Inputs from timer channels
    input  logic [NUM_CHANNELS-1:0][WIDTH-1:0]  channel_count,
    input  logic [NUM_CHANNELS-1:0][WIDTH-1:0]  channel_captured,
    input  logic [NUM_CHANNELS-1:0]             channel_overflow,
    input  logic [NUM_CHANNELS-1:0]             channel_underflow,
    input  logic [NUM_CHANNELS-1:0]             channel_match,
    input  logic [NUM_CHANNELS-1:0]             channel_capture_event,

    // Interrupt interface
    input  logic [NUM_CHANNELS-1:0]             channel_int_pending,
    output logic [NUM_CHANNELS-1:0]             channel_int_en,
    output logic [NUM_CHANNELS-1:0]             channel_int_clr,

    // Global configuration
    output logic                                global_enable,
    output logic [15:0]                         prescaler_val
);

    localparam logic [APB_ADDR_W-1:0] CH_STRIDE    = 12'h040;
    localparam logic [APB_ADDR_W-1:0] GLOBAL_BASE  = 12'h400;
    localparam logic [APB_ADDR_W-1:0] VERSION_ADDR = 12'h408;
    localparam logic [31:0] IP_VERSION = 32'h0001_0001; // v1.0.1

    logic [NUM_CHANNELS-1:0][1:0]       ctrl_reg;
    logic [NUM_CHANNELS-1:0][WIDTH-1:0] reload_reg;
    logic [NUM_CHANNELS-1:0][WIDTH-1:0] compare_reg;
    logic [NUM_CHANNELS-1:0][WIDTH-1:0] pwm_cmp_reg;
    logic [NUM_CHANNELS-1:0][1:0]       edge_reg;
    logic [NUM_CHANNELS-1:0]            cascade_reg;
    logic [NUM_CHANNELS-1:0]            int_en_reg;
    logic [NUM_CHANNELS-1:0]            int_clr_reg;

    logic [NUM_CHANNELS-1:0][WIDTH-1:0] count_load_value_reg;
    logic [NUM_CHANNELS-1:0]            count_load_strobe_reg;
    logic [NUM_CHANNELS-1:0][3:0]       status_reg;

    logic [15:0] prescaler_reg;
    logic        global_ctrl_reg;

    logic [NUM_CHANNELS-1:0] channel_sel;
    logic global_sel;
    logic version_sel;
    logic [5:0] reg_offset;

    // -------------------------------------------------------------------------
    // Address decode
    // -------------------------------------------------------------------------
    always_comb begin
        channel_sel = '0;
        global_sel  = 1'b0;
        version_sel = 1'b0;
        reg_offset  = paddr[5:0];

        for (int i = 0; i < NUM_CHANNELS; i++) begin
            if (psel &&
                (paddr >= (i * CH_STRIDE)) &&
                (paddr < ((i + 1) * CH_STRIDE))) begin
                channel_sel[i] = 1'b1;
            end
        end

        if (psel && (paddr >= GLOBAL_BASE) && (paddr < VERSION_ADDR))
            global_sel = 1'b1;

        if (psel && (paddr == VERSION_ADDR))
            version_sel = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Register writes and sticky status
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg               <= '0;
            reload_reg             <= '0;
            compare_reg            <= '0;
            pwm_cmp_reg            <= '0;
            edge_reg               <= '0;
            cascade_reg            <= '0;
            int_en_reg             <= '0;
            int_clr_reg            <= '0;
            count_load_value_reg   <= '0;
            count_load_strobe_reg  <= '0;
            status_reg             <= '0;
            prescaler_reg          <= '0;
            global_ctrl_reg        <= 1'b0;
        end else begin
            int_clr_reg           <= '0;
            count_load_strobe_reg <= '0;

            // Sticky event status. New events survive a simultaneous clear.
            for (int i = 0; i < NUM_CHANNELS; i++) begin
                status_reg[i] <= status_reg[i] |
                                 {channel_capture_event[i],
                                  channel_underflow[i],
                                  channel_overflow[i],
                                  channel_match[i]};
            end

            if (psel && penable && pwrite) begin
                for (int i = 0; i < NUM_CHANNELS; i++) begin
                    if (channel_sel[i]) begin
                        case (reg_offset)
                            6'h00: begin
                                ctrl_reg[i] <= pwdata[1:0];
                            end

                            6'h08: begin
                                count_load_value_reg[i]  <= pwdata;
                                count_load_strobe_reg[i] <= 1'b1;
                            end

                            6'h0C: begin
                                reload_reg[i] <= pwdata;
                            end

                            6'h10: begin
                                compare_reg[i] <= pwdata;
                            end

                            6'h14: begin
                                pwm_cmp_reg[i] <= pwdata;
                            end

                            6'h1C: begin
                                edge_reg[i] <= pwdata[1:0];
                            end

                            6'h20: begin
                                int_en_reg[i]   <= pwdata[0];
                                cascade_reg[i]  <= pwdata[1];
                            end

                            6'h24: begin
                                if (pwdata[0]) begin
                                    int_clr_reg[i] <= 1'b1;
                                    status_reg[i] <=
                                        {channel_capture_event[i],
                                         channel_underflow[i],
                                         channel_overflow[i],
                                         channel_match[i]};
                                end
                            end

                            default: begin
                                // Read-only or reserved location: no write effect.
                            end
                        endcase
                    end
                end

                if (global_sel && (reg_offset == 6'h00)) begin
                    global_ctrl_reg <= pwdata[0];
                    prescaler_reg   <= pwdata[16:1];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // APB read mux
    // -------------------------------------------------------------------------
    always_comb begin
        prdata  = '0;
        pready  = 1'b1;
        pslverr = 1'b0;

        if (psel && penable) begin
            for (int i = 0; i < NUM_CHANNELS; i++) begin
                if (channel_sel[i]) begin
                    case (reg_offset)
                        6'h00: begin
                            prdata = '0;
                            prdata[1:0] = ctrl_reg[i];
                        end

                        6'h04: begin
                            prdata = '0;
                            prdata[3:0] = status_reg[i];
                        end

                        6'h08: prdata = channel_count[i];
                        6'h0C: prdata = reload_reg[i];
                        6'h10: prdata = compare_reg[i];
                        6'h14: prdata = pwm_cmp_reg[i];
                        6'h18: prdata = channel_captured[i];

                        6'h1C: begin
                            prdata = '0;
                            prdata[1:0] = edge_reg[i];
                        end

                        6'h20: begin
                            prdata = '0;
                            prdata[0] = int_en_reg[i];
                            prdata[1] = cascade_reg[i];
                        end

                        6'h24: prdata = '0;

                        default: prdata = '0;
                    endcase
                end
            end

            if (global_sel) begin
                case (reg_offset)
                    6'h00: begin
                        prdata = '0;
                        prdata[0]    = global_ctrl_reg;
                        prdata[16:1] = prescaler_reg;
                    end

                    6'h04: begin
                        prdata = '0;
                        prdata[NUM_CHANNELS-1:0] = channel_int_pending;
                    end

                    default: prdata = '0;
                endcase
            end

            if (version_sel)
                prdata = IP_VERSION;
        end
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    always_comb begin
        channel_enable = '0;
        for (int i = 0; i < NUM_CHANNELS; i++) begin
            channel_enable[i] = |ctrl_reg[i];
        end
    end

    assign channel_mode              = ctrl_reg;
    assign channel_reload            = reload_reg;
    assign channel_compare           = compare_reg;
    assign channel_pwm_cmp           = pwm_cmp_reg;
    assign channel_edge_sel          = edge_reg;
    assign channel_cascade_en        = cascade_reg;
    assign channel_count_load_strobe = count_load_strobe_reg;
    assign channel_count_load_value  = count_load_value_reg;
    assign channel_int_en            = int_en_reg;
    assign channel_int_clr           = int_clr_reg;
    assign global_enable             = global_ctrl_reg;
    assign prescaler_val             = prescaler_reg;

endmodule
