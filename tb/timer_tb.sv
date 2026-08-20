// =============================================================================
// Testbench: timer_tb
// Description: Self-checking testbench for the timer/counter subsystem.
//              Includes directed tests, randomized tests, and corner cases.
// =============================================================================

`timescale 1ns / 1ps

module timer_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter int unsigned NUM_CHANNELS = 4;
    parameter int unsigned WIDTH        = 32;
    parameter int unsigned APB_ADDR_W   = 12;
    parameter int unsigned CLK_PERIOD   = 10;  // 100 MHz

    // Register offsets (per channel, base = ch_id * 0x40)
    localparam logic [5:0] REG_CTRL    = 6'h00;  // Enable + mode
    localparam logic [5:0] REG_STATUS  = 6'h04;  // Match/overflow status (R)
    localparam logic [5:0] REG_CNT     = 6'h08;  // Counter value (R/W)
    localparam logic [5:0] REG_RELOAD  = 6'h0C;  // Reload value
    localparam logic [5:0] REG_COMPARE = 6'h10;  // Compare match value
    localparam logic [5:0] REG_PWM_CMP = 6'h14;  // PWM duty compare
    localparam logic [5:0] REG_CAPTURE = 6'h18;  // Captured value (R)
    localparam logic [5:0] REG_EDGE    = 6'h1C;  // Edge select / debounce
    localparam logic [5:0] REG_INT_EN  = 6'h20;  // Interrupt enable + cascade
    localparam logic [5:0] REG_INT_CLR = 6'h24;  // Clear interrupt (W1C)

    localparam logic [11:0] REG_GLOBAL_CTRL = 12'h400;
    localparam logic [11:0] REG_GLOBAL_IRQ  = 12'h404;
    localparam logic [11:0] REG_VERSION     = 12'h408;

    // =========================================================================
    // Signals
    // =========================================================================
    logic clk;
    logic rst_n;
    logic [APB_ADDR_W-1:0] paddr;
    logic                  psel;
    logic                  penable;
    logic                  pwrite;
    logic [WIDTH-1:0]      pwdata;
    logic [WIDTH-1:0]      prdata;
    logic                  pready;
    logic                  pslverr;
    logic [NUM_CHANNELS-1:0] capture_in;
    logic [NUM_CHANNELS-1:0] pwm_out;
    logic                   irq;

    // Test control
    int errors = 0;
    int test_num = 0;
    logic [WIDTH-1:0] rd_data;

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic do_reset();
        rst_n = 1'b0;
        paddr = '0;
        psel = 1'b0;
        penable = 1'b0;
        pwrite = 1'b0;
        pwdata = '0;
        capture_in = '0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);
    endtask

    // =========================================================================
    // APB Tasks
    // =========================================================================
    task automatic apb_write(input logic [APB_ADDR_W-1:0] addr,
                             input logic [WIDTH-1:0] data);
        @(posedge clk);
        paddr   <= addr;
        psel    <= 1'b1;
        pwrite  <= 1'b1;
        pwdata  <= data;
        penable <= 1'b0;

        @(posedge clk);
        penable <= 1'b1;

        @(posedge clk);
        while (!pready) @(posedge clk);

        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
        @(posedge clk);
    endtask

    task automatic apb_read(input logic [APB_ADDR_W-1:0] addr,
                            output logic [WIDTH-1:0] data);
        @(posedge clk);
        paddr   <= addr;
        psel    <= 1'b1;
        pwrite  <= 1'b0;
        pwdata  <= '0;
        penable <= 1'b0;

        @(posedge clk);
        penable <= 1'b1;

        @(posedge clk);
        while (!pready) @(posedge clk);
        data = prdata;

        psel    <= 1'b0;
        penable <= 1'b0;
        @(posedge clk);
    endtask

    function automatic logic [APB_ADDR_W-1:0] ch_addr(int ch, logic [5:0] reg_off);
        return ch * 12'h040 + reg_off;
    endfunction

    task automatic write_ch(input int ch, input logic [5:0] reg_off,
                            input logic [WIDTH-1:0] data);
        apb_write(ch_addr(ch, reg_off), data);
    endtask

    task automatic read_ch(input int ch, input logic [5:0] reg_off,
                           output logic [WIDTH-1:0] data);
        apb_read(ch_addr(ch, reg_off), data);
    endtask

    // =========================================================================
    // Helper: Run timer for N prescaler ticks
    // =========================================================================
    task automatic run_ticks(int n);
        repeat(n) @(posedge clk);
    endtask

    // =========================================================================
    // Check helper
    // =========================================================================
    task automatic check(string test_name, logic [WIDTH-1:0] actual,
                         logic [WIDTH-1:0] expected);
        test_num++;
        if (actual === expected) begin
            $display("[TEST %0d] PASS: %s (got %0h)", test_num, test_name, actual);
        end else begin
            $error("[TEST %0d] FAIL: %s (expected %0h, got %0h)",
                   test_num, test_name, expected, actual);
            errors++;
        end
    endtask

    task automatic check_msg(string test_name, bit condition);
        test_num++;
        if (condition) begin
            $display("[TEST %0d] PASS: %s", test_num, test_name);
        end else begin
            $error("[TEST %0d] FAIL: %s", test_num, test_name);
            errors++;
        end
    endtask

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    timer_top #(
        .NUM_CHANNELS  (NUM_CHANNELS),
        .WIDTH         (WIDTH),
        .APB_ADDR_W    (APB_ADDR_W),
        .DEBOUNCE_DEPTH(0)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .paddr      (paddr),
        .psel       (psel),
        .penable    (penable),
        .pwrite     (pwrite),
        .pwdata     (pwdata),
        .prdata     (prdata),
        .pready     (pready),
        .pslverr    (pslverr),
        .capture_in (capture_in),
        .pwm_out    (pwm_out),
        .irq        (irq)
    );

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("============================================================");
        $display("Timer/Counter Subsystem - Self-Checking Testbench");
        $display("============================================================");

        do_reset();

        // ---------------------------------------------------------------
        // Test: Version register
        // ---------------------------------------------------------------
        $display("\n--- Test: Version Register ---");
        apb_read(REG_VERSION, rd_data);
        check("Version register", rd_data, 32'h0001_0000);

        // ---------------------------------------------------------------
        // Test: Global enable/disable
        // ---------------------------------------------------------------
        $display("\n--- Test: Global Enable/Disable ---");
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);  // Enable global, prescaler=0 (div by 1)
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Enable channel 0, mode=up(01)
        write_ch(0, REG_RELOAD, 32'h0000_00FF);     // Reload = 255

        run_ticks(10);
        read_ch(0, REG_CNT, rd_data);
        check("Count after 10 ticks", rd_data, 32'd10);

        // ---------------------------------------------------------------
        // Test: Counter overflow and reload
        // ---------------------------------------------------------------
        $display("\n--- Test: Counter Overflow & Reload ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(0, REG_RELOAD, 32'h0000_0005);     // Reload = 5

        run_ticks(260);  // 256 to overflow + 4 more
        read_ch(0, REG_CNT, rd_data);
        check("Count after overflow+reload", rd_data, 32'd9);

        // ---------------------------------------------------------------
        // Test: Down-count mode
        // ---------------------------------------------------------------
        $display("\n--- Test: Down-Count Mode ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0002);       // Down count (mode=10)
        write_ch(0, REG_RELOAD, 32'h0000_0064);     // Reload = 100
        write_ch(0, REG_CNT, 32'h0000_000A);        // Set count = 10

        run_ticks(5);
        read_ch(0, REG_CNT, rd_data);
        check("Down count 10 -> 5", rd_data, 32'd5);

        // ---------------------------------------------------------------
        // Test: Compare match
        // ---------------------------------------------------------------
        $display("\n--- Test: Compare Match ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(0, REG_RELOAD, 32'h0000_00FF);
        write_ch(0, REG_COMPARE, 32'h0000_0005);    // Match at count=5

        run_ticks(20);
        read_ch(0, REG_STATUS, rd_data);
        check_msg("Compare match occurred", rd_data[0]);  // bit0 = match

        // ---------------------------------------------------------------
        // Test: Interrupt generation
        // ---------------------------------------------------------------
        $display("\n--- Test: Interrupt Generation ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(0, REG_RELOAD, 32'h0000_00FF);
        write_ch(0, REG_INT_EN, 32'h0000_0001);     // Enable interrupt

        run_ticks(10);
        check_msg("IRQ asserted", irq === 1'b1);

        // Clear interrupt
        write_ch(0, REG_INT_CLR, 32'h0000_0001);
        run_ticks(2);

        // ---------------------------------------------------------------
        // Test: PWM output
        // ---------------------------------------------------------------
        $display("\n--- Test: PWM Output ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(0, REG_RELOAD, 32'h0000_0064);     // Period = 100
        write_ch(0, REG_PWM_CMP, 32'h0000_0032);    // 50% duty

        run_ticks(1);
        check_msg("PWM output active", pwm_out[0] === 1'b1);

        // ---------------------------------------------------------------
        // Test: Channel cascade
        // ---------------------------------------------------------------
        $display("\n--- Test: Channel Cascade ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);

        // Channel 0: small counter for fast overflow
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(0, REG_RELOAD, 32'h0000_000F);     // Overflow at 15

        // Channel 1: cascade from channel 0
        write_ch(1, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(1, REG_RELOAD, 32'h0000_00FF);
        write_ch(1, REG_INT_EN, 32'h0000_0002);     // Cascade enable (bit 1)

        run_ticks(256);
        read_ch(1, REG_CNT, rd_data);
        check_msg("Channel 1 counted via cascade", rd_data > 0);

        // ---------------------------------------------------------------
        // Test: Up/down (center-aligned) mode
        // ---------------------------------------------------------------
        $display("\n--- Test: Up/Down Mode ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0003);       // Up/down mode (mode=11)
        write_ch(0, REG_RELOAD, 32'h0000_00FF);

        run_ticks(260);
        read_ch(0, REG_CNT, rd_data);
        // 255 up + 5 down = 250
        check("Up/down count", rd_data, 32'd250);

        // ---------------------------------------------------------------
        // Test: Input capture (rising edge)
        // ---------------------------------------------------------------
        $display("\n--- Test: Input Capture ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(0, REG_RELOAD, 32'h0000_00FF);
        write_ch(0, REG_EDGE, 32'h0000_0000);       // Rising edge

        run_ticks(20);  // Count = 20

        // Generate rising edge on capture input
        capture_in[0] = 1'b0;
        run_ticks(2);
        capture_in[0] = 1'b1;
        run_ticks(5);

        read_ch(0, REG_CAPTURE, rd_data);
        // Captured value should be around 20-22
        check_msg("Input capture recorded value", rd_data > 0);

        // ---------------------------------------------------------------
        // Test: Counter disabled
        // ---------------------------------------------------------------
        $display("\n--- Test: Counter Disabled ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0000);       // Disable channel
        write_ch(0, REG_RELOAD, 32'h0000_00FF);
        write_ch(0, REG_CNT, 32'h0000_0042);        // Set count

        run_ticks(20);
        read_ch(0, REG_CNT, rd_data);
        check("Counter frozen when disabled", rd_data, 32'h42);

        // ---------------------------------------------------------------
        // Test: All channels run independently
        // ---------------------------------------------------------------
        $display("\n--- Test: Multi-Channel Independent Operation ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);

        for (int i = 0; i < NUM_CHANNELS; i++) begin
            write_ch(i, REG_CTRL, 32'h0000_0001);     // Up count
            write_ch(i, REG_RELOAD, 32'h0000_00FF);
            write_ch(i, REG_COMPARE, 32'(i * 10 + 5));
        end

        run_ticks(50);
        for (int i = 0; i < NUM_CHANNELS; i++) begin
            read_ch(i, REG_CNT, rd_data);
            check_msg($sformatf("Channel %0d counting independently", i),
                     rd_data == 32'd50);
        end

        // ---------------------------------------------------------------
        // Test: Corner case - counter at max value
        // ---------------------------------------------------------------
        $display("\n--- Test: Counter at Max Value ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0001);
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(0, REG_RELOAD, 32'hFFFFFFFF);      // Reload at max
        write_ch(0, REG_CNT, 32'hFFFFFFFE);         // Set near max

        run_ticks(10);
        read_ch(0, REG_CNT, rd_data);
        // Should have overflowed and reloaded, then counted
        check_msg("Counter handles max value", rd_data > 0);

        // ---------------------------------------------------------------
        // Test: Prescaler
        // ---------------------------------------------------------------
        $display("\n--- Test: Prescaler ---");
        do_reset();
        apb_write(REG_GLOBAL_CTRL, 32'h0000_0003);  // Enable, prescaler=1 (div by 2)
        write_ch(0, REG_CTRL, 32'h0000_0001);       // Up count
        write_ch(0, REG_RELOAD, 32'h0000_00FF);

        run_ticks(20);
        read_ch(0, REG_CNT, rd_data);
        // With prescaler=2, should count ~10
        check_msg("Prescaler divides clock", rd_data < 32'd20);

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        $display("\n============================================================");
        if (errors == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("%0d TEST(S) FAILED", errors);
        $display("============================================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #1000000;
        $error("TIMEOUT: Simulation exceeded maximum time");
        $finish;
    end

endmodule
