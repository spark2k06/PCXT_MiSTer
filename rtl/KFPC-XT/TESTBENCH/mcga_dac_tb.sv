`timescale 1ns / 1ps

module mcga_dac_tb;

    reg        clock = 1'b0;
    reg        reset = 1'b1;
    reg        write_en = 1'b0;
    reg [7:0]  write_index = 8'h00;
    reg [5:0]  write_red = 6'h00;
    reg [5:0]  write_green = 6'h00;
    reg [5:0]  write_blue = 6'h00;
    reg [7:0]  sample_index = 8'h00;
    wire [5:0] sample_red;
    wire [5:0] sample_green;
    wire [5:0] sample_blue;
    wire [7:0] sample_red_8;
    wire [7:0] sample_green_8;
    wire [7:0] sample_blue_8;

    integer failures = 0;

    mcga_dac dut (
        .clock          (clock),
        .reset          (reset),
        .reset_palette  (1'b0),
        .write_en       (write_en),
        .write_index    (write_index),
        .write_red      (write_red),
        .write_green    (write_green),
        .write_blue     (write_blue),
        .component_write_en(1'b0),
        .component_write_index(8'h00),
        .component_select(2'd0),
        .component_data  (6'h00),
        .sample_index   (sample_index),
        .sample_red     (sample_red),
        .sample_green   (sample_green),
        .sample_blue    (sample_blue),
        .sample_red_8   (sample_red_8),
        .sample_green_8 (sample_green_8),
        .sample_blue_8  (sample_blue_8),
        .port_index     (8'h00),
        .port_red       (),
        .port_green     (),
        .port_blue      ()
    );

    always #5 clock = ~clock;

    task check_sample;
        input [7:0] index;
        input [5:0] expected_red;
        input [5:0] expected_green;
        input [5:0] expected_blue;
        begin
            sample_index = index;
            #1;
            if (sample_red !== expected_red ||
                sample_green !== expected_green ||
                sample_blue !== expected_blue) begin
                $display("FAIL sample index=%02h expected=%02h/%02h/%02h actual=%02h/%02h/%02h",
                         index, expected_red, expected_green, expected_blue,
                         sample_red, sample_green, sample_blue);
                failures = failures + 1;
            end
        end
    endtask

    task write_entry;
        input [7:0] index;
        input [5:0] red;
        input [5:0] green;
        input [5:0] blue;
        begin
            write_index = index;
            write_red = red;
            write_green = green;
            write_blue = blue;
            write_en = 1'b1;
            @(posedge clock);
            #1;
            write_en = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;
        #1;

        check_sample(8'h00, 6'h00, 6'h00, 6'h00);
        check_sample(8'h01, 6'h00, 6'h00, 6'h2A);
        check_sample(8'h0E, 6'h3F, 6'h3F, 6'h15);
        check_sample(8'h0F, 6'h3F, 6'h3F, 6'h3F);
        check_sample(8'h10, 6'h00, 6'h00, 6'h00);
        check_sample(8'h15, 6'h11, 6'h11, 6'h11);
        check_sample(8'h20, 6'h00, 6'h00, 6'h3F);
        check_sample(8'h34, 6'h00, 6'h3F, 6'h3F);
        check_sample(8'hE8, 6'h10, 6'h0B, 6'h0B);

        write_entry(8'h2A, 6'h01, 6'h23, 6'h3E);
        check_sample(8'h2A, 6'h01, 6'h23, 6'h3E);
        if (sample_red_8 !== 8'h04 || sample_green_8 !== 8'h8E || sample_blue_8 !== 8'hFB) begin
            $display("FAIL RGB expansion expected=04/8e/fb actual=%02h/%02h/%02h",
                     sample_red_8, sample_green_8, sample_blue_8);
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS mcga_dac_tb");
            $finish;
        end

        $display("FAIL mcga_dac_tb failures=%0d", failures);
        $finish;
    end

endmodule
