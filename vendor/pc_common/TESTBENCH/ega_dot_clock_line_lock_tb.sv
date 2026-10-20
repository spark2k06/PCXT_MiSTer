`timescale 1ns / 1ps
`default_nettype none

module ega_dot_clock_line_lock_tb;

    localparam integer LINE_DOTS = 776;
    localparam integer LINES_TO_CHECK = 12;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg clock_select = 1'b1;

    wire ce_dot;
    wire ce_dot_early;
    wire ce_dot_2x;
    wire dot_toggle;

    integer cycle_count = 0;
    integer last_dot_cycle = -1;
    integer dot_in_line = 0;
    integer sample_pos = 0;
    integer locked_lines = 0;
    integer gap;
    integer baseline_gap [0:LINE_DOTS-1];
    reg measuring = 1'b0;

    wire line_boundary = ce_dot && (dot_in_line == LINE_DOTS - 1);
`ifdef NO_LINE_LOCK
    wire line_lock = 1'b0;
`else
    wire line_lock = line_boundary;
`endif

    ega_dot_clock dut (
        .clk          (clk),
        .reset        (reset),
        .clock_select (clock_select),
        .line_lock    (line_lock),
        .ce_dot       (ce_dot),
        .ce_dot_early (ce_dot_early),
        .ce_dot_2x    (ce_dot_2x),
        .dot_toggle   (dot_toggle)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;

        if (reset) begin
            last_dot_cycle = -1;
            dot_in_line = 0;
            sample_pos = 0;
            locked_lines = 0;
            measuring = 1'b0;
        end else if (ce_dot) begin
            if (last_dot_cycle >= 0)
                gap = cycle_count - last_dot_cycle;
            else
                gap = 0;
            last_dot_cycle = cycle_count;

            if (measuring) begin
                if ((gap < 1) || (gap > 2))
                    $fatal(1, "Malformed dot gap %0d at line %0d dot %0d", gap, locked_lines, sample_pos);

                if (locked_lines == 1)
                    baseline_gap[sample_pos] = gap;
                else if (gap != baseline_gap[sample_pos])
                    $fatal(1, "Line pattern moved at line %0d dot %0d: expected %0d clocks, got %0d",
                           locked_lines, sample_pos, baseline_gap[sample_pos], gap);

                sample_pos = sample_pos + 1;
            end

            if (line_boundary) begin
                if (measuring && (sample_pos != LINE_DOTS))
                    $fatal(1, "Line contained %0d dots, expected %0d", sample_pos, LINE_DOTS);

                if (!measuring) begin
                    measuring = 1'b1;
                    locked_lines = 1;
                end else begin
                    locked_lines = locked_lines + 1;
                    if (locked_lines == LINES_TO_CHECK) begin
                        $display("PASS: %0d high-frequency lines repeated one identical dot-width pattern", LINES_TO_CHECK);
                        $finish;
                    end
                end

                sample_pos = 0;
                dot_in_line = 0;
            end else begin
                dot_in_line = dot_in_line + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        #1000000;
        $fatal(1, "Timed out waiting for line-lock regression to complete");
    end

endmodule

`default_nettype wire
