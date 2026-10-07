// =============================================================================
// Integration testbench: timer_top
// Focus: APB register semantics + end-to-end channel behavior.
// =============================================================================
`timescale 1ns/1ps

module timer_tb;

    localparam int unsigned NUM_CHANNELS = 4;
    localparam int unsigned WIDTH        = 32;
    localparam int unsigned APB_ADDR_W   = 12;
    localparam int unsigned CLK_PERIOD   = 10;

    localparam logic [5:0] REG_CTRL    = 6'h00;
    localparam logic [5:0] REG_STATUS  = 6'h04;
    localparam logic [5:0] REG_CNT     = 6'h08;
    localparam logic [5:0] REG_RELOAD  = 6'h0C;
    localparam logic [5:0] REG_COMPARE = 6'h10;
    localparam logic [5:0] REG_PWM_CMP = 6'h14;
    localparam logic [5:0] REG_CAPTURE = 6'h18;
    localparam logic [5:0] REG_EDGE    = 6'h1C;
    localparam logic [5:0] REG_INT_EN  = 6'h20;
    localparam logic [5:0] REG_INT_CLR = 6'h24;

    localparam logic [11:0] REG_GLOBAL_CTRL = 12'h400;
    localparam logic [11:0] REG_GLOBAL_IRQ  = 12'h404;
    localparam logic [11:0] REG_VERSION     = 12'h408;

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
    logic                    irq;

    logic [WIDTH-1:0] rd_data;
    int errors;
    int checks;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    timer_top #(
        .NUM_CHANNELS   (NUM_CHANNELS),
        .WIDTH          (WIDTH),
        .APB_ADDR_W     (APB_ADDR_W),
        .DEBOUNCE_DEPTH (0)
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

`ifdef ENABLE_ASSERTIONS
    timer_assertions #(
        .NUM_CHANNELS(NUM_CHANNELS),
        .WIDTH(WIDTH)
    ) u_assertions (
        .clk                 (clk),
        .rst_n               (rst_n),
        .paddr               (paddr),
        .psel                (psel),
        .penable             (penable),
        .pwrite              (pwrite),
        .pwdata              (pwdata),
        .pready              (pready),
        .channel_enable      (dut.channel_enable),
        .channel_count       (dut.channel_count),
        .channel_overflow    (dut.channel_overflow),
        .channel_underflow   (dut.channel_underflow),
        .channel_int_pending (dut.channel_int_pending),
        .irq                 (irq)
    );
