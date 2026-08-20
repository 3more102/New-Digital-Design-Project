// =============================================================================
// Module: apb_bfm
// Description: APB Bus Functional Model (Master).
//              Provides tasks for APB read/write transactions.
// =============================================================================
module apb_bfm #(
    parameter int unsigned ADDR_W = 12,
    parameter int unsigned DATA_W = 32
) (
    output logic [ADDR_W-1:0] paddr,
    output logic              psel,
    output logic              penable,
    output logic              pwrite,
    output logic [DATA_W-1:0] pwdata,
    input  logic [DATA_W-1:0] prdata,
    input  logic              pready,
    input  logic              pslverr,
    input  logic              clk,
    input  logic              rst_n
);

    task automatic init();
        paddr   = '0;
        psel    = 1'b0;
        penable = 1'b0;
        pwrite  = 1'b0;
        pwdata  = '0;
    endtask

    task automatic write(
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] data
    );
        // Setup phase
        @(posedge clk);
        paddr   <= addr;
        psel    <= 1'b1;
        pwrite  <= 1'b1;
        pwdata  <= data;
        penable <= 1'b0;

        // Access phase
        @(posedge clk);
        penable <= 1'b1;

        // Wait for ready
        wait(pready);
        @(posedge clk);

        // Deassert
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
        @(posedge clk);
    endtask

    task automatic read(
        input  logic [ADDR_W-1:0] addr,
        output logic [DATA_W-1:0] data
    );
        // Setup phase
        @(posedge clk);
        paddr   <= addr;
        psel    <= 1'b1;
        pwrite  <= 1'b0;
        pwdata  <= '0;
        penable <= 1'b0;

        // Access phase
        @(posedge clk);
        penable <= 1'b1;

        // Wait for ready
        wait(pready);
        data = prdata;
        @(posedge clk);

        // Deassert
        psel    <= 1'b0;
        penable <= 1'b0;
        @(posedge clk);
    endtask

    // Register map helpers (per-channel offsets)
    localparam logic [ADDR_W-1:0] CH_STRIDE = 12'h040;

    function automatic logic [ADDR_W-1:0] ch_base(int ch_id);
        return ch_id * CH_STRIDE;
    endfunction

    task automatic write_reg(input int ch_id, input logic [5:0] offset,
                             input logic [DATA_W-1:0] data);
        write(ch_base(ch_id) + offset, data);
    endtask

    task automatic read_reg(input int ch_id, input logic [5:0] offset,
                            output logic [DATA_W-1:0] data);
        read(ch_base(ch_id) + offset, data);
    endtask

endmodule
