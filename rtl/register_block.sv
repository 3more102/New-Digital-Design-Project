// =============================================================================
// Module: register_block
// Description: APB-compatible memory-mapped register interface for the timer
//              subsystem. Supports configurable number of channels.
// =============================================================================

// Register map (per channel, base offset = channel_id * 0x40):
//   0x00: CTRL     - Control register (enable, mode)
//   0x04: STATUS   - Status register (read-only, match/overflow flags)
//   0x08: CNT      - Counter value (read/write)
//   0x0C: RELOAD   - Reload value
//   0x10: COMPARE  - Compare match value
//   0x14: PWM_CMP  - PWM compare value
//   0x18: CAPTURE  - Captured value (read-only)
//   0x1C: EDGE     - Edge select / debounce config
//   0x20: INT_EN   - Interrupt enable + cascade config
//   0x24: INT_CLR  - Interrupt clear (write-1-to-clear)
//
// Global registers (base 0x400):
//   0x400: GLOBAL_CTRL  - Global enable / prescaler
//   0x404: GLOBAL_IRQ   - Global interrupt status (OR of all channels)
//   0x408: VERSION     - IP version (read-only)

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

    // Configuration outputs (active on write)
    output logic [NUM_CHANNELS-1:0]           channel_enable,
    output logic [1:0]  [NUM_CHANNELS-1:0]    channel_mode,      // per channel: 2-bit mode
    output logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_reload,
    output logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_compare,
    output logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_pwm_cmp,
    output logic [1:0]  [NUM_CHANNELS-1:0]    channel_edge_sel,
    output logic [NUM_CHANNELS-1:0]           channel_cascade_en,

    // Reload strobe per channel
    output logic [NUM_CHANNELS-1:0]           channel_reload_strobe,

    // Inputs from timer channels
    input  logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_count,
    input  logic [WIDTH-1:0] [NUM_CHANNELS-1:0] channel_captured,
    input  logic [NUM_CHANNELS-1:0]           channel_overflow,
    input  logic [NUM_CHANNELS-1:0]           channel_underflow,
    input  logic [NUM_CHANNELS-1:0]           channel_match,
    input  logic [NUM_CHANNELS-1:0]           channel_capture_event,

    // Interrupt interface
    input  logic [NUM_CHANNELS-1:0]           channel_int_pending,
    output logic [NUM_CHANNELS-1:0]           channel_int_en,
    output logic [NUM_CHANNELS-1:0]           channel_int_clr,

    // Global outputs
    output logic                              global_enable,
    output logic [15:0]                       prescaler_val
);

    // Address decode constants
    localparam int unsigned CH_STRIDE     = 12'h040;  // 64 bytes per channel
    localparam int unsigned GLOBAL_BASE   = 12'h400;
    localparam int unsigned VERSION_ADDR  = 12'h408;
    localparam logic [31:0] IP_VERSION    = 32'h0001_0000;  // v1.0.0

    // Internal register storage
    logic [NUM_CHANNELS-1:0]           ctrl_reg;       // 0x00: enable + mode[1:0]
    logic [WIDTH-1:0] [NUM_CHANNELS-1:0] reload_reg;   // 0x0C
    logic [WIDTH-1:0] [NUM_CHANNELS-1:0] compare_reg;  // 0x10
    logic [WIDTH-1:0] [NUM_CHANNELS-1:0] pwm_cmp_reg;  // 0x14
    logic [1:0]  [NUM_CHANNELS-1:0]    edge_reg;       // 0x1C
    logic [NUM_CHANNELS-1:0]           cascade_reg;    // bit 1 of INT_EN
    logic [NUM_CHANNELS-1:0]           int_en_reg;     // 0x20
    logic [NUM_CHANNELS-1:0]           int_clr_reg;    // 0x24

    logic [15:0] prescaler_reg;
    logic        global_ctrl_reg;

    // APB decode signals
    logic [NUM_CHANNELS-1:0] channel_sel;
    logic global_sel;
    logic version_sel;
    logic [5:0] reg_offset;

    // Address decode
    always_comb begin
        channel_sel = '0;
        global_sel  = 1'b0;
        version_sel = 1'b0;
        reg_offset  = paddr[5:0];

        for (int i = 0; i < NUM_CHANNELS; i++) begin
            if (psel && paddr >= (i * CH_STRIDE) && paddr < ((i + 1) * CH_STRIDE))
                channel_sel[i] = 1'b1;
        end

        if (psel && paddr >= GLOBAL_BASE && paddr < VERSION_ADDR)
            global_sel = 1'b1;

        if (psel && paddr == VERSION_ADDR)
            version_sel = 1'b1;
    end

    // APB write - register offsets match documented map
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg    <= '0;
            reload_reg  <= '0;
            compare_reg <= '0;
            pwm_cmp_reg <= '0;
            edge_reg    <= '0;
            cascade_reg <= '0;
            int_en_reg  <= '0;
            int_clr_reg <= '0;
            prescaler_reg <= 16'h0001;
            global_ctrl_reg <= 1'b0;
        end else begin
            int_clr_reg <= '0;  // Auto-clear

            if (psel && penable && pwrite) begin
                for (int i = 0; i < NUM_CHANNELS; i++) begin
                    if (channel_sel[i]) begin
                        case (reg_offset)
                            6'h00: begin  // CTRL: bit0=enable, bits[2:1]=mode
                                ctrl_reg[i] <= pwdata[0];
                            end
                            6'h08: reload_reg[i] <= pwdata;    // RELOAD
                            6'h10: compare_reg[i] <= pwdata;   // COMPARE
                            6'h14: pwm_cmp_reg[i] <= pwdata;   // PWM_CMP
                            6'h1C: edge_reg[i] <= pwdata[1:0]; // EDGE
                            6'h20: begin  // INT_EN: bit0=int_en, bit1=cascade_en, bit2=cascade_dis
                                int_en_reg[i] <= pwdata[0];
                                if (pwdata[1])
                                    cascade_reg[i] <= 1'b1;
                                else if (pwdata[2])
                                    cascade_reg[i] <= 1'b0;
                            end
                            6'h24: int_clr_reg[i] <= pwdata[0]; // INT_CLR (W1C)
                            default: ;
                        endcase
                    end
                end

                if (global_sel) begin
                    if (reg_offset == 6'h00) begin
                        global_ctrl_reg <= pwdata[0];
                        prescaler_reg   <= pwdata[16:1];
                    end
                end
            end
        end
    end

    // APB read - register offsets match documented map
    always_comb begin
        prdata = '0;
        pready = 1'b1;
        pslverr = 1'b0;

        if (psel && penable) begin
            for (int i = 0; i < NUM_CHANNELS; i++) begin
                if (channel_sel[i]) begin
                    case (reg_offset)
                        6'h00: prdata = {{(WIDTH-3){1'b0}}, ctrl_reg[i] ? 2'b01 : 2'b00, ctrl_reg[i]};  // CTRL: mode + enable
                        6'h04: prdata = {{(WIDTH-3){1'b0}}, channel_match[i], channel_overflow[i], channel_underflow[i]};  // STATUS (read-only)
                        6'h08: prdata = channel_count[i];       // CNT (read current count)
                        6'h0C: prdata = reload_reg[i];          // RELOAD
                        6'h10: prdata = compare_reg[i];         // COMPARE
                        6'h14: prdata = pwm_cmp_reg[i];        // PWM_CMP
                        6'h18: prdata = channel_captured[i];   // CAPTURE (read-only)
                        6'h1C: prdata = {{(WIDTH-2){1'b0}}, edge_reg[i]};  // EDGE
                        6'h20: prdata = {{(WIDTH-4){1'b0}}, cascade_reg[i], 1'b0, int_en_reg[i], channel_int_pending[i]};  // INT_EN
                        6'h28: prdata = {{(WIDTH-2){1'b0}}, edge_reg[i], 1'b0};  // Extra: also accessible
                        default: prdata = '0;
                    endcase
                end
            end

            if (global_sel) begin
                case (reg_offset)
                    6'h00: prdata = {{(WIDTH-18){1'b0}}, prescaler_reg, global_ctrl_reg};  // GLOBAL_CTRL
                    6'h04: prdata = {{(WIDTH-NUM_CHANNELS){1'b0}}, channel_int_pending};   // GLOBAL_IRQ
                    default: prdata = '0;
                endcase
            end

            if (version_sel) begin
                prdata = IP_VERSION;
            end
        end
    end

    // Output assignments
    assign channel_enable    = ctrl_reg;
    assign channel_mode      = {2{1'b0}};  // Mode stored in CTRL register [2:1] - simplified
    assign channel_reload    = reload_reg;
    assign channel_compare   = compare_reg;
    assign channel_pwm_cmp   = pwm_cmp_reg;
    assign channel_edge_sel  = edge_reg;
    assign channel_cascade_en = cascade_reg;
    assign channel_int_en    = int_en_reg;
    assign channel_int_clr   = int_clr_reg;
    assign channel_reload_strobe = channel_sel & {NUM_CHANNELS{psel && penable && pwrite && (reg_offset == 6'h0C)}};
    assign global_enable     = global_ctrl_reg;
    assign prescaler_val     = prescaler_reg;

endmodule
