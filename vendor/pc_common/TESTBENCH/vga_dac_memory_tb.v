`timescale 1ns/1ps

module vga_dac_memory_tb;
    reg clock = 1'b0;
    always #5 clock = ~clock;

    reg reset = 1'b0;
    reg load_defaults = 1'b0;
    reg invalidate = 1'b0;
    reg write_en = 1'b0;
    reg [7:0] write_index = 8'd0;
    reg [5:0] write_red = 6'd0, write_green = 6'd0, write_blue = 6'd0;
    reg component_write_en = 1'b0;
    reg [7:0] component_write_index = 8'd0;
    reg [1:0] component_select = 2'd0;
    reg [5:0] component_data = 6'd0;
    reg [7:0] sample_index = 8'd0, port_index = 8'd0;
    wire [5:0] sample_red, sample_green, sample_blue;
    wire [7:0] sample_red_8, sample_green_8, sample_blue_8;
    wire sample_valid;
    wire [5:0] port_red, port_green, port_blue;
    wire port_valid;

    vga_dac dut (
        .clock(clock), .reset(reset), .load_defaults(load_defaults),
        .invalidate(invalidate), .write_en(write_en),
        .write_index(write_index), .write_red(write_red),
        .write_green(write_green), .write_blue(write_blue),
        .component_write_en(component_write_en),
        .component_write_index(component_write_index),
        .component_select(component_select), .component_data(component_data),
        .sample_index(sample_index), .sample_red(sample_red),
        .sample_green(sample_green), .sample_blue(sample_blue),
        .sample_red_8(sample_red_8), .sample_green_8(sample_green_8),
        .sample_blue_8(sample_blue_8), .sample_valid(sample_valid),
        .port_index(port_index), .port_red(port_red),
        .port_green(port_green), .port_blue(port_blue),
        .port_valid(port_valid)
    );

    reg [17:0] expected[0:255];
    reg [255:0] expected_valid;
    integer i, cycle;
    integer seed = 32'h286dac;
    reg [7:0] random_index;
    reg [17:0] random_rgb;

    task check_pair;
        input [7:0] pixel_address;
        input [7:0] io_address;
        begin
            sample_index = pixel_address;
            port_index = io_address;
            #1;
            if ({sample_red, sample_green, sample_blue} !== expected[pixel_address] ||
                sample_valid !== expected_valid[pixel_address] ||
                {port_red, port_green, port_blue} !== expected[io_address] ||
                port_valid !== expected_valid[io_address] ||
                sample_red_8 !== {sample_red, sample_red[5:4]} ||
                sample_green_8 !== {sample_green, sample_green[5:4]} ||
                sample_blue_8 !== {sample_blue, sample_blue[5:4]}) begin
                $display("pixel=%0d got=%h valid=%b expected=%h/%b", pixel_address,
                         {sample_red, sample_green, sample_blue}, sample_valid,
                         expected[pixel_address], expected_valid[pixel_address]);
                $display("port=%0d got=%h valid=%b expected=%h/%b", io_address,
                         {port_red, port_green, port_blue}, port_valid,
                         expected[io_address], expected_valid[io_address]);
                $fatal(1, "VGA DAC palette mismatch");
            end
        end
    endtask

    task tick;
        begin
            @(posedge clock);
            #1;
        end
    endtask

    initial begin
        #1;
        // These anchors check the fixed ROM independently of the behavioural
        // model used below for the many write and restore combinations.
        if (dut.sample_default_palette[0] !== 18'h00000 ||
            dut.sample_default_palette[1] !== 18'h0002a ||
            dut.sample_default_palette[15] !== 18'h3ffff ||
            dut.sample_default_palette[32] !== 18'h0003f ||
            dut.sample_default_palette[255] !== 18'h00000)
            $fatal(1, "VGA default palette changed");
        for (i = 0; i < 256; i = i + 1) begin
            expected[i] = dut.sample_default_palette[i];
            if (dut.port_default_palette[i] !== expected[i])
                $fatal(1, "Pixel and port default palettes differ at %0d", i);
        end

        reset = 1'b1;
        expected_valid = 256'd0;
        tick();
        reset = 1'b0;
        for (i = 0; i < 256; i = i + 1)
            check_pair(i[7:0], 8'(255 - i));

        load_defaults = 1'b1;
        expected_valid = {256{1'b1}};
        tick();
        load_defaults = 1'b0;
        check_pair(8'd1, 8'd32);

        // Full and component writes share a cycle-independent palette view.
        write_index = 8'd1;
        write_red = 6'h12;
        write_green = 6'h23;
        write_blue = 6'h34;
        write_en = 1'b1;
        tick();
        write_en = 1'b0;
        expected[1] = {6'h12, 6'h23, 6'h34};
        check_pair(8'd1, 8'd1);

        component_write_index = 8'd1;
        component_select = 2'd1;
        component_data = 6'h05;
        component_write_en = 1'b1;
        tick();
        component_write_en = 1'b0;
        expected[1][11:6] = 6'h05;
        check_pair(8'd1, 8'd1);

        invalidate = 1'b1;
        expected_valid = 256'd0;
        tick();
        invalidate = 1'b0;
        check_pair(8'd1, 8'd32); // Invalidation retains written colours.

        component_write_index = 8'd2;
        component_select = 2'd0;
        component_data = 6'h3d;
        component_write_en = 1'b1;
        tick();
        component_write_en = 1'b0;
        expected[2][17:12] = 6'h3d;
        expected_valid[2] = 1'b1;
        check_pair(8'd2, 8'd1); // Other components still use their defaults.

        // Loading defaults wins over a simultaneous palette write.
        write_en = 1'b1;
        load_defaults = 1'b1;
        expected_valid = {256{1'b1}};
        for (i = 0; i < 256; i = i + 1)
            expected[i] = dut.sample_default_palette[i];
        tick();
        write_en = 1'b0;
        load_defaults = 1'b0;
        for (i = 0; i < 256; i = i + 1)
            check_pair(i[7:0], 8'(255 - i));

        // Exercise read-after-write at both independent addresses.
        for (cycle = 0; cycle < 400; cycle = cycle + 1) begin
            random_index = $random(seed);
            random_rgb = $random(seed);
            if (cycle[0]) begin
                write_index = random_index;
                {write_red, write_green, write_blue} = random_rgb;
                write_en = 1'b1;
                tick();
                write_en = 1'b0;
                expected[random_index] = random_rgb;
                expected_valid[random_index] = 1'b1;
            end else begin
                component_write_index = random_index;
                component_select = cycle[2:1] % 3;
                component_data = random_rgb[5:0];
                component_write_en = 1'b1;
                tick();
                component_write_en = 1'b0;
                case (component_select)
                    2'd0: expected[random_index][17:12] = component_data;
                    2'd1: expected[random_index][11:6] = component_data;
                    2'd2: expected[random_index][5:0] = component_data;
                endcase
                expected_valid[random_index] = 1'b1;
            end
            check_pair(random_index, random_index);
            check_pair(random_index ^ 8'h55, random_index ^ 8'haa);
        end

        reset = 1'b1;
        expected_valid = 256'd0;
        for (i = 0; i < 256; i = i + 1)
            expected[i] = dut.sample_default_palette[i];
        tick();
        reset = 1'b0;
        for (i = 0; i < 256; i = i + 1)
            check_pair(i[7:0], 8'(255 - i));
        $display("PASS vga_dac_memory_tb");
        $finish;
    end
endmodule
