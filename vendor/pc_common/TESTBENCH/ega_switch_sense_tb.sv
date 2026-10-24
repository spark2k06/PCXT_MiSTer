//============================================================================
//
//  IBM EGA monitor-switch readback.
//
//  The IBM BIOS selects each of the four switches by writing Miscellaneous
//  Output bits 3:2, then reads Input Status Register 0 bit 4 at the same 3C2h
//  port. In the order used by the BIOS (0Dh, 09h, 05h, 01h), the assembled
//  values must be 1001b for an IBM 5154/ECD, 0111b for an IBM 5153/CGA,
//  and 1011b for an IBM 5151/MDA.
//
//  Both halves of the port are checked here: ega_switch_sense_host must answer
//  the read, and ega_top must not - Input Status 0 has a single source in the
//  ISA clock domain. The splash override applies to the connector colour only;
//  the switches always report the profile the user selected, because the option
//  ROM may well read them while the boot artwork is still up.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_switch_sense_tb;

    logic clk = 1'b0;
    always #17.462 clk = ~clk;

    logic        reset = 1'b1;
    logic [14:0] bus_a = 15'h0000;
    logic [7:0]  bus_d = 8'h00;
    logic        bus_ior_l = 1'b1;
    logic        bus_iow_l = 1'b1;
    logic        bus_aen = 1'b0;
    logic [1:0]  ega_monitor_profile = 2'b00;
    logic        splashscreen = 1'b0;

    wire [7:0] bus_out;
    wire       bus_dir;
    wire [5:0] ega_red;
    wire [5:0] ega_green;
    wire [5:0] ega_blue;

    ega_top dut (
        .clk                         (clk),
        .reset                       (reset),
        .bus_a                       (bus_a),
        .bus_ior_l                   (bus_ior_l),
        .bus_iow_l                   (bus_iow_l),
        .bus_d                       (bus_d),
        .bus_out                     (bus_out),
        .bus_dir                     (bus_dir),
        .bus_aen                     (bus_aen),
        .ega_red                     (ega_red),
        .ega_green                   (ega_green),
        .ega_blue                    (ega_blue),
        .ega_plane0_data             (8'h00),
        .ega_plane1_data             (8'h00),
        .ega_plane2_data             (8'h00),
        .ega_plane3_data             (8'h00),
        .ega_fetch_data_valid        (1'b0),
        .ega_text_char               (8'h00),
        .ega_text_attr               (8'h00),
        .ega_text_glyph              (8'h00),
        .ega_text_data_valid         (1'b0), .ega_text_tag_in(1'b0),
        .cpu_mem_select              (1'b0),
        .cpu_mem_write               (1'b0),
        .prebios_video               (1'b0),
        .splashscreen                (splashscreen), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0),
        .thin_font                   (1'b0),
        .scandouble_en               (1'b0),
        .ega_enabled                 (1'b1),
        .ega_monitor_profile         (ega_monitor_profile),
        .crt_h_offset                (4'd0),
        .crt_v_offset                (3'd0),
        .vsync_width_osd             (3'd0),
        .hsync_width_osd             (3'd0)
    );

    // The ISA-domain half of the port. In the core this sits in Peripherals.sv
    // on the live 8088 cycle; here it shares the bench's bus for the same
    // reason it shares the CPU's in hardware.
    wire [7:0] host_data_out;
    wire       host_output_enable;

    ega_switch_sense_host host_path (
        .clock            (clk),
        .reset            (reset),
        .monitor_profile  (ega_monitor_profile),
        .io_address       (bus_a),
        .io_data          (bus_d),
        .io_write_n       (bus_iow_l),
        .io_read_n        (bus_ior_l),
        .address_enable_n (bus_aen),
        .data_out         (host_data_out),
        .output_enable    (host_output_enable)
    );

    integer errors = 0;

    task automatic io_write(input logic [14:0] address, input logic [7:0] data);
        begin
            @(posedge clk);
            bus_a <= address;
            bus_d <= data;
            bus_aen <= 1'b0;
            repeat (4) @(posedge clk);
            bus_iow_l <= 1'b0;
            repeat (8) @(posedge clk);
            bus_iow_l <= 1'b1;
            repeat (6) @(posedge clk);
        end
    endtask

    task automatic io_read(input logic [14:0] address, output logic [7:0] data);
        begin
            @(posedge clk);
            bus_a <= address;
            bus_aen <= 1'b0;
            repeat (4) @(posedge clk);
            bus_ior_l <= 1'b0;
            repeat (4) @(posedge clk);
            #1 data = host_data_out;
            if (host_output_enable !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: the ISA switch sense did not drive the 3C2h read");
            end
            if (bus_dir !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL: ega_top answered a 3C2h read; Input Status 0 must have one source");
            end
            repeat (4) @(posedge clk);
            bus_ior_l <= 1'b1;
            repeat (6) @(posedge clk);
        end
    endtask

    task automatic read_switch(
        input  logic [7:0] misc_output,
        output logic       switch_value
    );
        logic [7:0] status0;
        begin
            io_write(15'h03C2, misc_output);
            io_read(15'h03C2, status0);
            switch_value = status0[4];
            if ((status0 & 8'hEF) !== 8'h00) begin
                errors = errors + 1;
                $display("FAIL: unexpected Input Status 0 bits for Misc=%02h: %02h",
                         misc_output, status0);
            end
        end
    endtask

    task automatic read_bios_pattern(output logic [3:0] pattern);
        begin
            // This is the exact order and bit placement used by IBM ROM
            // 6277356 at offsets 009Bh-00CAh.
            read_switch(8'h0D, pattern[0]);
            read_switch(8'h09, pattern[1]);
            read_switch(8'h05, pattern[2]);
            read_switch(8'h01, pattern[3]);
        end
    endtask

    logic [3:0] pattern;

    initial begin
        repeat (10) @(posedge clk);
        reset <= 1'b0;
        repeat (10) @(posedge clk);

        read_bios_pattern(pattern);
        if (pattern !== 4'b1001) begin
            errors = errors + 1;
            $display("FAIL: IBM 5154/ECD pattern=%04b, expected 1001", pattern);
        end

        ega_monitor_profile <= 2'd1;
        repeat (4) @(posedge clk);
        read_bios_pattern(pattern);
        if (pattern !== 4'b0111) begin
            errors = errors + 1;
            $display("FAIL: IBM 5153/CGA 80-column pattern=%04b, expected 0111", pattern);
        end

        ega_monitor_profile <= 2'd2;
        repeat (4) @(posedge clk);

        read_bios_pattern(pattern);
        if (pattern !== 4'b1011) begin
            errors = errors + 1;
            $display("FAIL: IBM 5151/MDA pattern=%04b, expected 1011", pattern);
        end

        // A pending MDA profile must not turn the EGA-authored splash black:
        // the connector colour falls back to 5154/ECD while the artwork is up.
        // The switches do not, because the option ROM can read them at any
        // point during POST and must always see what the user selected.
        splashscreen <= 1'b1;
        repeat (4) @(posedge clk);
        read_bios_pattern(pattern);
        if (pattern !== 4'b1011) begin
            errors = errors + 1;
            $display("FAIL: splash switch pattern=%04b, expected the selected MDA 1011", pattern);
        end

        force dut.ega_video_selected = 6'b00_0001;
        #1;
        if ({ega_red, ega_green, ega_blue} !== {6'd0, 6'd0, 6'd42}) begin
            errors = errors + 1;
            $display("FAIL: splash under pending MDA RGB=%0d,%0d,%0d, expected EGA blue 0,0,42",
                     ega_red, ega_green, ega_blue);
        end
        release dut.ega_video_selected;
        splashscreen <= 1'b0;
        repeat (4) @(posedge clk);

        // In 5151 mode, connector bit 3 is Mono Video and bit 4 is its
        // intensity signal. Full Color must therefore still receive neutral
        // white, leaving the later OSD monochrome selector free to tint it.
        force dut.ega_video_selected = 6'b00_1000;
        #1;
        if ({ega_red, ega_green, ega_blue} !== {6'd42, 6'd42, 6'd42}) begin
            errors = errors + 1;
            $display("FAIL: IBM 5151 normal video RGB=%0d,%0d,%0d, expected 42,42,42",
                     ega_red, ega_green, ega_blue);
        end

        force dut.ega_video_selected = 6'b01_1000;
        #1;
        if ({ega_red, ega_green, ega_blue} !== {6'd63, 6'd63, 6'd63}) begin
            errors = errors + 1;
            $display("FAIL: IBM 5151 intense video RGB=%0d,%0d,%0d, expected 63,63,63",
                     ega_red, ega_green, ega_blue);
        end

        force dut.ega_video_selected = 6'b00_0000;
        #1;
        if ({ega_red, ega_green, ega_blue} !== 18'd0) begin
            errors = errors + 1;
            $display("FAIL: IBM 5151 blanking RGB=%0d,%0d,%0d, expected 0,0,0",
                     ega_red, ega_green, ega_blue);
        end
        release dut.ega_video_selected;

        if (errors == 0)
            $display("PASS: reset-time monitor profiles, EGA splash override and 5151 white levels are correct");
        else
            $display("FAIL: %0d monitor switch-sense checks failed", errors);

        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
