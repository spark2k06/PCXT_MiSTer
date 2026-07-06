`timescale 1ns / 1ps

module mcga_dac_io_tb;

    reg        clock = 1'b0;
    reg        reset = 1'b1;
    reg        read_index_write = 1'b0;
    reg        write_index_write = 1'b0;
    reg        data_write = 1'b0;
    reg        read_index_read = 1'b0;
    reg        write_index_read = 1'b0;
    reg        data_read = 1'b0;
    reg        reset_palette = 1'b0;
    reg [7:0]  io_data_in = 8'h00;
    wire [7:0] io_data_out;
    reg [7:0]  sample_index = 8'h00;
    wire [5:0] sample_red;
    wire [5:0] sample_green;
    wire [5:0] sample_blue;
    wire [7:0] sample_red_8;
    wire [7:0] sample_green_8;
    wire [7:0] sample_blue_8;

    integer failures = 0;

    mcga_dac_io dut (
        .clock              (clock),
        .reset              (reset),
        .reset_palette      (reset_palette),
        .read_index_write   (read_index_write),
        .write_index_write  (write_index_write),
        .data_write         (data_write),
        .read_index_read    (read_index_read),
        .write_index_read   (write_index_read),
        .data_read          (data_read),
        .io_data_in         (io_data_in),
        .io_data_out        (io_data_out),
        .sample_index       (sample_index),
        .sample_red         (sample_red),
        .sample_green       (sample_green),
        .sample_blue        (sample_blue),
        .sample_red_8       (sample_red_8),
        .sample_green_8     (sample_green_8),
        .sample_blue_8      (sample_blue_8)
    );

    always #5 clock = ~clock;

    task pulse_write_index;
        input [7:0] value;
        begin
            io_data_in = value;
            write_index_write = 1'b1;
            @(posedge clock);
            #1;
            write_index_write = 1'b0;
        end
    endtask

    task pulse_read_index;
        input [7:0] value;
        begin
            io_data_in = value;
            read_index_write = 1'b1;
            @(posedge clock);
            #1;
            read_index_write = 1'b0;
        end
    endtask

    task pulse_data_write;
        input [7:0] value;
        begin
            io_data_in = value;
            data_write = 1'b1;
            @(posedge clock);
            #1;
            data_write = 1'b0;
        end
    endtask

    task check_data_read;
        input [7:0] expected;
        input [8*64-1:0] message;
        begin
            data_read = 1'b1;
            #1;
            if (io_data_out !== expected) begin
                $display("FAIL %0s expected=%02h actual=%02h", message, expected, io_data_out);
                failures = failures + 1;
            end
            @(posedge clock);
            #1;
            data_read = 1'b0;
            @(posedge clock);
            #1;
        end
    endtask

    task check_held_data_read;
        input [7:0] expected;
        input [8*64-1:0] message;
        begin
            data_read = 1'b1;
            #1;
            if (io_data_out !== expected) begin
                $display("FAIL %0s expected=%02h actual=%02h", message, expected, io_data_out);
                failures = failures + 1;
            end
            repeat (3) @(posedge clock);
            #1;
            if (io_data_out !== expected) begin
                $display("FAIL %0s held expected=%02h actual=%02h", message, expected, io_data_out);
                failures = failures + 1;
            end
            data_read = 1'b0;
            @(posedge clock);
            #1;
        end
    endtask

    task check_index_read;
        input read_write_index;
        input [7:0] expected;
        input [8*64-1:0] message;
        begin
            if (read_write_index)
                write_index_read = 1'b1;
            else
                read_index_read = 1'b1;
            #1;
            if (io_data_out !== expected) begin
                $display("FAIL %0s expected=%02h actual=%02h", message, expected, io_data_out);
                failures = failures + 1;
            end
            write_index_read = 1'b0;
            read_index_read = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;
        #1;

        pulse_write_index(8'h20);
        check_index_read(1'b1, 8'h20, "03C8 write index readback");
        pulse_data_write(8'h01);
        pulse_data_write(8'h22);
        pulse_data_write(8'h3F);
        check_index_read(1'b1, 8'h21, "03C9 write auto-increment");

        sample_index = 8'h20;
        #1;
        if (sample_red !== 6'h01 || sample_green !== 6'h22 || sample_blue !== 6'h3F) begin
            $display("FAIL sampled DAC entry expected=01/22/3f actual=%02h/%02h/%02h",
                     sample_red, sample_green, sample_blue);
            failures = failures + 1;
        end

        pulse_data_write(8'h04);
        pulse_data_write(8'h05);
        pulse_data_write(8'h06);
        sample_index = 8'h21;
        #1;
        if (sample_red !== 6'h04 || sample_green !== 6'h05 || sample_blue !== 6'h06) begin
            $display("FAIL auto-increment DAC entry expected=04/05/06 actual=%02h/%02h/%02h",
                     sample_red, sample_green, sample_blue);
            failures = failures + 1;
        end

        pulse_read_index(8'h20);
        check_index_read(1'b0, 8'h20, "03C7 read index readback");
        check_data_read(8'h01, "03C9 red read");
        check_data_read(8'h22, "03C9 green read");
        check_data_read(8'h3F, "03C9 blue read");
        check_index_read(1'b0, 8'h21, "03C9 read auto-increment");

        check_data_read(8'h04, "03C9 next red read");
        check_data_read(8'h05, "03C9 next green read");
        check_data_read(8'h06, "03C9 next blue read");
        check_index_read(1'b0, 8'h22, "03C9 second read auto-increment");

        pulse_read_index(8'h20);
        check_held_data_read(8'h01, "03C9 held red read");
        check_data_read(8'h22, "03C9 advances once after held read");

        if (sample_red_8 !== 8'h10 || sample_green_8 !== 8'h14 || sample_blue_8 !== 8'h18) begin
            $display("FAIL sampled RGB expansion expected=10/14/18 actual=%02h/%02h/%02h",
                     sample_red_8, sample_green_8, sample_blue_8);
            failures = failures + 1;
        end

        reset_palette = 1'b1;
        @(posedge clock);
        #1;
        reset_palette = 1'b0;
        sample_index = 8'h20;
        #1;
        if (sample_red !== 6'h00 || sample_green !== 6'h18 || sample_blue !== 6'h30) begin
            $display("FAIL palette reset default entry 20h expected=00/18/30 actual=%02h/%02h/%02h",
                     sample_red, sample_green, sample_blue);
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS mcga_dac_io_tb");
            $finish;
        end

        $display("FAIL mcga_dac_io_tb failures=%0d", failures);
        $finish;
    end

endmodule