`endif

    function automatic logic [APB_ADDR_W-1:0] ch_addr(
        input int ch,
        input logic [5:0] offset
    );
        ch_addr = (ch * 12'h040) + offset;
    endfunction

    task automatic init_bus;
        begin
            paddr      = '0;
            psel       = 1'b0;
            penable    = 1'b0;
            pwrite     = 1'b0;
            pwdata     = '0;
            capture_in = '0;
        end
    endtask

    task automatic do_reset;
        begin
            rst_n = 1'b0;
            init_bus();
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic apb_write(
        input logic [APB_ADDR_W-1:0] addr,
        input logic [WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            paddr   = addr;
            psel    = 1'b1;
            penable = 1'b0;
            pwrite  = 1'b1;
            pwdata  = data;

            @(negedge clk);
            penable = 1'b1;

            @(posedge clk);
            #1;
            if (!pready) begin
                while (!pready) begin
                    @(posedge clk);
                    #1;
                end
            end

            @(negedge clk);
            psel    = 1'b0;
            penable = 1'b0;
            pwrite  = 1'b0;
            pwdata  = '0;
        end
    endtask

    task automatic apb_read(
        input  logic [APB_ADDR_W-1:0] addr,
        output logic [WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            paddr   = addr;
            psel    = 1'b1;
            penable = 1'b0;
            pwrite  = 1'b0;
            pwdata  = '0;

            @(negedge clk);
            penable = 1'b1;

            @(posedge clk);
            #1;
            if (!pready) begin
                while (!pready) begin
                    @(posedge clk);
                    #1;
                end
            end
            data = prdata;

            @(negedge clk);
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    task automatic write_ch(
        input int ch,
        input logic [5:0] offset,
        input logic [WIDTH-1:0] data
    );
        begin
            apb_write(ch_addr(ch, offset), data);
        end
    endtask

    task automatic read_ch(
        input int ch,
        input logic [5:0] offset,
        output logic [WIDTH-1:0] data
    );
        begin
            apb_read(ch_addr(ch, offset), data);
        end
    endtask

    task automatic expect_eq(
        input string name,
        input logic [WIDTH-1:0] actual,
        input logic [WIDTH-1:0] expected
    );
        begin
            checks = checks + 1;
            if (actual === expected) begin
                $display("[PASS] %s: 0x%08h", name, actual);
            end else begin
                errors = errors + 1;
                $error("[FAIL] %s: expected 0x%08h, got 0x%08h",
                       name, expected, actual);
            end
        end
    endtask

    task automatic expect_true(
        input string name,
        input logic condition
    );
        begin
            checks = checks + 1;
            if (condition === 1'b1) begin
                $display("[PASS] %s", name);
            end else begin
                errors = errors + 1;
                $error("[FAIL] %s", name);
            end
        end
    endtask

    task automatic freeze_global;
        begin
            apb_write(REG_GLOBAL_CTRL, 32'h0000_0000);
            repeat (3) @(posedge clk);
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        init_bus();
        do_reset();

        $display("============================================================");
        $display("Multi-Channel Timer/Counter Integration Regression");
        $display("============================================================");

        // ---------------------------------------------------------------------
        // Register identity / mode encoding
        // ---------------------------------------------------------------------
        apb_read(REG_VERSION, rd_data);
        expect_eq("VERSION", rd_data, 32'h0001_0001);

        write_ch(0, REG_CTRL, 32'h0000_0001);
        read_ch(0, REG_CTRL, rd_data);
        expect_eq("CTRL up-mode readback", rd_data, 32'h0000_0001);

        write_ch(0, REG_CTRL, 32'h0000_0002);
        read_ch(0, REG_CTRL, rd_data);
        expect_eq("CTRL down-mode readback", rd_data, 32'h0000_0002);

        write_ch(0, REG_CTRL, 32'h0000_0003);
        read_ch(0, REG_CTRL, rd_data);
        expect_eq("CTRL up/down readback", rd_data, 32'h0000_0003);

        // ---------------------------------------------------------------------
        // CNT is independently writable and RELOAD does not preload CNT.
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'h1234_5678);
        read_ch(0, REG_CNT, rd_data);
        expect_eq("CNT software preload", rd_data, 32'h1234_5678);

        write_ch(0, REG_RELOAD, 32'h0000_0005);
        read_ch(0, REG_RELOAD, rd_data);
        expect_eq("RELOAD readback", rd_data, 32'h0000_0005);
        read_ch(0, REG_CNT, rd_data);
        expect_eq("RELOAD write does not alter CNT", rd_data, 32'h1234_5678);

        // ---------------------------------------------------------------------
        // Up mode
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'd10);
        write_ch(0, REG_CTRL, 32'h1);
        apb_write(REG_GLOBAL_CTRL, 32'h1); // enable, divide by 1
        repeat (12) @(posedge clk);
        freeze_global();
        read_ch(0, REG_CNT, rd_data);
        expect_true("Up mode increments", rd_data > 32'd10);

        // ---------------------------------------------------------------------
        // Down mode
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'd20);
        write_ch(0, REG_RELOAD, 32'd100);
        write_ch(0, REG_CTRL, 32'h2);
        apb_write(REG_GLOBAL_CTRL, 32'h1);
        repeat (8) @(posedge clk);
        freeze_global();
        read_ch(0, REG_CNT, rd_data);
        expect_true("Down mode decrements", (rd_data < 32'd20) && (rd_data > 0));

        // ---------------------------------------------------------------------
        // Overflow reload + sticky status
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'hFFFF_FFFF);
        write_ch(0, REG_RELOAD, 32'd5);
        write_ch(0, REG_CTRL, 32'h1);
        apb_write(REG_GLOBAL_CTRL, 32'h1);
        repeat (8) @(posedge clk);
        freeze_global();

        read_ch(0, REG_CNT, rd_data);
        expect_true("Overflow reload applied", (rd_data >= 32'd5) && (rd_data < 32'd20));

        read_ch(0, REG_STATUS, rd_data);
        expect_true("Overflow sticky STATUS bit", rd_data[1]);

        write_ch(0, REG_INT_CLR, 32'h1);
        read_ch(0, REG_STATUS, rd_data);
        expect_eq("STATUS clear", rd_data, 32'h0);

        // ---------------------------------------------------------------------
        // Up/down boundary behavior
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'hFFFF_FFFF);
        write_ch(0, REG_CTRL, 32'h3);
        apb_write(REG_GLOBAL_CTRL, 32'h1);
        repeat (8) @(posedge clk);
        freeze_global();
        read_ch(0, REG_CNT, rd_data);
        expect_true("Up/down turns around at max", rd_data < 32'hFFFF_FFFF);
        expect_true("Up/down direction switched to down",
                    dut.channel_counting_up[0] === 1'b0);

        // ---------------------------------------------------------------------
        // Compare interrupt + W1C
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'd4);
        write_ch(0, REG_COMPARE, 32'd5);
        write_ch(0, REG_INT_EN, 32'h1);
        write_ch(0, REG_CTRL, 32'h1);
        apb_write(REG_GLOBAL_CTRL, 32'h1);
        repeat (8) @(posedge clk);
        expect_true("Compare IRQ asserted", irq);

        apb_write(REG_GLOBAL_CTRL, 32'h0);
        write_ch(0, REG_INT_CLR, 32'h1);
        repeat (2) @(posedge clk);
        expect_true("IRQ clears after W1C", !irq);

        // ---------------------------------------------------------------------
        // Cascade: CH1 must count only when CH0 wraps.
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'hFFFF_FFFF);
        write_ch(0, REG_RELOAD, 32'h0);
        write_ch(0, REG_CTRL, 32'h1);

        write_ch(1, REG_CNT, 32'h0);
        write_ch(1, REG_CTRL, 32'h1);
        write_ch(1, REG_INT_EN, 32'h2); // cascade enable, IRQ disabled

        apb_write(REG_GLOBAL_CTRL, 32'h1);
        repeat (14) @(posedge clk);
        freeze_global();
        read_ch(1, REG_CNT, rd_data);
        expect_eq("Cascade increments CH1 exactly once", rd_data, 32'd1);

        // ---------------------------------------------------------------------
        // Input capture through synchronizer, with slow prescaler to hold CNT.
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'd42);
        write_ch(0, REG_EDGE, 32'h0); // rising
        write_ch(0, REG_CTRL, 32'h1);
        apb_write(REG_GLOBAL_CTRL, (32'd100 << 1) | 32'h1);
        repeat (3) @(posedge clk);
        capture_in[0] = 1'b1;
        repeat (6) @(posedge clk);
        capture_in[0] = 1'b0;
        read_ch(0, REG_CAPTURE, rd_data);
        expect_eq("Input capture value", rd_data, 32'd42);

        // ---------------------------------------------------------------------
        // PWM is a level signal between prescaler ticks.
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CNT, 32'd0);
        write_ch(0, REG_PWM_CMP, 32'd10);
        write_ch(0, REG_CTRL, 32'h1);
        apb_write(REG_GLOBAL_CTRL, (32'd100 << 1) | 32'h1);
        repeat (4) @(posedge clk);
        expect_true("PWM high below compare", pwm_out[0]);

        write_ch(0, REG_CNT, 32'd20);
        repeat (3) @(posedge clk);
        expect_true("PWM low above compare", !pwm_out[0]);

        // ---------------------------------------------------------------------
        // Prescaler sanity: divide-by-4 must count slower than divide-by-1.
        // ---------------------------------------------------------------------
        do_reset();
        write_ch(0, REG_CTRL, 32'h1);
        apb_write(REG_GLOBAL_CTRL, 32'h1);
        repeat (20) @(posedge clk);
        freeze_global();
        read_ch(0, REG_CNT, rd_data);
        begin
            logic [WIDTH-1:0] fast_count;
            logic [WIDTH-1:0] slow_count;
            fast_count = rd_data;

            do_reset();
            write_ch(0, REG_CTRL, 32'h1);
            apb_write(REG_GLOBAL_CTRL, (32'd3 << 1) | 32'h1); // divide by 4
            repeat (20) @(posedge clk);
            freeze_global();
            read_ch(0, REG_CNT, slow_count);
            expect_true("Prescaler divides count rate",
                        (slow_count > 0) && (slow_count < fast_count));
        end

        // Global IRQ register should be clear after final reset/sequence.
        apb_read(REG_GLOBAL_IRQ, rd_data);
        expect_true("GLOBAL_IRQ readable", !$isunknown(rd_data));

        $display("============================================================");
        $display("Checks: %0d  Errors: %0d", checks, errors);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $fatal(1, "%0d TEST(S) FAILED", errors);
        end
    end

    initial begin
        #2_000_000;
        $fatal(1, "TIMEOUT");
    end

endmodule
